import SwiftUI

@main
struct OnyxApp: App {

    @StateObject private var store = LibraryStore()
    @StateObject private var drive = DriveSync()
    @StateObject private var auth  = GoogleDriveAuth.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(drive)
                .environmentObject(auth)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
                // PDFs recibidos desde la hoja de compartir de Safari
                .onOpenURL { url in
                    if url.pathExtension.lowercased() == "pdf" {
                        store.addPDF(from: url, move: url.path.contains("/Inbox/"))
                    }
                    store.importInboxIfNeeded()
                }
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:     store.importInboxIfNeeded()
            case .background: store.saveNow()
            default:          break
            }
        }
    }
}
