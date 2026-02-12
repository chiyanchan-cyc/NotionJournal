import SwiftUI

@main
struct Notion_JournalApp: App {
    @StateObject private var store = AppStore()
    // Ensure GPS logger is initialized at app launch so background logging starts
    @StateObject private var gpsLogger = NJGPSLogger.shared
    // Ensure Health logger is initialized at app launch so sync can run
    @StateObject private var healthLogger = NJHealthLogger.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onOpenURL { url in
                    if NJAudioShareReceiver.handleIncomingURL(url) != nil {
                        store.runAudioIngestIfNeeded()
                    }
                }
        }

        WindowGroup(id: "clip-pdf", for: URL.self) { url in
            NJClipPDFWindowPage(url: url.wrappedValue)
                .environmentObject(store)
        }

        WindowGroup(id: "reconstructed-weekly") {
            NJReconstructedNoteView(spec: .weekly())
                .environmentObject(store)
        }

        WindowGroup(id: "reconstructed-workspace") {
            NJReconstructedWorkspaceView()
                .environmentObject(store)
        }

        WindowGroup(id: "reconstructed-manual", for: String.self) { tag in
            NJReconstructedManualView(initialTag: tag.wrappedValue ?? "#REMIND")
                .environmentObject(store)
        }

        WindowGroup(id: "calendar") {
            NJCalendarView()
                .environmentObject(store)
        }

        WindowGroup(id: "chrono") {
            NJChronoNoteListView()
                .environmentObject(store)
        }

        WindowGroup(id: "goals") {
            NJGoalWorkspaceView()
                .environmentObject(store)
        }

        WindowGroup(id: "outline-node-detail", for: String.self) { nodeID in
            if let id = nodeID.wrappedValue {
                NJOutlineNodeDetailWindowView(outline: store.outline, nodeID: id)
                    .environmentObject(store)
            } else {
                ContentUnavailableView("Node not found", systemImage: "exclamationmark.triangle")
            }
        }

        WindowGroup(id: "photo-viewer", for: String.self) { id in
            NJPhotoWindow(localIdentifier: id.wrappedValue)
        }
    }
}
