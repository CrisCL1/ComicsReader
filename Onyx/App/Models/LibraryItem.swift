import Foundation

/// Un documento de la biblioteca. Se serializa a JSON en Documents/library.json
struct LibraryItem: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var title: String
    /// Nombre de archivo dentro de Documents/Library (no ruta absoluta: el
    /// contenedor de la app cambia de UUID entre instalaciones).
    var fileName: String
    var addedAt: Date = Date()
    var lastOpenedAt: Date?
    var sourceURL: URL?

    var pageCount: Int = 0
    /// Última página vista (índice 0-based).
    var lastPage: Int = 0
    /// Página más avanzada alcanzada, usada para el % leído.
    var maxPageReached: Int = 0

    var isFavorite: Bool = false
    var tags: [String] = []

    var fileSize: Int64 = 0

    // MARK: Google Drive
    var driveFileID: String?
    /// false cuando el PDF se subió a Drive y se borró la copia local.
    var isLocalAvailable: Bool = true

    // MARK: Derivados
    var progress: Double {
        guard pageCount > 0 else { return 0 }
        return min(1, Double(maxPageReached + 1) / Double(pageCount))
    }

    var progressPercent: Int { Int((progress * 100).rounded()) }

    var isFinished: Bool { pageCount > 0 && maxPageReached >= pageCount - 1 }

    var isStarted: Bool { maxPageReached > 0 || lastOpenedAt != nil }

    var readableSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent      = "Recientes"
    case added       = "Añadidos"
    case title       = "Título"
    case progress    = "Progreso"
    var id: String { rawValue }
}

enum ReadFilter: String, CaseIterable, Identifiable {
    case all         = "Todos"
    case reading     = "En curso"
    case unread      = "Sin empezar"
    case finished    = "Terminados"
    var id: String { rawValue }
}
