import Foundation

/// Cliente mínimo de la Drive API v3 (REST, sin dependencias).
@MainActor
struct GoogleDriveClient {

    private let auth = GoogleDriveAuth.shared

    // MARK: - Carpeta de la app

    /// Devuelve (creando si hace falta) el ID de la carpeta "Onyx" en Drive.
    func ensureFolder() async throws -> String {
        if let cached = UserDefaults.standard.string(forKey: "google.folderID"),
           try await folderExists(id: cached) {
            return cached
        }

        let token = try await auth.validAccessToken()
        let query = "mimeType='application/vnd.google-apps.folder' and name='\(DriveConfig.folderName)' and trashed=false"
        var components = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        components.queryItems = [
            .init(name: "q", value: query),
            .init(name: "fields", value: "files(id,name)"),
            .init(name: "spaces", value: "drive")
        ]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, _) = try await URLSession.shared.data(for: request)
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let files = json["files"] as? [[String: Any]],
           let id = files.first?["id"] as? String {
            UserDefaults.standard.set(id, forKey: "google.folderID")
            return id
        }

        let id = try await createFolder(token: token)
        UserDefaults.standard.set(id, forKey: "google.folderID")
        return id
    }

    private func folderExists(id: String) async throws -> Bool {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(id)?fields=id,trashed")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, http.statusCode == 200,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return false }
        return (json["trashed"] as? Bool) != true
    }

    private func createFolder(token: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files?fields=id")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": DriveConfig.folderName,
            "mimeType": "application/vnd.google-apps.folder"
        ])
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw DriveError.uploadFailed("no se pudo crear la carpeta")
        }
        return id
    }

    // MARK: - Subida (resumable, apta para archivos grandes)

    func upload(fileURL: URL, name: String, folderID: String) async throws -> String {
        let token = try await auth.validAccessToken()

        var initRequest = URLRequest(
            url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=resumable&fields=id")!
        )
        initRequest.httpMethod = "POST"
        initRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        initRequest.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        initRequest.setValue("application/pdf", forHTTPHeaderField: "X-Upload-Content-Type")
        initRequest.httpBody = try JSONSerialization.data(withJSONObject: [
            "name": name,
            "parents": [folderID],
            "mimeType": "application/pdf"
        ])

        let (_, initResponse) = try await URLSession.shared.data(for: initRequest)
        guard let http = initResponse as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              let location = http.value(forHTTPHeaderField: "Location"),
              let uploadURL = URL(string: location) else {
            throw DriveError.uploadFailed("la sesión de subida no se inició")
        }

        var putRequest = URLRequest(url: uploadURL)
        putRequest.httpMethod = "PUT"
        putRequest.setValue("application/pdf", forHTTPHeaderField: "Content-Type")

        let (data, putResponse) = try await URLSession.shared.upload(for: putRequest, fromFile: fileURL)
        guard let httpPut = putResponse as? HTTPURLResponse, (200..<300).contains(httpPut.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw DriveError.uploadFailed("respuesta inesperada del servidor")
        }
        return id
    }

    // MARK: - Descarga

    func download(fileID: String, to destination: URL) async throws {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)?alt=media")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw DriveError.downloadFailed("el archivo ya no está en Drive")
        }
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: tempURL, to: destination)
    }

    // MARK: - Borrado

    func delete(fileID: String) async throws {
        let token = try await auth.validAccessToken()
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(fileID)")!)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        _ = try? await URLSession.shared.data(for: request)
    }
}
