import SwiftUI
import WebKit

struct BrowserView: View {

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var drive: DriveSync
    @StateObject private var model = BrowserModel()
    @StateObject private var capture = ImageCaptureService()

    @AppStorage("browser.lastURL") private var lastURL: String = ""
    @State private var showDetected = false
    @State private var showImages = false
    @State private var selectedImages: Set<URL> = []
    @State private var savedTitle: String?
    @State private var errorText: String?
    @FocusState private var addressFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Theme.bg.ignoresSafeArea()

                VStack(spacing: 0) {
                    addressBar

                    if model.isLoading {
                        ProgressBar(value: model.loadProgress, height: 2, tint: Theme.accent)
                    }

                    ZStack {
                        WebViewContainer(model: model)

                        if model.currentURL == nil {
                            startScreen
                        }
                    }
                }

                if let progress = model.downloadProgress {
                    banner(title: model.downloadName ?? "Descargando...",
                           detail: "\(Int(progress * 100))%",
                           progress: progress)
                        .padding(.top, 62)
                } else if capture.isRunning {
                    banner(title: capture.statusText ?? "Capturando...",
                           detail: capture.total > 0 ? "\(capture.completed)/\(capture.total)" : "",
                           progress: capture.progress)
                        .padding(.top, 62)
                }

