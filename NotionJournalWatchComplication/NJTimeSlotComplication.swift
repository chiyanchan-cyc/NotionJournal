import WidgetKit
import SwiftUI
import AppIntents

@available(watchOS 10.0, *)
struct NJTimeSlotComplicationEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
}

@available(watchOS 10.0, *)
struct NJTimeSlotComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> NJTimeSlotComplicationEntry {
        NJTimeSlotComplicationEntry(date: Date(), todayCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (NJTimeSlotComplicationEntry) -> Void) {
        completion(NJTimeSlotComplicationEntry(date: Date(), todayCount: loadTodayCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NJTimeSlotComplicationEntry>) -> Void) {
        let now = Date()
        let entry = NJTimeSlotComplicationEntry(date: now, todayCount: loadTodayCount())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: now) ?? now.addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadTodayCount() -> Int {
        guard let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal"),
              let data = defaults.data(forKey: "nj_time_module_slots_v1") else {
            return 0
        }
        guard let slots = try? JSONDecoder().decode([NJTimeSlot].self, from: data) else {
            return 0
        }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return slots.filter { $0.startDate >= start && $0.startDate < end }.count
    }
}

@available(watchOS 10.0, *)
struct NJTimeSlotComplicationView: View {
    var entry: NJTimeSlotComplicationProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Time")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text("Today \(entry.todayCount)")
                .font(.headline)
            Button(intent: quickIntent(.piano)) {
                Label("Piano", systemImage: "pianokeys")
            }
            .buttonStyle(.plain)
            Button(intent: quickIntent(.exercise)) {
                Label("Exercise", systemImage: "figure.run")
            }
            .buttonStyle(.plain)
        }
        .padding(6)
    }

    private func quickIntent(_ category: NJTimeSlotCategoryIntent) -> NJLogTimeSlotIntent {
        var intent = NJLogTimeSlotIntent()
        intent.category = category
        intent.durationMinutes = 45
        intent.title = category == .piano ? "Piano Practice" : "Exercise"
        intent.notes = "From Watch"
        return intent
    }
}

@available(watchOS 10.0, *)
struct NJTimeSlotComplication: Widget {
    let kind: String = "NJTimeSlotComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NJTimeSlotComplicationProvider()) { entry in
            NJTimeSlotComplicationView(entry: entry)
        }
        .configurationDisplayName("Time Slot")
        .description("Quickly create piano/exercise time slots.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular
        ])
    }
}
