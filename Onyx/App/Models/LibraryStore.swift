import Foundation
import SwiftUI
import PDFKit

/// Fuente de verdad de la biblioteca. Persiste en Documents/library.json
@MainActor
final class LibraryStore: ObservableObject {

    @Published private(set) var items: [LibraryItem] = []
    @Published var lastError: String?

    private var saveTask: Task<Void, Never>?

    init() {
        load()
        importInboxIfNeeded()
    }

    // MARK: - Persistencia

    private func load() {
        guard let data = try? Data(contentsOf: FileStore.libraryJSON) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([LibraryItem].self, from: data) {
            items = decoded
        }
    }

    /// Guardado con un pequeño retardo para no escribir en cada cambio de página.
    func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            self?.saveNow()
        }
    }

    func saveNow() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(items) else { return }
        try? data.write(to: FileStore.libraryJSON, options: .atomic)
    }

    // MARK: - Consultas

    var favorites: [LibraryItem] {
        items.filter(\.isFavorite)
             .sorted { ($0.lastOpenedAt ?? $0.addedAt) > ($1.lastOpenedAt ?? $1.addedAt) }
    }

    var allTags: [String] {
        Array(Set(items.flatMap(\.tags)))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func item(id: UUID) -> LibraryItem? { items.first { $0.id == id } }

    func count(forTag tag: String) -> Int {
        items.filter { $0.tags.contains(tag) }.count
    }

    func filtered(search: String, tag: String?, filter: ReadFilter, sort: LibrarySort) -> [LibraryItem] {
        var result = items

        if let tag { result = result.filter { $0.tags.contains(tag) } }

        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        if !query.isEmpty {
            result = result.filter { item in
                item.title.lowercased().contains(query) ||
                item.tags.contains { $0.lowercased().contains(query) }
            }
        }

        switch filter {
        case .all:      break
        case .reading:  result = result.filter { $0.isStarted && !$0.isFinished }
        case .unread:   result = result.filter { !$0.isStarted }
        case .finished: result = result.filter(\.isFinished)
        }

        switch sort {
        case .recent:
            result.sort { ($0.lastOpenedAt ?? .distantPast) > ($1.lastOpenedAt ?? .distantPast) }
        case .added:
            result.sort { $0.addedAt > $1.addedAt }
        case .title:
            result.sort { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
        case .progress:
            result.sort { $0.progress > $1.progress }
        }
        return result
    }

    // MARK: - Alta de documentos

    /// Copia (o mueve) un PDF a la biblioteca y crea su ficha.
    @discardableResult
    func addPDF(from url: URL, suggestedTitle: String? = nil, sourceURL: URL? = nil, move: Bool = false) -> LibraryItem? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }

        guard PDFDocument(url: url) != nil else {
            lastError = "El archivo no es un PDF válido."
            return nil
        }

        let baseName: String = {
            if let t = suggestedTitle, !t.trimmingCharacters(in: .whitespaces).isEmpty { return t }
            return url.deletingPathExtension().lastPathComponent
        }()

        let fileName = FileStore.uniqueFileName(preferred: baseName)
        let dest = FileStore.libraryDir.appendingPathComponent(fileName)

        do {
            if move, url.isFileURL, FileManager.default.isDeletableFile(atPath: url.path) {
                try FileManager.default.moveItem(at: url, to: dest)
            } else {
                try FileManager.default.copyItem(at: url, to: dest)
            }
        } catch {
            lastError = "No se pudo guardar: \(error.localizedDescription)"
            return nil
        }

        var item = LibraryItem(
            title: (fileName as NSString).deletingPathExtension,
            fileName: fileName,
            sourceURL: sourceURL
        )
        item.fileSize = FileStore.size(of: dest)
        item.pageCount = FileStore.makeThumbnail(pdfURL: dest, itemID: item.id)

        items.insert(item, at: 0)
        saveNow()
        return item
    }

    /// Guarda datos descargados (por ejemplo, desde el navegador integrado).
    @discardableResult
    func addPDF(data: Data, suggestedTitle: String, sourceURL: URL?) -> LibraryItem? {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        do {
            try data.write(to: tmp)
        } catch {
            lastError = "No se pudo escribir el archivo temporal."
            return nil
        }
        defer { try? FileManager.default.removeItem(at: tmp) }
        return addPDF(from: tmp, suggestedTitle: suggestedTitle, sourceURL: sourceURL)
    }

    /// PDFs que llegan por la hoja de compartir de Safari (Copiar en Onyx).
    func importInboxIfNeeded() {
        let fm = FileManager.default
        guard let files = try? fm.contentsOfDirectory(at: FileStore.inboxDir, includingPropertiesForKeys: nil) else { return }
        for file in files where file.pathExtension.lowercased() == "pdf" {
            addPDF(from: file, move: true)
        }
        try? fm.removeItem(at: FileStore.inboxDir)
    }

    // MARK: - Mutaciones

    func update(_ item: LibraryItem, immediate: Bool = false) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx] = item
        if immediate { saveNow() } else { scheduleSave() }
    }

    func toggleFavorite(_ item: LibraryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].isFavorite.toggle()
        saveNow()
    }

    func rename(_ item: LibraryItem, to newTitle: String) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        let trimmed = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        items[idx].title = trimmed
        saveNow()
    }

    func setTags(_ tags: [String], for item: LibraryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        var unique: [String] = []
        for tag in tags {
            let clean = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !clean.isEmpty else { continue }
            if !unique.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) {
                unique.append(clean)
            }
        }
        items[idx].tags = unique
        saveNow()
    }

    func renameTag(_ old: String, to new: String) {
        let clean = new.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return }
        for i in items.indices {
            guard let pos = items[i].tags.firstIndex(where: { $0.caseInsensitiveCompare(old) == .orderedSame }) else { continue }
            items[i].tags[pos] = clean
            var seen: [String] = []
            for tag in items[i].tags where !seen.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
                seen.append(tag)
            }
            items[i].tags = seen
        }
        saveNow()
    }

    func deleteTag(_ tag: String) {
        for i in items.indices {
            items[i].tags.removeAll { $0.caseInsensitiveCompare(tag) == .orderedSame }
        }
        saveNow()
    }

    /// Registra la posición de lectura.
    func recordProgress(itemID: UUID, page: Int) {
        guard let idx = items.firstIndex(where: { $0.id == itemID }) else { return }
        items[idx].lastPage = page
        items[idx].maxPageReached = max(items[idx].maxPageReached, page)
        items[idx].lastOpenedAt = Date()
        scheduleSave()
    }

    func markFinished(_ item: LibraryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }), items[idx].pageCount > 0 else { return }
        items[idx].maxPageReached = items[idx].pageCount - 1
        items[idx].lastPage = items[idx].pageCount - 1
        saveNow()
    }

    func resetProgress(_ item: LibraryItem) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[idx].maxPageReached = 0
        items[idx].lastPage = 0
        saveNow()
    }

    func delete(_ item: LibraryItem) {
        FileStore.deleteFiles(for: item)
        items.removeAll { $0.id == item.id }
        saveNow()
    }

    func delete(ids: Set<UUID>) {
        for id in ids {
            if let item = item(id: id) { FileStore.deleteFiles(for: item) }
        }
        items.removeAll { ids.contains($0.id) }
        saveNow()
    }
}
