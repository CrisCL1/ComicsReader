import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var drive: DriveSync
    @EnvironmentObject private var auth: GoogleDriveAuth

    @AppStorage(DriveSync.Prefs.autoUpload) private var autoUpload = false
    @AppStorage(DriveSync.Prefs.offloadAfterUpload) private var offloadAfterUpload = false

    @State private var localUsage: Int64 = 0
    @State private var signingIn = false
    @State private var showTagManager = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        storageSection
                        driveSection
                        tagsSection
                        helpSection
                        Color.clear.frame(height: 20)
                    }
                    .padding(20)
                }
            }
            .navigationTitle("Ajustes")
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .onAppear { localUsage = FileStore.localStorageUsed() }
            .sheet(isPresented: $showTagManager) { TagManagerView() }
        }
    }

    // MARK: - Almacenamiento

    private var storageSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Almacenamiento")
            VStack(alignment: .leading, spacing: 12) {
                row("Documentos", "\(store.items.count)")
                row("Ocupado en el iPhone", ByteCountFormatter.string(fromByteCount: localUsage, countStyle: .file))
                row("Copias en Drive", "\(store.items.filter { $0.driveFileID != nil }.count)")
                row("Solo en la nube", "\(store.items.filter { !$0.isLocalAvailable }.count)")

                if store.items.contains(where: { $0.driveFileID != nil && $0.isLocalAvailable }) {
                    Divider().overlay(Theme.stroke)
                    Button {
                        Task {
                            await drive.offloadAllSynced(store: store)
                            localUsage = FileStore.localStorageUsed()
                        }
                    } label: {
                        Label("Liberar espacio de todo lo sincronizado", systemImage: "internaldrive")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(Theme.accent)
                }
            }
            .padding(14)
            .card()
        }
    }

    // MARK: - Google Drive

    private var driveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Google Drive")
            VStack(alignment: .leading, spacing: 14) {
                if !DriveConfig.isConfigured {
                    Text("Falta configurar tu Client ID de Google en DriveConfig.swift e Info.plist. Sin eso, la app funciona igual pero solo con almacenamiento local.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)
                } else if auth.isSignedIn {
                    HStack {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accentAlt)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Conectado").font(.footnote.weight(.medium)).foregroundStyle(Theme.text)
                            if let email = auth.accountEmail {
                                Text(email).font(.caption2).foregroundStyle(Theme.textFaint)
                            }
                        }
                        Spacer()
                        Button("Cerrar sesión") { auth.signOut() }
                            .font(.caption.weight(.medium))
                            .tint(Theme.danger)
                    }

                    Divider().overlay(Theme.stroke)

                    Toggle(isOn: $autoUpload) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Subir automáticamente").font(.footnote)
                            Text("Cada PDF nuevo se copia a Drive").font(.caption2).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .tint(Theme.accent)

                    Toggle(isOn: $offloadAfterUpload) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Liberar espacio tras subir").font(.footnote)
                            Text("Borra la copia local; se descarga al abrirla").font(.caption2).foregroundStyle(Theme.textFaint)
                        }
                    }
                    .tint(Theme.accent)

                    Button {
                        Task {
                            await drive.uploadAll(store: store)
                            localUsage = FileStore.localStorageUsed()
                        }
                    } label: {
                        Label("Sincronizar todo ahora", systemImage: "arrow.triangle.2.circlepath")
                            .font(.footnote.weight(.medium))
                    }
                    .tint(Theme.accent)
                } else {
                    Text("Guarda tus PDFs en tu Drive y libera espacio del iPhone. Onyx solo puede ver los archivos que ella misma crea.")
                        .font(.caption)
                        .foregroundStyle(Theme.textMuted)

                    Button {
                        signingIn = true
                        Task {
                            do { try await auth.signIn() }
                            catch { drive.errorMessage = error.localizedDescription }
                            signingIn = false
                        }
                    } label: {
                        HStack(spacing: 8) {
                            if signingIn { ProgressView().controlSize(.mini).tint(Theme.bg) }
                            Text("Conectar Google Drive")
                        }
                    }
                    .buttonStyle(SoftButtonStyle())
                    .disabled(signingIn)
                }
            }
            .foregroundStyle(Theme.text)
            .padding(14)
            .card()
        }
    }

    // MARK: - Etiquetas

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Etiquetas")
            Button { showTagManager = true } label: {
                HStack {
                    Text(store.allTags.isEmpty ? "Aún no has creado etiquetas" : "\(store.allTags.count) etiquetas")
                        .font(.footnote)
                        .foregroundStyle(store.allTags.isEmpty ? Theme.textMuted : Theme.text)
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(Theme.textFaint)
                }
                .padding(14)
                .card()
            }
            .buttonStyle(.plain)
        }
    }

    // MARK: - Ayuda

    private var helpSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Cómo añadir PDFs")
            VStack(alignment: .leading, spacing: 12) {
                helpRow("safari", "Pestaña Buscar", "Abre la web dentro de Onyx. Si sirve un PDF, se guarda solo.")
                helpRow("square.and.arrow.up", "Desde Safari", "Comparte el PDF y elige «Copiar en Onyx».")
                helpRow("folder", "Desde Archivos", "Menú ··· de la biblioteca → Importar PDF.")
            }
            .padding(14)
            .card()
        }
    }

    private func helpRow(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundStyle(Theme.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.footnote.weight(.medium)).foregroundStyle(Theme.text)
                Text(detail).font(.caption2).foregroundStyle(Theme.textMuted)
            }
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.footnote).foregroundStyle(Theme.textMuted)
            Spacer()
            Text(value).font(.footnote.weight(.medium).monospacedDigit()).foregroundStyle(Theme.text)
        }
    }
}

// MARK: - Gestor de etiquetas

struct TagManagerView: View {

    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if store.allTags.isEmpty {
                    EmptyState(
                        icon: "tag",
                        title: "Sin etiquetas",
                        message: "Crea etiquetas desde los detalles de cualquier documento."
                    ) { EmptyView() }
                } else {
                    List {
                        ForEach(store.allTags, id: \.self) { tag in
                            HStack {
                                Text(tag).font(.footnote).foregroundStyle(Theme.text)
                                Spacer()
                                Text("\(store.count(forTag: tag))")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(Theme.textFaint)
                            }
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button(role: .destructive) { store.deleteTag(tag) } label: {
                                    Label("Borrar", systemImage: "trash")
                                }
                                Button {
                                    renaming = tag
                                    newName = tag
                                } label: {
                                    Label("Renombrar", systemImage: "pencil")
                                }
                                .tint(Theme.accentAlt)
                            }
                        }
                    }
                    .scrollContentBackground(.hidden)
                }
            }
            .navigationTitle("Etiquetas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { dismiss() }
                }
            }
            .alert("Renombrar etiqueta", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Nombre", text: $newName)
                Button("Guardar") {
                    if let old = renaming { store.renameTag(old, to: newName) }
                    renaming = nil
                }
                Button("Cancelar", role: .cancel) { renaming = nil }
            }
        }
    }
}
