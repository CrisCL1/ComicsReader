import Foundation

/// Configuración de Google Drive.
///
/// PASOS (una sola vez, ver INSTALL.md):
///  1. console.cloud.google.com  ->  nuevo proyecto
///  2. Habilitar "Google Drive API"
///  3. Pantalla de consentimiento OAuth: tipo Externo, en modo "Pruebas",
///     y añádete a ti mismo como usuario de prueba.
///  4. Credenciales -> Crear credenciales -> ID de cliente de OAuth -> iOS
///     Bundle ID: com.cris.onyx
///  5. Copia el Client ID aquí abajo y su versión invertida en Info.plist
///     (CFBundleURLSchemes).
enum DriveConfig {

    /// Ej: "123456789012-abcdefghijklmnop.apps.googleusercontent.com"
    static let clientID = "REEMPLAZA-CON-TU-CLIENT-ID.apps.googleusercontent.com"

    /// Esquema de retorno = client ID invertido (sin el sufijo).
    static var redirectURI: String {
        let reversed = clientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(reversed):/oauth2redirect"
    }

    static var callbackScheme: String {
        let reversed = clientID
            .replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        return "com.googleusercontent.apps.\(reversed)"
    }

    /// drive.file = la app solo ve los archivos que ella misma crea.
    /// Es el permiso mínimo posible para lo que necesitamos.
    static let scope = "https://www.googleapis.com/auth/drive.file"

    /// Carpeta que la app crea en tu Drive.
    static let folderName = "Onyx"

    static var isConfigured: Bool {
        !clientID.hasPrefix("REEMPLAZA")
    }
}
