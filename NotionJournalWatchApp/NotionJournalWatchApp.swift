import SwiftUI

@main
struct NotionJournalWatchApp: App {
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                NotionJournalWatchHomeView()
            }
        }
    }
}
