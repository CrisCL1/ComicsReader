import Foundation
import WebKit
import SwiftUI

/// Navegador integrado que intercepta cualquier PDF y lo descarga a la app
/// en lugar de mostrarlo en el visor del sistema.
@MainActor
final class BrowserModel: NSObject, ObservableObject {

    let webView: WKWebView

    @Published var addressText: String = ""
    @Published var currentURL: URL?
    @Published var pageTitle: String = ""
    @Published var isLoading = false
    @Published var loadProgress: Double = 0
    @Published var canGoBack = false
    @Published var canGoForward = false

    /// Enlaces .pdf detectados en la página actual.
    @Published var detectedPDFs: [URL] = []
    /// Imágenes de lectura detectadas en la página actual (visores tipo cómic/manga).
    @Published var detectedImages: [CapturedImage] = []
    @Published var isScanning = false

    /// Descarga en curso: 0...1, nil si no hay ninguna.
    @Published var downloadProgress: Double?
    @Published var downloadName: String?

    /// Se invoca con (archivo temporal, nombre sugerido, url de origen).
    var onDownloadFinished: (@MainActor (URL, String, URL?) -> Void)?
    var onError: (@MainActor (String) -> Void)?

    private var observations: [NSKeyValueObservation] = []
    private var progressObservation: NSKeyValueObservation?
    private var downloadDestinations: [ObjectIdentifier: URL] = [:]
    private var downloadOrigins: [ObjectIdentifier: URL] = [:]

    override init() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.allowsInlineMediaPlayback = true
        webView = WKWebView(frame: .zero, configuration: config)
        super.init()

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black

        observations = [
            webView.observe(\.estimatedProgress, options: .new) { [weak self] view, _ in
                let value = view.estimatedProgress
                Task { @MainActor in self?.loadProgress = value }
            },
            webView.observe(\.isLoading, options: .new) { [weak self] view, _ in
                let value = view.isLoading
                Task { @MainActor in self?.isLoading = value }
            },
            webView.observe(\.canGoBack, options: .new) { [weak self] view, _ in
                let value = view.canGoBack
                Task { @MainActor in self?.canGoBack = value }
            },
            webView.observe(\.canGoForward, options: .new) { [weak self] view, _ in
                let value = view.canGoForward
                Task { @MainActor in self?.canGoForward = value }
            },
            webView.observe(\.url, options: .new) { [weak self] view, _ in
                let value = view.url
                Task { @MainActor in
                    self?.currentURL = value
                    if let value { self?.addressText = value.absoluteString }
                }
            },
            webView.observe(\.title, options: .new) { [weak self] view, _ in
                let value = view.title ?? ""
                Task { @MainActor in self?.pageTitle = value }
            }
        ]
    }

    // MARK: - Navegación

    func go(to text: String) {
        guard let url = Self.normalizeURL(text) else { return }
        webView.load(URLRequest(url: url))
    }

    func reload()  { webView.reload() }
    func back()    { webView.goBack() }
    func forward() { webView.goForward() }

    nonisolated static func normalizeURL(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let looksLikeDomain = trimmed.contains(".") && !trimmed.contains(" ")
        if looksLikeDomain {
            if trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://") {
                return URL(string: trimmed)
            }
            return URL(string: "https://" + trimmed)
        }
        let query = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        return URL(string: "https://duckduckgo.com/?q=\(query)")
    }

    // MARK: - Detección de PDFs en la página

    func scanForPDFs() async {
        isScanning = true
        defer { isScanning = false }

        let js = """
        (function () {
          var out = [];
          function push(u) {
            if (!u) return;
            try { u = new URL(u, document.baseURI).href; } catch (e) { return; }
            if (out.indexOf(u) === -1) out.push(u);
          }
          document.querySelectorAll('a[href]').forEach(function (a) {
            var h = a.href.toLowerCase();
            if (h.indexOf('.pdf') !== -1 || h.indexOf('/download') !== -1) push(a.href);
          });
          document.querySelectorAll('embed[src], object[data], iframe[src]').forEach(function (e) {
            var s = e.getAttribute('src') || e.getAttribute('data') || '';
            if (s.toLowerCase().indexOf('.pdf') !== -1) push(s);
          });
          return out.slice(0, 40);
        })();
        """

        do {
            let result = try await webView.evaluateJavaScript(js)
            let strings = (result as? [String]) ?? []
            detectedPDFs = strings.compactMap { URL(string: $0) }
            if detectedPDFs.isEmpty {
                onError?("No se encontraron PDFs enlazados en esta página. Prueba a abrir el enlace de descarga directamente.")
            }
        } catch {
            onError?("No se pudo analizar la página.")
        }
    }

    /// Fuerza la descarga de una URL concreta usando las cookies de la sesión.
    func download(url: URL) {
        webView.load(URLRequest(url: url))
    }

    fileprivate func observeProgress(of download: WKDownload) {
        progressObservation = download.progress.observe(\.fractionCompleted, options: .new) { [weak self] progress, _ in
            let value = progress.fractionCompleted
            Task { @MainActor in self?.downloadProgress = value }
        }
    }

    fileprivate func registerDownload(_ download: WKDownload, destination: URL, origin: URL?) {
        downloadDestinations[ObjectIdentifier(download)] = destination
        downloadOrigins[ObjectIdentifier(download)] = origin
        downloadName = destination.lastPathComponent
        downloadProgress = 0
        observeProgress(of: download)
    }

    fileprivate func finishDownload(_ download: WKDownload) {
        let key = ObjectIdentifier(download)
        let destination = downloadDestinations.removeValue(forKey: key)
        let origin = downloadOrigins.removeValue(forKey: key)
        downloadProgress = nil
        downloadName = nil
        progressObservation = nil
        guard let destination else { return }
        let name = (destination.lastPathComponent as NSString).deletingPathExtension
        onDownloadFinished?(destination, name, origin)
    }

    fileprivate func failDownload(_ download: WKDownload, message: String) {
        downloadDestinations.removeValue(forKey: ObjectIdentifier(download))
        downloadOrigins.removeValue(forKey: ObjectIdentifier(download))
        downloadProgress = nil
        downloadName = nil
        progressObservation = nil
        onError?(message)
    }
}

// MARK: - WKNavigationDelegate

extension BrowserModel: WKNavigationDelegate {

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let mime = navigationResponse.response.mimeType?.lowercased() ?? ""
        let name = navigationResponse.response.suggestedFilename?.lowercased() ?? ""
        let isPDF = mime.contains("pdf") || name.hasSuffix(".pdf")
        decisionHandler(isPDF ? .download : .allow)
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView,
                 navigationAction: WKNavigationAction,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        detectedPDFs = []
        detectedImages = []
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        report(error)
    }

    private func report(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled,
              nsError.code != 102 else { return }   // 102 = frame load interrumpido por una descarga
        onError?(error.localizedDescription)
    }
}

// MARK: - WKUIDelegate (enlaces con target=_blank)

extension BrowserModel: WKUIDelegate {
    func webView(_ webView: WKWebView,
                 createWebViewWith configuration: WKWebViewConfiguration,
                 for navigationAction: WKNavigationAction,
                 windowFeatures: WKWindowFeatures) -> WKWebView? {
        if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }
}

// MARK: - WKDownloadDelegate

extension BrowserModel: WKDownloadDelegate {

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let fileName = suggestedFilename.isEmpty ? "documento.pdf" : suggestedFilename
        let destination = folder.appendingPathComponent(fileName)

        registerDownload(download, destination: destination, origin: response.url)
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        finishDownload(download)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        failDownload(download, message: "La descarga falló: \(error.localizedDescription)")
    }
}
