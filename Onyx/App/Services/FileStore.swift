import Foundation
import PDFKit
import UIKit

/// Gestión del sistema de archivos: dónde viven los PDFs y sus miniaturas.
enum FileStore {

    static var documents: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    static var libraryDir: URL {
        let url = documents.appendingPathComponent("Library", isDirectory: true)
        ensureDir(url)
        return url
    }

    static var thumbsDir: URL {
        let url = documents.appendingPathComponent("Thumbnails", isDirectory: true)
        ensureDir(url)
        return url
    }

    static var inboxDir: URL {
        documents.appendingPathComponent("Inbox", isDirectory: true)
    }

    static var libraryJSON: URL {
        documents.appendingPathComponent("library.json")
    }

    private static func ensureDir(_ url: URL) {
        if !FileManager.default.fileExists(atPath: url.path) {
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    // MARK: - Rutas

    static func fileURL(for item: LibraryItem) -> URL {
        libraryDir.appendingPathComponent(item.fileName)
    }

    static func thumbURL(for item: LibraryItem) -> URL {
        thumbsDir.appendingPathComponent("\(item.id.uuidString).jpg")
    }

    static func exists(_ item: LibraryItem) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: item).path)
    }

    // MARK: - Nombres únicos

    /// Devuelve un nombre de archivo libre dentro de Library/ a partir de uno propuesto.
    static func uniqueFileName(preferred: String) -> String {
        let sanitized = sanitize(preferred)
        var candidate = sanitized
        var n = 2
        while FileManager.default.fileExists(atPath: libraryDir.appendingPathComponent(candidate).path) {
            let base = (sanitized as NSString).deletingPathExtension
            let ext  = (sanitized as NSString).pathExtension
            candidate = ext.isEmpty ? "\(base) \(n)" : "\(base) \(n).\(ext)"
            n += 1
        }
        return candidate
    }

    static func sanitize(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:*?\"<>|\n\r\t")
        var cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { cleaned = "Documento" }
        if cleaned.count > 120 { cleaned = String(cleaned.prefix(120)) }
        if !cleaned.lowercased().hasSuffix(".pdf") { cleaned += ".pdf" }
        return cleaned
    }

    // MARK: - Tamaño

    static func size(of url: URL) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
    }

    /// Espacio ocupado por los PDFs guardados localmente.
    static func localStorageUsed() -> Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: libraryDir, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        return files.reduce(0) { $0 + size(of: $1) }
    }

    // MARK: - Miniaturas

    /// Genera y guarda la miniatura de la primera página. Devuelve el número de páginas.
    @discardableResult
    static func makeThumbnail(pdfURL: URL, itemID: UUID, maxWidth: CGFloat = 300) -> Int {
        guard let doc = PDFDocument(url: pdfURL), let page = doc.page(at: 0) else { return 0 }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0 else { return doc.pageCount }
        let scale = maxWidth / bounds.width
        let size  = CGSize(width: maxWidth, height: bounds.height * scale)
        let image = page.thumbnail(of: size, for: .mediaBox)
        if let data = image.jpegData(compressionQuality: 0.8) {
            try? data.write(to: thumbsDir.appendingPathComponent("\(itemID.uuidString).jpg"), options: .atomic)
        }
        return doc.pageCount
    }

    static func loadThumbnail(for item: LibraryItem) -> UIImage? {
        UIImage(contentsOfFile: thumbURL(for: item).path)
    }

    // MARK: - Borrado

    static func deleteFiles(for item: LibraryItem, includeThumbnail: Bool = true) {
        try? FileManager.default.removeItem(at: fileURL(for: item))
        if includeThumbnail {
            try? FileManager.default.removeItem(at: thumbURL(for: item))
        }
    }
}
