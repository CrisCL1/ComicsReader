import Foundation
import AuthenticationServices
import CryptoKit
import UIKit

/// OAuth 2.0 con PKCE para clientes iOS (sin client secret, sin SDK externo).
@MainActor
final class GoogleDriveAuth: NSObject, ObservableObject {

    static let shared = GoogleDriveAuth()

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var accountEmail: String?

    private var session: ASWebAuthenticationSession?
    private var codeVerifier: String?
    private let anchorProvider = WebAuthAnchorProvider()

    private enum Key {
        static let refresh = "google.refreshToken"
        static let access  = "google.accessToken"
        static let expiry  = "google.accessExpiry"
        static let email   = "google.email"
    }

    private override init() {
        super.init()
        isSignedIn = Keychain.get(Key.refresh) != nil
        accountEmail = UserDefaults.standard.string(forKey: Key.email)
    }

    // MARK: - Login

    func signIn() async throws {
        guard DriveConfig.isConfigured else { throw DriveError.notConfigured }

        let verifier = Self.randomURLSafeString(length: 64)
        codeVerifier = verifier
        let challenge = Self.codeChallenge(for: verifier)

        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            .init(name: "client_id", value: DriveConfig.clientID),
            .init(name: "redirect_uri", value: DriveConfig.redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: DriveConfig.scope + " email"),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]

        let callbackURL: URL = try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: components.url!,
                callbackURLScheme: DriveConfig.callbackScheme
            ) { url, error in
                if let url {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(throwing: error ?? DriveError.cancelled)
                }
            }
            session.presentationContextProvider = self.anchorProvider
            session.prefersEphemeralWebBrowserSession = false
            self.session = session
            session.start()
        }

        guard let code = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "code" })?.value else {
            throw DriveError.noAuthCode
        }

        try await exchange(code: code, verifier: verifier)
    }

    func signOut() {
        Keychain.remove(Key.refresh)
        Keychain.remove(Key.access)
        Keychain.remove(Key.expiry)
        UserDefaults.standard.removeObject(forKey: Key.email)
        isSignedIn = false
        accountEmail = nil
    }

    // MARK: - Tokens

    private func exchange(code: String, verifier: String) async throws {
        let body = [
            "client_id": DriveConfig.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": DriveConfig.redirectURI
        ]
        let json = try await postForm(body)

        guard let access = json["access_token"] as? String else { throw DriveError.tokenExchangeFailed }
        Keychain.set(access, for: Key.access)
        if let refresh = json["refresh_token"] as? String {
            Keychain.set(refresh, for: Key.refresh)
        }
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        Keychain.set(String(Date().addingTimeInterval(expiresIn - 60).timeIntervalSince1970), for: Key.expiry)

        if let idToken = json["id_token"] as? String, let email = Self.email(fromIDToken: idToken) {
            UserDefaults.standard.set(email, forKey: Key.email)
            accountEmail = email
        }
        isSignedIn = true
    }

    /// Devuelve un access token válido, refrescándolo si hace falta.
    func validAccessToken() async throws -> String {
        if let token = Keychain.get(Key.access),
           let expiryString = Keychain.get(Key.expiry),
           let expiry = Double(expiryString),
           Date().timeIntervalSince1970 < expiry {
            return token
        }
        guard let refresh = Keychain.get(Key.refresh) else {
            isSignedIn = false
            throw DriveError.notSignedIn
        }
        let json = try await postForm([
            "client_id": DriveConfig.clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ])
        guard let access = json["access_token"] as? String else {
            signOut()
            throw DriveError.tokenExchangeFailed
        }
        Keychain.set(access, for: Key.access)
        let expiresIn = (json["expires_in"] as? Double) ?? 3600
        Keychain.set(String(Date().addingTimeInterval(expiresIn - 60).timeIntervalSince1970), for: Key.expiry)
        return access
    }

    private func postForm(_ fields: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = fields
            .map { "\($0.key)=\(Self.formEncode($0.value))" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DriveError.tokenExchangeFailed
        }
        return json
    }

    // MARK: - Utilidades

    private static func formEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

    private static func randomURLSafeString(length: Int) -> String {
        let chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
        return String((0..<length).map { _ in chars.randomElement()! })
    }

    private static func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    private static func email(fromIDToken token: String) -> String? {
        let parts = token.split(separator: ".")
        guard parts.count > 1 else { return nil }
        var payload = String(parts[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while payload.count % 4 != 0 { payload += "=" }
        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return json["email"] as? String
    }
}

/// Devuelve la ventana sobre la que presentar la pantalla de login de Google.
/// Va en su propia clase para no mezclar aislamiento de actores.
final class WebAuthAnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow } ?? ASPresentationAnchor()
    }
}

enum DriveError: LocalizedError {
    case notConfigured
    case notSignedIn
    case cancelled
    case noAuthCode
    case tokenExchangeFailed
    case uploadFailed(String)
    case downloadFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:       return "Falta configurar el Client ID de Google en DriveConfig.swift."
        case .notSignedIn:         return "No has iniciado sesión en Google Drive."
        case .cancelled:           return "Inicio de sesión cancelado."
        case .noAuthCode:          return "Google no devolvió un código de autorización."
        case .tokenExchangeFailed: return "No se pudo obtener el token de acceso."
        case .uploadFailed(let m): return "Error al subir: \(m)"
        case .downloadFailed(let m): return "Error al descargar: \(m)"
        }
    }
}
