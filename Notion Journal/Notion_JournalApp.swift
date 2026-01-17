import SwiftUI

@main
struct Notion_JournalApp: App {
    @StateObject private var store = AppStore()
    @StateObject private var clipPDFWindowState = ClipPDFWindowState()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(clipPDFWindowState)
        }

        WindowGroup(id: "clip-pdf") {
            NJClipPDFWindowPage()
                .environmentObject(store)
                .environmentObject(clipPDFWindowState)
        }
    }
}
