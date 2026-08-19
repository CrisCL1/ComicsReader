import SwiftUI

struct RootView: View {

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var drive: DriveSync
    @State private var tab: Tab = .library

    enum Tab: Hashable { case library, favorites, browser, settings }

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $tab) {
                LibraryView()
                    .tabItem { Label("Biblioteca", systemImage: "books.vertical") }
                    .tag(Tab.library)

                FavoritesView()
                    .tabItem { Label("Favoritos", systemImage: "star") }
                    .tag(Tab.favorites)

                BrowserView()
                    .tabItem { Label("Buscar", systemImage: "safari") }
                    .tag(Tab.browser)

                SettingsView()
                    .tabItem { Label("Ajustes", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }
            .tint(Theme.accent)

            if let message = drive.statusMessage {
                Toast(text: message, tone: .neutral)
                    .padding(.bottom, 70)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onAppear {
                        Task {
                            try? await Task.sleep(nanoseconds: 2_500_000_000)
                            if drive.statusMessage == message { drive.statusMessage = nil }
                        }
                    }
            }
        }
        .animation(.easeInOut(duration: 0.25), value: drive.statusMessage)
        .background(Theme.bg.ignoresSafeArea())
        .alert("Algo salió mal", isPresented: Binding(
            get: { drive.errorMessage != nil },
            set: { if !$0 { drive.errorMessage = nil } }
        )) {
            Button("Entendido", role: .cancel) { drive.errorMessage = nil }
        } message: {
            Text(drive.errorMessage ?? "")
        }
        .alert("Aviso", isPresented: Binding(
            get: { store.lastError != nil },
            set: { if !$0 { store.lastError = nil } }
        )) {
            Button("Entendido", role: .cancel) { store.lastError = nil }
        } message: {
            Text(store.lastError ?? "")
        }
    }
}

struct Toast: View {
    enum Tone { case neutral, good, bad }
    let text: String
    var tone: Tone = .neutral

    var body: some View {
        Text(text)
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Theme.surfaceHigh)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
    }
}
