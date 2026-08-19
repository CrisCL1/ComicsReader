import SwiftUI

/// Ficha del documento: renombrar, etiquetas personalizadas, progreso, Drive.
struct DocumentDetailView: View {

    let itemID: UUID

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var drive: DriveSync
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var tags: [String] = []
    @State private var newTag = ""
    @State private var confirmDelete = false

    private var item: LibraryItem? { store.item(id: itemID) }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if let item {
                            header(item)
                            titleField
                            tagsSection
                            progressSection(item)
                            driveSection(item)
                            deleteButton
                        }
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Detalles")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cerrar") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Guardar") { save() }.fontWeight(.semibold)
                }
            }
            .onAppear {
                title = item?.title ?? ""
                tags = item?.tags ?? []
            }
            .confirmationDialog("¿Eliminar este documento?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Eliminar de todas partes", role: .destructive) {
                    if let item {
                        Task {
                            await drive.deleteEverywhere(item, store: store)
                            dismiss()
                        }
                    }
                }
                Button("Cancelar", role: .cancel) {}
            } message: {
                Text("Se borrará el PDF del iPhone y también de Google Drive si está allí.")
            }
        }
    }

    // MARK: - Secciones

    private func header(_ item: LibraryItem) -> some View {
        HStack(spacing: 14) {
            if let image = FileStore.loadThumbnail(for: item) {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 70, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("\(item.pageCount) páginas")
                Text(item.readableSize)
                Text("Añadido \(item.addedAt.formatted(date: .abbreviated, time: .omitted))")
                if let source = item.sourceURL {
                    Link("Ver origen", destination: source)
                        .font(.caption)
                        .tint(Theme.accentAlt)
                }
            }
            .font(.caption)
            .foregroundStyle(Theme.textMuted)
            Spacer()
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionLabel("Título")
            TextField("Título", text: $title)
                .textFieldStyle(.plain)
                .foregroundStyle(Theme.text)
                .padding(12)
                .card()
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Etiquetas")

            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        HStack(spacing: 6) {
                            Text(tag).font(.system(size: 12, weight: .medium))
                            Image(systemName: "xmark")
                                .font(.system(size: 9, weight: .bold))
                        }
                        .foregroundStyle(Theme.text)
                        .padding(.horizontal, 11)
                        .padding(.vertical, 6)
                        .background(Theme.surfaceHigh)
                        .clipShape(Capsule())
                        .onTapGesture { tags.removeAll { $0 == tag } }
                    }
                }
            }

            HStack(spacing: 8) {
                TextField("Nueva etiqueta", text: $newTag)
                    .textFieldStyle(.plain)
                    .foregroundStyle(Theme.text)
                    .autocorrectionDisabled()
                    .onSubmit(addTag)
                Button(action: addTag) {
                    Image(systemName: "plus.circle.fill")
                        .foregroundStyle(Theme.accent)
                }
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(12)
            .card()

            let suggestions = store.allTags.filter { candidate in
                !tags.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
            }
            if !suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(suggestions, id: \.self) { tag in
                            Chip(text: tag, selected: false, muted: true) { tags.append(tag) }
                        }
                    }
                }
            }
        }
    }

    private func progressSection(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Progreso")
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("\(item.progressPercent)% leído")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.text)
                    Spacer()
                    Text("p. \(item.lastPage + 1) / \(max(item.pageCount, 1))")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textMuted)
                }
                ProgressBar(value: item.progress)
                HStack(spacing: 10) {
                    Button("Marcar leído") { store.markFinished(item) }
                    Button("Reiniciar") { store.resetProgress(item) }
                }
                .font(.caption.weight(.medium))
                .tint(Theme.accentAlt)
            }
            .padding(14)
            .card()
        }
    }

    private func driveSection(_ item: LibraryItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Almacenamiento")
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: item.driveFileID != nil ? "checkmark.icloud" : "icloud.slash")
                        .foregroundStyle(item.driveFileID != nil ? Theme.accentAlt : Theme.textFaint)
                    Text(item.driveFileID != nil ? "Copia en Google Drive" : "Solo en este iPhone")
                        .font(.footnote)
                        .foregroundStyle(Theme.textMuted)
                    Spacer()
                    if drive.isBusy(item) { ProgressView().controlSize(.mini) }
                }

                HStack(spacing: 10) {
                    if item.driveFileID == nil {
                        Button("Subir a Drive") {
                            Task { await drive.upload(item, store: store) }
                        }
                    } else if item.isLocalAvailable {
                        Button("Liberar espacio") {
                            Task { await drive.offload(item, store: store) }
                        }
                    } else {
                        Button("Descargar de nuevo") {
                            Task { await drive.fetch(item, store: store) }
                        }
                    }
                    Spacer()
                }
                .font(.caption.weight(.medium))
                .tint(Theme.accent)
            }
            .padding(14)
            .card()
        }
    }

    private var deleteButton: some View {
        Button(role: .destructive) { confirmDelete = true } label: {
            HStack {
                Spacer()
                Label("Eliminar documento", systemImage: "trash")
                    .font(.subheadline.weight(.medium))
                Spacer()
            }
            .padding(.vertical, 13)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        }
        .tint(Theme.danger)
        .padding(.top, 6)
    }

    // MARK: - Acciones

    private func addTag() {
        let clean = newTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        if !tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
            tags.append(clean)
        }
        newTag = ""
    }

    private func save() {
        guard let item else { return }
        store.rename(item, to: title)
        store.setTags(tags, for: item)
        dismiss()
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(Theme.textFaint)
    }
}

/// Disposición tipo "wrap" para los chips de etiquetas.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
