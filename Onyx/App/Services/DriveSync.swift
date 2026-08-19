import Foundation
import SwiftUI

/// Orquesta la copia de PDFs a Google Drive y la liberación de espacio local.
@MainActor
final class DriveSync: ObservableObject {

    @Published var busyItemIDs: Set<UUID> = []
    @Published var statusMessage: String?
    @Published var errorMessage: String?

    /// Claves compartidas con los interruptores de Ajustes.
    enum Prefs {
        static let autoUpload = "drive.autoUpload"
        static let offloadAfterUpload = "drive.offloadAfterUpload"
    }

    /// Si está activo, cada PDF nuevo se sube a Drive automáticamente.
    var autoUpload: Bool { UserDefaults.standard.bool(forKey: Prefs.autoUpload) }
    /// Si está activo, tras subir se borra la copia local para no llenar el iPhone.
    var offloadAfterUpload: Bool { UserDefaults.standard.bool(forKey: Prefs.offloadAfterUpload) }

    private let client = GoogleDriveClient()

    func isBusy(_ item: LibraryItem) -> Bool { busyItemIDs.contains(item.id) }

    // MARK: - Subir

    func upload(_ item: LibraryItem, store: LibraryStore) async {
        guard GoogleDriveAuth.shared.isSignedIn else {
            errorMessage = DriveError.notSignedIn.localizedDescription
            return
        }
        guard item.driveFileID == nil else { return }
        guard FileStore.exists(item) else {
            errorMessage = "El archivo local ya no existe."
            return
        }

        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }

        do {
            statusMessage = "Subiendo \(item.title)…"
            let folder = try await client.ensureFolder()
            let id = try await client.upload(
                fileURL: FileStore.fileURL(for: item),
                name: item.fileName,
                folderID: folder
            )
            var updated = item
            updated.driveFileID = id
            store.update(updated, immediate: true)
            statusMessage = "\(item.title) está en Drive."

            if offloadAfterUpload {
                await offload(updated, store: store)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Sube todos los que aún no estén en Drive.
    func uploadAll(store: LibraryStore) async {
        for item in store.items where item.driveFileID == nil && item.isLocalAvailable {
            await upload(item, store: store)
        }
        statusMessage = "Sincronización completada."
    }

    // MARK: - Liberar espacio

    /// Borra la copia local (conserva ficha, progreso y miniatura).
    func offload(_ item: LibraryItem, store: LibraryStore) async {
        guard item.driveFileID != nil else {
            errorMessage = "Súbelo a Drive antes de liberar espacio."
            return
        }
        FileStore.deleteFiles(for: item, includeThumbnail: false)
        var updated = item
        updated.isLocalAvailable = false
        store.update(updated, immediate: true)
        statusMessage = "Espacio liberado: \(item.readableSize)"
    }

    func offloadAllSynced(store: LibraryStore) async {
        for item in store.items where item.driveFileID != nil && item.isLocalAvailable {
            await offload(item, store: store)
        }
    }

    // MARK: - Recuperar

    /// Vuelve a traer el PDF desde Drive. Devuelve true si quedó disponible.
    @discardableResult
    func fetch(_ item: LibraryItem, store: LibraryStore) async -> Bool {
        if FileStore.exists(item) {
            if !item.isLocalAvailable {
                var updated = item
                updated.isLocalAvailable = true
                store.update(updated, immediate: true)
            }
            return true
        }
        guard let fileID = item.driveFileID else {
            errorMessage = "Este documento no está en Drive y falta localmente."
            return false
        }

        busyItemIDs.insert(item.id)
        defer { busyItemIDs.remove(item.id) }

        do {
            statusMessage = "Descargando \(item.title)…"
            try await client.download(fileID: fileID, to: FileStore.fileURL(for: item))
            var updated = item
            updated.isLocalAvailable = true
            updated.fileSize = FileStore.size(of: FileStore.fileURL(for: item))
            store.update(updated, immediate: true)
            statusMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    // MARK: - Alta automática

    func handleNewImport(_ item: LibraryItem, store: LibraryStore) async {
        guard autoUpload, GoogleDriveAuth.shared.isSignedIn else { return }
        await upload(item, store: store)
    }

    // MARK: - Borrado

    func deleteEverywhere(_ item: LibraryItem, store: LibraryStore) async {
        if let fileID = item.driveFileID {
            try? await client.delete(fileID: fileID)
        }
        store.delete(item)
    }
}
