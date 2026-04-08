import WidgetKit
import SwiftUI
import AppIntents

private struct NJWidgetTimeSlot: Codable {
    let id: String
    let title: String
    let category: String
    let startDate: Date
    let endDate: Date
    let notes: String
}

@available(watchOS 10.0, *)
struct NJComplicationEntry: TimelineEntry {
    let date: Date
    let todayCount: Int
}

@available(watchOS 10.0, *)
struct NJComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> NJComplicationEntry {
        NJComplicationEntry(date: Date(), todayCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (NJComplicationEntry) -> Void) {
        completion(NJComplicationEntry(date: Date(), todayCount: loadTodayCount()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NJComplicationEntry>) -> Void) {
        let now = Date()
        let entry = NJComplicationEntry(date: now, todayCount: loadTodayCount())
        let next = Calendar.current.date(byAdding: .minute, value: 20, to: now) ?? now.addingTimeInterval(1200)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadTodayCount() -> Int {
        guard let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal"),
              let data = defaults.data(forKey: "nj_time_module_slots_v1"),
              let slots = try? JSONDecoder().decode([NJWidgetTimeSlot].self, from: data) else {
            return 0
        }

        let cal = Calendar.current
        let start = cal.startOfDay(for: Date())
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start
        return slots.filter { $0.startDate >= start && $0.startDate < end }.count
    }
}

@available(watchOS 10.0, *)
struct NJComplicationWidgetView: View {
    let entry: NJComplicationEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch family {
            case .accessoryInline:
                Text("Time \(entry.todayCount)")
            case .accessoryCircular:
                ZStack {
                    Circle()
                        .fill(.tertiary)
                    VStack(spacing: 1) {
                        Text("Time")
                            .font(.system(size: 7, weight: .medium))
                        Text("\(entry.todayCount)")
                            .font(.system(size: 15, weight: .bold))
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 6) {
                    Text("Time")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("Today \(entry.todayCount)")
                        .font(.headline)
                    HStack(spacing: 8) {
                        Button(intent: quickIntent(.piano, title: "Piano Practice")) {
                            Image(systemName: "pianokeys")
                        }
                        .buttonStyle(.borderless)

                        Button(intent: quickIntent(.exercise, title: "Exercise")) {
                            Image(systemName: "figure.run")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            default:
                Text("Time \(entry.todayCount)")
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private func quickIntent(_ category: NJComplicationCategory, title: String) -> NJComplicationQuickLogIntent {
        var intent = NJComplicationQuickLogIntent()
        intent.category = category
        intent.durationMinutes = 45
        intent.title = title
        intent.comment = "From complication"
        return intent
    }
}

@available(watchOS 10.0, *)
struct NJComplicationWidget: Widget {
    let kind = "NJComplicationWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NJComplicationProvider()) { entry in
            NJComplicationWidgetView(entry: entry)
        }
        .configurationDisplayName("Time Quick Log")
        .description("Quickly add piano or exercise slots.")
        .supportedFamilies([
            .accessoryRectangular,
            .accessoryInline,
            .accessoryCircular
        ])
    }
}
