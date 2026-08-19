import SwiftUI
import PDFKit

/// Forma de avanzar por el documento. Por defecto, una página completa cada vez.
enum ReaderMode: String, CaseIterable, Identifiable {
    case paged           // pasar página en horizontal
    case pagedVertical   // pasar página en vertical
    case continuous      // rollo continuo

    var id: String { rawValue }

    var label: String {
        switch self {
        case .paged:         return "Página a página"
        case .pagedVertical: return "Página a página (vertical)"
        case .continuous:    return "Desplazamiento continuo"
        }
    }

    var icon: String {
        switch self {
        case .paged:         return "book.pages"
        case .pagedVertical: return "rectangle.portrait.arrowtriangle.2.outward"
        case .continuous:    return "scroll"
        }
    }
}

struct ReaderView: View {

    let itemID: UUID

    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    @AppStorage("reader.mode") private var mode: ReaderMode = .paged

    @State private var page: Int = 0
    @State private var pageCount: Int = 0
    @State private var showChrome = true
    @State private var jumpTarget: Int?

    private var item: LibraryItem? { store.item(id: itemID) }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if let item, FileStore.exists(item) {
                PDFKitView(
                    url: FileStore.fileURL(for: item),
                    startPage: item.lastPage,
                    mode: mode,
                    jumpTarget: $jumpTarget,
                    onPageChange: { newPage, total in
                        page = newPage
                        pageCount = total
                        store.recordProgress(itemID: itemID, page: newPage)
                    },
                    onTap: {
                        withAnimation(.easeInOut(duration: 0.2)) { showChrome.toggle() }
                    }
                )
                .ignoresSafeArea()
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundStyle(Theme.textFaint)
                    Text("No se encontró el archivo.")
                        .foregroundStyle(Theme.textMuted)
                    Button("Cerrar") { dismiss() }
                        .buttonStyle(SoftButtonStyle())
                }
            }

            if showChrome {
                VStack {
                    topBar
                    Spacer()
                    bottomBar
                }
                .transition(.opacity)
            }
        }
        .statusBarHidden(!showChrome)
        .onAppear {
            page = item?.lastPage ?? 0
            pageCount = item?.pageCount ?? 0
        }
        .onDisappear { store.saveNow() }
    }

    // MARK: - Barras

    private var topBar: some View {
        HStack(spacing: 14) {
            Button { dismiss() } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
            }

            Text(item?.title ?? "")
                .font(.footnote.weight(.medium))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                if let item { store.toggleFavorite(item) }
            } label: {
                Image(systemName: (item?.isFavorite ?? false) ? "star.fill" : "star")
                    .font(.system(size: 15))
                    .foregroundStyle((item?.isFavorite ?? false) ? Theme.star : Theme.text)
            }

            Menu {
                Picker("Modo de lectura", selection: $mode) {
                    ForEach(ReaderMode.allCases) { option in
                        Label(option.label, systemImage: option.icon).tag(option)
                    }
                }
                Button {
                    if let item { store.markFinished(item) }
                } label: {
                    Label("Marcar como leído", systemImage: "checkmark.circle")
                }
            } label: {
                Image(systemName: "textformat.size")
                    .font(.system(size: 15))
            }
        }
        .foregroundStyle(Theme.text)
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    private var bottomBar: some View {
        VStack(spacing: 8) {
            HStack {
                Text("Página \(page + 1) de \(max(pageCount, 1))")
                    .font(.caption.monospacedDigit())
                Spacer()
                Text("\(item?.progressPercent ?? 0)% leído")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.accent)
            }
            .foregroundStyle(Theme.textMuted)

            if pageCount > 1 {
                Slider(
                    value: Binding(
                        get: { Double(page) },
                        set: { newValue in
                            let target = Int(newValue.rounded())
                            page = target
                            jumpTarget = target
                        }
                    ),
                    in: 0...Double(pageCount - 1),
                    step: 1
                )
                .tint(Theme.accent)
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 26)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Puente a PDFKit

struct PDFKitView: UIViewRepresentable {

    let url: URL
    let startPage: Int
    let mode: ReaderMode
    @Binding var jumpTarget: Int?
    let onPageChange: (Int, Int) -> Void
    let onTap: () -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.backgroundColor = .black
        view.pageShadowsEnabled = false
        view.autoScales = true

        if let document = PDFDocument(url: url) {
            view.document = document
        }

        Self.apply(mode, to: view)
        context.coordinator.appliedMode = mode

        if let document = view.document, document.pageCount > 0 {
            let index = min(max(0, startPage), document.pageCount - 1)
            if let page = document.page(at: index) { view.go(to: page) }
        }

        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.pageChanged(_:)),
            name: .PDFViewPageChanged,
            object: view
        )

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.numberOfTapsRequired = 1
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)

        context.coordinator.pdfView = view
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if context.coordinator.appliedMode != mode {
            let current = view.currentPage
            Self.apply(mode, to: view)
            context.coordinator.appliedMode = mode
            if let current { view.go(to: current) }
        }

        if let target = jumpTarget,
           let document = view.document,
           target >= 0, target < document.pageCount,
           let page = document.page(at: target),
           view.currentPage != page {
            view.go(to: page)
            DispatchQueue.main.async { self.jumpTarget = nil }
        }
    }

    /// Configura PDFKit para que cada gesto pase una página completa,
    /// salvo que se elija explícitamente el desplazamiento continuo.
    private static func apply(_ mode: ReaderMode, to view: PDFView) {
        switch mode {
        case .paged:
            view.displayMode = .singlePage
            view.displayDirection = .horizontal
            view.usePageViewController(true, withViewOptions: [
                UIPageViewController.OptionsKey.interPageSpacing: 12
            ])
        case .pagedVertical:
            view.displayMode = .singlePage
            view.displayDirection = .vertical
            view.usePageViewController(true, withViewOptions: [
                UIPageViewController.OptionsKey.interPageSpacing: 12
            ])
        case .continuous:
            view.usePageViewController(false, withViewOptions: nil)
            view.displayMode = .singlePageContinuous
            view.displayDirection = .vertical
        }
        view.autoScales = true
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPageChange: onPageChange, onTap: onTap)
    }

    static func dismantleUIView(_ view: PDFView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
    }

    final class Coordinator: NSObject {
        weak var pdfView: PDFView?
        var appliedMode: ReaderMode?
        let onPageChange: (Int, Int) -> Void
        let onTap: () -> Void

        init(onPageChange: @escaping (Int, Int) -> Void, onTap: @escaping () -> Void) {
            self.onPageChange = onPageChange
            self.onTap = onTap
        }

        @objc func pageChanged(_ notification: Notification) {
            guard let view = pdfView,
                  let document = view.document,
                  let current = view.currentPage else { return }
            onPageChange(document.index(for: current), document.pageCount)
        }

        @objc func handleTap() { onTap() }
    }
}
