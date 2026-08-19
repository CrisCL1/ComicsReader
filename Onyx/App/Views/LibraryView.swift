import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var drive: DriveSync

    @State private var search = ""
    @State private var selectedTag: String?
    @State private var filter: ReadFilter = .all
    @State private var sort: LibrarySort = .recent

    @State private var openItem: LibraryItem?
    @State private var detailItem: LibraryItem?
    @State private var showImporter = false
    @State private var loadingItemID: UUID?

    private var results: [LibraryItem] {
        store.filtered(search: search, tag: selectedTag, filter: filter, sort: sort)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if store.items.isEmpty {
                    EmptyState(
                        icon: "books.vertical",
                        title: "Tu biblioteca está vacía",
                        message: "Usa la pestaña Buscar para abrir una web y descargar un PDF, o importa uno desde Archivos."
                    ) {
                        Button("Importar PDF") { showImporter = true }
                            .buttonStyle(SoftButtonStyle())
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            filters

                            ForEach(results) { item in
                                DocumentCard(
                                    item: item,
                                    onOpen: { open(item) },
                                    onToggleFavorite: { store.toggleFavorite(item) }
                                )
                                .contextMenu {
                                    contextMenu(for: item)
                                }
                                .overlay {
                                    if loadingItemID == item.id {
                                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                            .fill(.black.opacity(0.55))
                                            .overlay(ProgressView().tint(Theme.accent))
                                    }
                                }
                            }

                            if results.isEmpty {
                                Text("Nada coincide con este filtro.")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.textFaint)
                                    .padding(.top, 40)
                            }

                            Color.clear.frame(height: 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            }
            .navigationTitle("Biblioteca")
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .searchable(text: $search, prompt: "Buscar por título o etiqueta")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Ordenar", selection: $sort) {
                            ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0) }
                        }
                        Divider()
                        Button {
                            showImporter = true
                        } label: {
                            Label("Importar PDF", systemImage: "square.and.arrow.down")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result {
                    for url in urls {
                        if let item = store.addPDF(from: url) {
                            Task { await drive.handleNewImport(item, store: store) }
                        }
                    }
                }
            }
            .fullScreenCover(item: $openItem) { item in
                ReaderView(itemID: item.id)
            }
            .sheet(item: $detailItem) { item in
                DocumentDetailView(itemID: item.id)
            }
        }
    }

    // MARK: - Filtros

    private var filters: some View {
        VStack(spacing: 10) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ReadFilter.allCases) { option in
                        Chip(text: option.rawValue, selected: filter == option) {
                            filter = option
                        }
                    }
                }
                .padding(.horizontal, 2)
            }

            if !store.allTags.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Chip(text: "Todas", selected: selectedTag == nil, muted: true) {
                            selectedTag = nil
                        }
                        ForEach(store.allTags, id: \.self) { tag in
                            Chip(text: tag, selected: selectedTag == tag, muted: true) {
                                selectedTag = (selectedTag == tag) ? nil : tag
                            }
                        }
                    }
                    .padding(.horizontal, 2)
                }
            }
        }
        .padding(.bottom, 4)
    }

    // MARK: - Acciones

    @ViewBuilder
    private func contextMenu(for item: LibraryItem) -> some View {
        Button { detailItem = item } label: {
            Label("Detalles y etiquetas", systemImage: "tag")
        }
        Button { store.toggleFavorite(item) } label: {
            Label(item.isFavorite ? "Quitar de favoritos" : "Añadir a favoritos",
                  systemImage: item.isFavorite ? "star.slash" : "star")
        }
        Button { store.markFinished(item) } label: {
            Label("Marcar como leído", systemImage: "checkmark.circle")
        }
        Button { store.resetProgress(item) } label: {
            Label("Reiniciar progreso", systemImage: "arrow.counterclockwise")
        }

        Divider()

        if item.driveFileID == nil {
            Button { Task { await drive.upload(item, store: store) } } label: {
                Label("Subir a Drive", systemImage: "icloud.and.arrow.up")
            }
        } else if item.isLocalAvailable {
            Button { Task { await drive.offload(item, store: store) } } label: {
                Label("Liberar espacio local", systemImage: "internaldrive")
            }
        }

        Divider()

        Button(role: .destructive) {
            Task { await drive.deleteEverywhere(item, store: store) }
        } label: {
            Label("Eliminar", systemImage: "trash")
        }
    }

    private func open(_ item: LibraryItem) {
        if FileStore.exists(item) {
            openItem = item
            return
        }
        loadingItemID = item.id
        Task {
            let ok = await drive.fetch(item, store: store)
            loadingItemID = nil
            if ok, let fresh = store.item(id: item.id) { openItem = fresh }
        }
    }
}

// MARK: - Piezas reutilizables

struct Chip: View {
    let text: String
    let selected: Bool
    var muted: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(selected ? Theme.bg : Theme.textMuted)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(selected ? (muted ? Theme.accentAlt : Theme.accent) : Theme.surface)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(selected ? .clear : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

struct SoftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.bg)
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
            .background(Theme.accent.opacity(configuration.isPressed ? 0.7 : 1))
            .clipShape(Capsule())
    }
}

struct EmptyState<Actions: View>: View {
    let icon: String
    let title: String
    let message: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 34, weight: .ultraLight))
                .foregroundStyle(Theme.textFaint)
            Text(title)
                .font(.headline)
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textMuted)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            actions.padding(.top, 6)
        }
    }
}
