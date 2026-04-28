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

struct NJWidgetActiveTracker: Codable {
    let title: String
    let startDate: Date
    let notes: String
}

private func elapsedMinutesText(since startDate: Date, now: Date) -> String {
    let elapsedSeconds = max(0, Int(now.timeIntervalSince(startDate)))
    let minutes = max(1, elapsedSeconds / 60)
    return "\(minutes)m"
}

private func elapsedClockText(since startDate: Date, now: Date) -> String {
    let elapsedSeconds = max(0, Int(now.timeIntervalSince(startDate)))
    let minutes = elapsedSeconds / 60
    let seconds = elapsedSeconds % 60
    return String(format: "%d:%02d", minutes, seconds)
}

@available(watchOS 10.0, *)
struct NJComplicationEntry: TimelineEntry {
    let date: Date
    let activeTracker: NJWidgetActiveTracker?
}

@available(watchOS 10.0, *)
struct NJComplicationProvider: TimelineProvider {
    func placeholder(in context: Context) -> NJComplicationEntry {
        NJComplicationEntry(
            date: Date(),
            activeTracker: NJWidgetActiveTracker(title: "Piano", startDate: Date().addingTimeInterval(-15 * 60), notes: "")
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NJComplicationEntry) -> Void) {
        completion(NJComplicationEntry(date: Date(), activeTracker: loadActiveTracker()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NJComplicationEntry>) -> Void) {
        let now = Date()
        let entry = NJComplicationEntry(date: now, activeTracker: loadActiveTracker())
        let next = Calendar.current.date(byAdding: .minute, value: 1, to: now) ?? now.addingTimeInterval(60)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func loadActiveTracker() -> NJWidgetActiveTracker? {
        guard let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal"),
              let data = defaults.data(forKey: "nj_watch_active_tracker_v1"),
              let tracker = try? JSONDecoder().decode(NJWidgetActiveTracker.self, from: data) else {
            return nil
        }
        return tracker
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
                if let tracker = entry.activeTracker {
                    Text("NJ \(elapsedClockText(since: tracker.startDate, now: entry.date))")
                } else {
                    Text("NJ Idle")
                }
            case .accessoryCircular:
                ZStack {
                    Circle()
                        .fill(.tertiary)
                    VStack(spacing: 2) {
                        Text("NJ")
                            .font(.system(size: 11, weight: .black, design: .rounded))
                        if let tracker = entry.activeTracker {
                            Text(elapsedClockText(since: tracker.startDate, now: entry.date))
                                .font(.system(size: 10, weight: .bold))
                                .monospacedDigit()
                        } else {
                            Text("Idle")
                                .font(.system(size: 9, weight: .bold))
                        }
                    }
                }
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Text("NJ")
                            .font(.system(size: 14, weight: .black, design: .rounded))
                            .frame(width: 18, height: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Notion Journal")
                                .font(.caption2)
                                .lineLimit(1)
                            if let tracker = entry.activeTracker {
                                Text(tracker.title)
                                    .font(.headline)
                                    .lineLimit(1)
                                Text(elapsedClockText(since: tracker.startDate, now: entry.date))
                                    .font(.caption)
                                    .monospacedDigit()
                            } else {
                                Text("No Active Timer")
                                    .font(.headline)
                            }
                        }
                    }
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
                if let tracker = entry.activeTracker {
                    Text(elapsedClockText(since: tracker.startDate, now: entry.date))
                } else {
                    Text("NJ")
                }
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
