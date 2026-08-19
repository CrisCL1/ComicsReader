import SwiftUI

struct FavoritesView: View {

    @EnvironmentObject private var store: LibraryStore
    @EnvironmentObject private var drive: DriveSync

    @State private var openItem: LibraryItem?
    @State private var detailItem: LibraryItem?
    @State private var loadingItemID: UUID?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.bg.ignoresSafeArea()

                if store.favorites.isEmpty {
                    EmptyState(
                        icon: "star",
                        title: "Sin favoritos todavía",
                        message: "Toca la estrella de cualquier documento para tenerlo siempre a mano."
                    ) { EmptyView() }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(store.favorites) { item in
                                DocumentCard(
                                    item: item,
                                    onOpen: { open(item) },
                                    onToggleFavorite: { store.toggleFavorite(item) }
                                )
                                .contextMenu {
                                    Button { detailItem = item } label: {
                                        Label("Detalles y etiquetas", systemImage: "tag")
                                    }
                                    Button { store.toggleFavorite(item) } label: {
                                        Label("Quitar de favoritos", systemImage: "star.slash")
                                    }
                                }
                                .overlay {
                                    if loadingItemID == item.id {
                                        RoundedRectangle(cornerRadius: Theme.corner, style: .continuous)
                                            .fill(.black.opacity(0.55))
                                            .overlay(ProgressView().tint(Theme.accent))
                                    }
                                }
                            }
                            Color.clear.frame(height: 24)
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 4)
                    }
                }
            }
            .navigationTitle("Favoritos")
            .toolbarBackground(Theme.bg, for: .navigationBar)
            .fullScreenCover(item: $openItem) { item in
                ReaderView(itemID: item.id)
            }
            .sheet(item: $detailItem) { item in
                DocumentDetailView(itemID: item.id)
            }
        }
    }

    private func open(_ item: LibraryItem) {
        if FileStore.exists(item) {
            openItem = item
            return
        }
        loadingItemID = item.id
        Task {
            let ok = await drive.fetch(item, store: store)
            loadingItemID = nil
            if ok, let fresh = store.item(id: item.id) { openItem = fresh }
        }
    }
}
