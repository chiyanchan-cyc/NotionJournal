import WidgetKit
import SwiftUI

@main
struct NotionJournalWidgetBundle: WidgetBundle {
    var body: some Widget {
        NJGoalJournalWidget()
        NJHabitWidget()
    }
}