                if let savedTitle {
                    Toast(text: "Guardado: \(savedTitle)")
                        .padding(.top, 62)
                }
            }
            .navigationBarHidden(true)
            .safeAreaInset(edge: .bottom) { toolbar }
            .onAppear(perform: configure)
            .onChange(of: model.currentURL) { url in
                if let url, url.absoluteString != "about:blank" {
                    lastURL = url.absoluteString
                }
            }
            .sheet(isPresented: $showDetected) {
                detectedSheet
            }
            .sheet(isPresented: $showImages) {
                imagesSheet
            }
            .alert("Aviso", isPresented: Binding(
                get: { errorText != nil },
                set: { if !$0 { errorText = nil } }
            )) {
                Button("Entendido", role: .cancel) { errorText = nil }
            } message: {
                Text(errorText ?? "")
            }
        }
    }

    // MARK: - Barra de dirección

    private var addressBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textFaint)

            TextField("Buscar o escribir dirección", text: $model.addressText)
                .textFieldStyle(.plain)
                .font(.footnote)
                .foregroundStyle(Theme.text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.webSearch)
                .submitLabel(.go)
                .focused($addressFocused)
                .onSubmit {
                    model.go(to: model.addressText)
                    addressFocused = false
                }

            if model.isLoading {
                Button { model.webView.stopLoading() } label: {
                    Image(systemName: "xmark").font(.system(size: 12))
                }
                .tint(Theme.textMuted)
            } else if model.currentURL != nil {
                Button { model.reload() } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 12))
                }
                .tint(Theme.textMuted)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.surface)
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Theme.bg)
    }

    // MARK: - Barra inferior

    private var toolbar: some View {
        HStack(spacing: 0) {
            toolbarButton("chevron.left", enabled: model.canGoBack) { model.back() }
            toolbarButton("chevron.right", enabled: model.canGoForward) { model.forward() }

            Spacer()

            Menu {
                Button {
                    Task {
                        await model.scanForPDFs()
                        if !model.detectedPDFs.isEmpty { showDetected = true }
                    }
                } label: {
                    Label("Buscar un PDF enlazado", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    Task {
                        await model.scanForImages()
                        if !model.detectedImages.isEmpty {
                            selectedImages = Set(model.detectedImages.map(\.url))
                            showImages = true
                        }
                    }
                } label: {
                    Label("Capturar imágenes como PDF", systemImage: "photo.on.rectangle.angled")
                }
            } label: {
                HStack(spacing: 7) {
                    if model.isScanning {
                        ProgressView().controlSize(.mini).tint(Theme.bg)
                    } else {
                        Image(systemName: "square.and.arrow.down").font(.system(size: 13, weight: .semibold))
                    }
                    Text("Guardar").font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(Theme.bg)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(Theme.accent)
                .clipShape(Capsule())
            }
            .disabled(model.currentURL == nil || model.isScanning || capture.isRunning)
            .opacity(model.currentURL == nil ? 0.4 : 1)

            Spacer()

            toolbarButton("house", enabled: true) {
                model.addressText = ""
                model.webView.load(URLRequest(url: URL(string: "about:blank")!))
                model.currentURL = nil
            }
            Color.clear.frame(width: 44, height: 1)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }

    private func toolbarButton(_ icon: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(enabled ? Theme.text : Theme.textFaint)
                .frame(width: 44, height: 32)
        }
        .disabled(!enabled)
    }

    // MARK: - Pantalla inicial

    private var startScreen: some View {
        ZStack {
            Theme.bg
            VStack(spacing: 18) {
                Image(systemName: "safari")
                    .font(.system(size: 36, weight: .ultraLight))
                    .foregroundStyle(Theme.textFaint)
                Text("Abre una web y guárdala para leer")
                    .font(.headline)
                    .foregroundStyle(Theme.text)
                Text("Cuando la página sirva un PDF, Onyx lo guarda en tu biblioteca en lugar de abrirlo en el visor del sistema.\n\nSi el PDF está detrás de un enlace o la página es un lector de imágenes (manga o cómic), pulsa «Guardar» y elige la opción que corresponda.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 36)

                if !lastURL.isEmpty {
                    Button {
                        model.addressText = lastURL
                        model.go(to: lastURL)
                    } label: {
                        Label("Continuar donde lo dejaste", systemImage: "clock.arrow.circlepath")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(Theme.accentAlt)
                }
            }
        }
    }

    // MARK: - Hoja de PDFs detectados

    private var detectedSheet: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                List {
                    Section {
                        ForEach(model.detectedPDFs, id: \.self) { url in
                            Button {
                                showDetected = false
                                model.download(url: url)
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(url.lastPathComponent.isEmpty ? url.host ?? "Archivo" : url.lastPathComponent)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(Theme.text)
                                        .lineLimit(1)
                                    Text(url.absoluteString)
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textFaint)
                                        .lineLimit(1)
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text("Enlaces detectados")
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Descargar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { showDetected = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func banner(title: String, detail: String, progress: Double) -> some View {
        VStack(spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                Spacer()
                Text(detail)
                    .font(.caption.monospacedDigit())
            }
            .foregroundStyle(Theme.text)
            ProgressBar(value: progress)
        }
        .padding(14)
        .frame(maxWidth: .infinity)
        .background(Theme.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner, style: .continuous).stroke(Theme.stroke, lineWidth: 1))
        .padding(.horizontal, 16)
        .shadow(color: .black.opacity(0.6), radius: 14, y: 6)
    }

    // MARK: - Hoja de imágenes detectadas

    private var imagesSheet: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()
                List {
                    Section {
                        ForEach(Array(model.detectedImages.enumerated()), id: \.element.id) { index, image in
                            Button {
                                if selectedImages.contains(image.url) {
                                    selectedImages.remove(image.url)
                                } else {
                                    selectedImages.insert(image.url)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: selectedImages.contains(image.url) ? "checkmark.circle.fill" : "circle")
                                        .font(.system(size: 16))
                                        .foregroundStyle(selectedImages.contains(image.url) ? Theme.accent : Theme.textFaint)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text("Página \(index + 1) · \(image.sizeLabel)")
                                            .font(.footnote.weight(.medium))
                                            .foregroundStyle(Theme.text)
                                            .lineLimit(1)
                                        Text(image.url.absoluteString)
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textFaint)
                                            .lineLimit(1)
                                    }
                                }
                            }
                            .listRowBackground(Theme.surface)
                        }
                    } header: {
                        Text("\(model.detectedImages.count) imágenes en orden de lectura")
                            .foregroundStyle(Theme.textFaint)
                    } footer: {
                        Text("Se unirán en un PDF, una página por imagen. Desmarca las que sean portadas de anuncios o logos.")
                            .foregroundStyle(Theme.textFaint)
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Capturar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(selectedImages.count == model.detectedImages.count ? "Ninguna" : "Todas") {
                        if selectedImages.count == model.detectedImages.count {
                            selectedImages = []
                        } else {
                            selectedImages = Set(model.detectedImages.map(\.url))
                        }
                    }
                    .tint(Theme.accentAlt)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { showImages = false }
                }
            }
            .safeAreaInset(edge: .bottom) {
                Button {
                    showImages = false
                    captureSelectedImages()
                } label: {
                    Text("Crear PDF con \(selectedImages.count) imágenes")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SoftButtonStyle())
                .disabled(selectedImages.isEmpty)
                .opacity(selectedImages.isEmpty ? 0.4 : 1)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(Theme.bg)
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func captureSelectedImages() {
        let chosen = model.detectedImages.filter { selectedImages.contains($0.url) }
        guard !chosen.isEmpty else { return }
        let referer = model.currentURL
        let title = model.suggestedCaptureTitle

        Task {
            let cookies = await model.currentCookies()
            do {
                let fileURL = try await capture.buildPDF(
                    from: chosen,
                    referer: referer,
                    cookies: cookies,
                    title: title
                )
                let folder = fileURL.deletingLastPathComponent()
                guard let item = store.addPDF(
                    from: fileURL,
                    suggestedTitle: title,
                    sourceURL: referer,
                    move: true
                ) else {
                    try? FileManager.default.removeItem(at: folder)
                    return
                }
                try? FileManager.default.removeItem(at: folder)
                savedTitle = item.title
                await drive.handleNewImport(item, store: store)
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                savedTitle = nil
                if let warning = capture.lastWarning {
                    capture.lastWarning = nil
                    errorText = warning
                }
            } catch {
                errorText = error.localizedDescription
            }
        }
    }

    // MARK: - Configuración

    private func configure() {
        model.onError = { message in errorText = message }

        model.onDownloadFinished = { fileURL, suggestedName, origin in
            guard let item = store.addPDF(from: fileURL, suggestedTitle: suggestedName, sourceURL: origin) else { return }
            try? FileManager.default.removeItem(at: fileURL.deletingLastPathComponent())
            savedTitle = item.title
            Task {
                await drive.handleNewImport(item, store: store)
                try? await Task.sleep(nanoseconds: 2_200_000_000)
                savedTitle = nil
            }
        }

    }
}

/// Contenedor del WKWebView creado por el modelo.
struct WebViewContainer: UIViewRepresentable {
    let model: BrowserModel

    func makeUIView(context: Context) -> WKWebView { model.webView }
    func updateUIView(_ view: WKWebView, context: Context) {}
}
