import Foundation
import WebKit

extension BrowserModel {

    /// Recorre la página (para disparar la carga diferida) y devuelve, en orden,
    /// las imágenes grandes que la componen: las páginas de un cómic o manga.
    func scanForImages() async {
        isScanning = true
        defer { isScanning = false }

        let js = """
        const sleep = (ms) => new Promise(r => setTimeout(r, ms));
        const pageHeight = () => Math.max(
            document.body ? document.body.scrollHeight : 0,
            document.documentElement ? document.documentElement.scrollHeight : 0
        );

        const startY = window.scrollY;
        const step = Math.max(window.innerHeight * 0.8, 400);
        let y = 0;
        let steps = 0;
        while (y < pageHeight() && steps < 120) {
            window.scrollTo(0, y);
            await sleep(90);
            y += step;
            steps++;
        }
        window.scrollTo(0, pageHeight());
        await sleep(500);
        window.scrollTo(0, startY);
        await sleep(150);

        const lazyAttrs = ['data-src', 'data-lazy-src', 'data-original', 'data-url',
                           'data-image', 'data-echo', 'data-full-src', 'data-lazy'];

        function pickSource(img) {
            const current = img.currentSrc || img.getAttribute('src') || '';
            const looksFake = !current
                || current.indexOf('data:') === 0
                || /blank|placeholder|spacer|loading|lazy|transparent/i.test(current);
            if (looksFake) {
                for (const a of lazyAttrs) {
                    const v = img.getAttribute(a);
                    if (v && v.indexOf('data:') !== 0) return v;
                }
            }
            const set = img.getAttribute('srcset') || img.getAttribute('data-srcset');
            if (set) {
                let bestWidth = -1;
                let bestURL = '';
                set.split(',').forEach(function (part) {
                    const bits = part.trim().split(' ').filter(Boolean);
                    if (!bits.length) return;
                    let w = 0;
                    if (bits[1] && bits[1].slice(-1) === 'w') w = parseInt(bits[1], 10) || 0;
                    if (w > bestWidth) { bestWidth = w; bestURL = bits[0]; }
                });
                if (bestURL && bestWidth > 0) return bestURL;
            }
            return current;
        }

        const out = [];
        const seen = {};

        function push(raw, w, h) {
            if (!raw) return;
            let abs;
            try { abs = new URL(raw, document.baseURI).href; } catch (e) { return; }
            if (!/^https?:/i.test(abs)) return;
            if (seen[abs]) return;
            if (w < 200 || h < 200) return;
            seen[abs] = 1;
            out.push({ url: abs, w: Math.round(w), h: Math.round(h) });
        }

        document.querySelectorAll('img').forEach(function (img) {
            const rect = img.getBoundingClientRect();
            const w = Math.max(img.naturalWidth || 0, img.width || 0, Math.round(rect.width));
            const h = Math.max(img.naturalHeight || 0, img.height || 0, Math.round(rect.height));
            push(pickSource(img), w, h);
        });

        if (out.length < 2) {
            const nodes = Array.prototype.slice.call(document.querySelectorAll('div, figure, section, a, span'), 0, 3000);
            nodes.forEach(function (node) {
                const rect = node.getBoundingClientRect();
                if (rect.width < 200 || rect.height < 200) return;
                const bg = window.getComputedStyle(node).backgroundImage || '';
                if (bg.indexOf('url(') !== 0) return;
                const raw = bg.slice(4, -1).replace(/["']/g, '');
                push(raw, rect.width, rect.height);
            });
        }

        return out.slice(0, 400);
        """

        do {
            let result = try await webView.callAsyncJavaScript(js, arguments: [:], in: nil, in: .page)
            let rows = (result as? [[String: Any]]) ?? []
            detectedImages = rows.compactMap { row in
                guard let string = row["url"] as? String, let url = URL(string: string) else { return nil }
                let w = (row["w"] as? NSNumber)?.intValue ?? 0
                let h = (row["h"] as? NSNumber)?.intValue ?? 0
                return CapturedImage(url: url, width: w, height: h)
            }
            if detectedImages.isEmpty {
                onError?("No se encontraron imágenes de lectura en esta página. Prueba a bajar hasta el final del capítulo y vuelve a pulsar.")
            }
        } catch {
            onError?("No se pudo analizar la página: \(error.localizedDescription)")
        }
    }

    /// Cookies de la sesión del navegador, para descargar imágenes protegidas.
    func currentCookies() async -> [HTTPCookie] {
        let store = webView.configuration.websiteDataStore.httpCookieStore
        return await withCheckedContinuation { continuation in
            store.getAllCookies { cookies in
                continuation.resume(returning: cookies)
            }
        }
    }

    /// Nombre razonable para el PDF que se genere con las imágenes.
    var suggestedCaptureTitle: String {
        let raw = pageTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty {
            let cut = raw
                .replacingOccurrences(of: " - Read Comics Online", with: "")
                .replacingOccurrences(of: " | ", with: " ")
                .prefix(70)
            return String(cut)
        }
        if let url = currentURL {
            let parts = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            if !parts.isEmpty { return parts.suffix(2).joined(separator: " ") }
            return url.host ?? "Captura"
        }
        return "Captura"
    }
}
