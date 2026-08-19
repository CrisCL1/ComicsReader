import Foundation
import UIKit

/// Una imagen detectada en la página web actual.
struct CapturedImage: Identifiable, Hashable {
    let url: URL
    var width: Int
    var height: Int

    var id: URL { url }

    var displayName: String {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty ? (url.host ?? "imagen") : name
    }

    var sizeLabel: String {
        width > 0 && height > 0 ? "\(width)×\(height)" : "tamaño desconocido"
    }
}

enum CaptureError: LocalizedError {
    case noImages
    case allFailed
    case pdfFailed

    var errorDescription: String? {
        switch self {
        case .noImages:  return "No hay imágenes seleccionadas."
        case .allFailed: return "No se pudo descargar ninguna imagen. Puede que el sitio bloquee las descargas fuera del navegador."
        case .pdfFailed: return "No se pudo crear el PDF con las imágenes."
        }
    }
}

/// Descarga una lista de imágenes de la web y las une en un PDF de una página
/// por imagen, para poder leerlas igual que cualquier otro documento.
@MainActor
final class ImageCaptureService: ObservableObject {

    @Published private(set) var isRunning = false
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var statusText: String?
    /// Aviso de la última captura cuando alguna página se quedó fuera.
    @Published var lastWarning: String?

    /// Lado máximo en píxeles de cada página; evita PDFs gigantes.
    private static let maxPixelSide: CGFloat = 2400

    var progress: Double {
        total > 0 ? min(1, Double(completed) / Double(total)) : 0
    }

    /// Devuelve la URL de un PDF temporal listo para entrar en la biblioteca.
    func buildPDF(from images: [CapturedImage],
                  referer: URL?,
                  cookies: [HTTPCookie],
                  title: String) async throws -> URL {

        guard !images.isEmpty else { throw CaptureError.noImages }

        isRunning = true
        completed = 0
        total = images.count
        lastWarning = nil
        statusText = "Descargando imágenes…"
        defer {
            isRunning = false
            statusText = nil
        }

        let session = URLSession(configuration: .ephemeral)
        var payloads: [Data] = []
        payloads.reserveCapacity(images.count)

        for image in images {
            let header = Self.cookieHeader(for: image.url, cookies: cookies)
            if let data = await Self.fetch(image.url, referer: referer, cookieHeader: header, session: session) {
                payloads.append(data)
            }
            completed += 1
        }

        guard !payloads.isEmpty else { throw CaptureError.allFailed }

        statusText = "Creando el PDF…"

        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(FileStore.sanitize(title))

        let maxSide = Self.maxPixelSide
        let written = await Task.detached(priority: .userInitiated) {
            Self.renderPDF(from: payloads, to: destination, maxSide: maxSide)
        }.value

        guard written > 0 else {
            try? FileManager.default.removeItem(at: folder)
            throw CaptureError.pdfFailed
        }

        // Las páginas que fallan se saltan en silencio: avisamos para poder
        // repetir la captura en lugar de leer un capítulo incompleto.
        if written < images.count {
            let missing = images.count - written
            lastWarning = "Se guardaron \(written) de \(images.count) páginas: \(missing) no se pudieron descargar. Recarga el capítulo entero y repite la captura."
        }
        return destination
    }

    // MARK: - Red

    private nonisolated static func fetch(_ url: URL,
                                          referer: URL?,
                                          cookieHeader: String?,
                                          session: URLSession) async -> Data? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 30
        if let referer {
            request.setValue(referer.absoluteString, forHTTPHeaderField: "Referer")
            if let origin = referer.host.flatMap({ "\(referer.scheme ?? "https")://\($0)" }) {
                request.setValue(origin, forHTTPHeaderField: "Origin")
            }
        }
        if let cookieHeader {
            request.setValue(cookieHeader, forHTTPHeaderField: "Cookie")
        }
        request.setValue(
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue("image/avif,image/webp,image/apng,image/*,*/*;q=0.8", forHTTPHeaderField: "Accept")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode),
              data.count > 1024 else { return nil }
        return data
    }

    /// Cookies del WKWebView que aplican a este host, en formato de cabecera.
    private nonisolated static func cookieHeader(for url: URL, cookies: [HTTPCookie]) -> String? {
        guard !cookies.isEmpty, let host = url.host?.lowercased() else { return nil }
        let matching = cookies.filter { cookie in
            var domain = cookie.domain.lowercased()
            if domain.hasPrefix(".") { domain.removeFirst() }
            return host == domain || host.hasSuffix("." + domain)
        }
        guard !matching.isEmpty else { return nil }
        return HTTPCookie.requestHeaderFields(with: matching)["Cookie"]
    }

    // MARK: - PDF

    /// Devuelve cuántas páginas se escribieron realmente en el PDF.
    private nonisolated static func renderPDF(from payloads: [Data], to url: URL, maxSide: CGFloat) -> Int {
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = [kCGPDFContextCreator as String: "Onyx"]
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: format)

        var pages = 0
        do {
            try renderer.writePDF(to: url) { context in
                for data in payloads {
                    guard let image = UIImage(data: data), let cgImage = image.cgImage else { continue }

                    var size = CGSize(width: cgImage.width, height: cgImage.height)
                    guard size.width > 0, size.height > 0 else { continue }

                    let longest = max(size.width, size.height)
                    if longest > maxSide {
                        let scale = maxSide / longest
                        size = CGSize(width: (size.width * scale).rounded(),
                                      height: (size.height * scale).rounded())
                    }

                    let bounds = CGRect(origin: .zero, size: size)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    UIImage(cgImage: cgImage, scale: 1, orientation: image.imageOrientation).draw(in: bounds)
                    pages += 1
                }
            }
        } catch {
            return 0
        }
        return pages
    }
}
