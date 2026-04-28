import WidgetKit
import SwiftUI

struct NJHabitWidgetDay: Codable, Hashable, Identifiable {
    let key: String
    let shortLabel: String

    var id: String { key }
}

struct NJHabitWidgetRow: Codable, Hashable, Identifiable {
    let id: String
    let name: String
    let subtitle: String
    let dayMinutes: [String: Int]
}

struct NJHabitWidgetSnapshot: Codable, Hashable {
    let days: [NJHabitWidgetDay]
    let rows: [NJHabitWidgetRow]
    let generatedAt: Date
}

struct NJHabitEntry: TimelineEntry {
    let date: Date
    let snapshot: NJHabitWidgetSnapshot
    let error: String?
}

private final class NJHabitWidgetProvider {
    private let appGroupID = "group.com.CYC.NotionJournal"
    private let snapshotKey = "nj.widget.habit.snapshot.v1"

    func loadSnapshot(now: Date = Date()) throws -> NJHabitWidgetSnapshot {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(NJHabitWidgetSnapshot.self, from: data) else {
            throw NSError(domain: "NJHabitWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local habit snapshot unavailable"])
        }
        return sanitizedSnapshot(snapshot, now: now)
    }

    private func sanitizedSnapshot(_ snapshot: NJHabitWidgetSnapshot, now: Date) -> NJHabitWidgetSnapshot {
        let currentDays = currentWeekDays(now: now)
        let currentKeys = currentDays.map(\.key)
        let snapshotKeys = snapshot.days.map(\.key)
        guard snapshotKeys == currentKeys else {
            return NJHabitWidgetSnapshot(days: currentDays, rows: [], generatedAt: now)
        }
        return snapshot
    }

    private func currentWeekDays(now: Date) -> [NJHabitWidgetDay] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "E"

        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -delta, to: today) ?? today

        let keyFormatter = DateFormatter()
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.dateFormat = "yyyy-MM-dd"

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return NJHabitWidgetDay(
                key: keyFormatter.string(from: date),
                shortLabel: formatter.string(from: date)
            )
        }
    }
}

struct NJHabitTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NJHabitEntry {
        NJHabitEntry(
            date: Date(),
            snapshot: NJHabitWidgetSnapshot(
                days: [
                    NJHabitWidgetDay(key: "2026-04-06", shortLabel: "Mon"),
                    NJHabitWidgetDay(key: "2026-04-07", shortLabel: "Tue"),
                    NJHabitWidgetDay(key: "2026-04-08", shortLabel: "Wed"),
                    NJHabitWidgetDay(key: "2026-04-09", shortLabel: "Thu"),
                    NJHabitWidgetDay(key: "2026-04-10", shortLabel: "Fri"),
                    NJHabitWidgetDay(key: "2026-04-11", shortLabel: "Sat"),
                    NJHabitWidgetDay(key: "2026-04-12", shortLabel: "Sun")
                ],
                rows: [
                    NJHabitWidgetRow(id: "piano|piano", name: "Piano", subtitle: "Piano • Week: 2h 30m", dayMinutes: ["2026-04-06": 60, "2026-04-08": 45, "2026-04-10": 45]),
                    NJHabitWidgetRow(id: "outdoor-jog|fitness", name: "Outdoor Jog", subtitle: "Fitness • Week: 1h 20m", dayMinutes: ["2026-04-07": 35, "2026-04-09": 45])
                ],
                generatedAt: Date()
            ),
            error: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NJHabitEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NJHabitEntry>) -> Void) {
        let provider = NJHabitWidgetProvider()
        do {
            let snapshot = try provider.loadSnapshot(now: Date())
            let entry = NJHabitEntry(date: Date(), snapshot: snapshot, error: nil)
            completion(Timeline(entries: [entry], policy: .never))
        } catch {
            let entry = NJHabitEntry(date: Date(), snapshot: placeholder(in: context).snapshot, error: "Local habit snapshot unavailable")
            completion(Timeline(entries: [entry], policy: .never))
        }
    }
}

struct NJHabitWidget: Widget {
    let kind = "NJHabitWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NJHabitTimelineProvider()) { entry in
            NJHabitWidgetView(entry: entry)
        }
        .configurationDisplayName("Time")
        .description("Distinct time slots and total time for this week.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct NJHabitWidgetView: View {
    let entry: NJHabitEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Time")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("Week time")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if let error = entry.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if visibleRows.isEmpty {
                Text("No time slots this week")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                grid
            }

            Spacer(minLength: 0)
        }
        .padding()
        .containerBackground(.fill.tertiary, for: .widget)
    }

    private var grid: some View {
        VStack(spacing: 4) {
            HStack(spacing: 2) {
                Text("Slot")
                    .font(.system(size: 8, weight: .medium))
                    .frame(width: labelWidth, alignment: .leading)
                ForEach(entry.snapshot.days) { day in
                    Text(day.shortLabel)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .frame(width: cellWidth)
                }
            }

            ForEach(visibleRows) { row in
                HStack(spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.name)
                            .font(.system(size: 7.5, weight: .medium))
                            .lineLimit(1)
                        Text(row.subtitle)
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: labelWidth, alignment: .leading)

                    ForEach(entry.snapshot.days) { day in
                        let minutes = row.dayMinutes[day.key] ?? 0
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(minutes > 0 ? Color.orange.opacity(0.18) : Color(.secondarySystemBackground))
                            if minutes > 0 {
                                Text("\(minutes)")
                                    .font(.system(size: minuteFontSize, weight: .semibold))
                                    .foregroundStyle(Color.orange)
                            } else {
                                Text(" ")
                                    .font(.system(size: 7))
                            }
                        }
                        .frame(width: cellWidth, height: rowHeight)
                    }
                }
            }
        }
    }

    private var visibleRows: [NJHabitWidgetRow] {
        Array(entry.snapshot.rows.prefix(maxRows))
    }

    private var labelWidth: CGFloat { family == .systemLarge ? 120 : 102 }
    private var cellWidth: CGFloat { family == .systemLarge ? 24 : 20 }
    private var rowHeight: CGFloat { family == .systemLarge ? 20 : 18 }
    private var minuteFontSize: CGFloat { family == .systemLarge ? 8 : 7 }
    private var maxRows: Int { 10 }
}
