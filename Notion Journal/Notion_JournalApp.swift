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

        WindowGroup(id: "reconstructed-manual") {
            NJReconstructedManualView()
                .environmentObject(store)
        }

        WindowGroup(id: "calendar") {
            NJCalendarView()
                .environmentObject(store)
        }
    }
}
