import WidgetKit
import SwiftUI

struct NJJournalGoalDay: Codable, Hashable, Identifiable {
    let key: String
    let shortLabel: String

    var id: String { key }
}

struct NJJournalGoalRow: Codable, Hashable, Identifiable {
    let id: String
    let owner: String
    let name: String
    let goalTag: String
    let filledDayKeys: [String]

    var filledDayKeySet: Set<String> { Set(filledDayKeys) }
}

struct NJJournalGoalSection: Codable, Hashable, Identifiable {
    let owner: String
    let rows: [NJJournalGoalRow]

    var id: String { owner }
}

struct NJJournalGoalSnapshot: Codable, Hashable {
    let days: [NJJournalGoalDay]
    let sections: [NJJournalGoalSection]
    let generatedAt: Date
}

struct NJGoalJournalEntry: TimelineEntry {
    let date: Date
    let snapshot: NJJournalGoalSnapshot
    let error: String?
}

private final class NJGoalJournalWidgetProvider {
    private let appGroupID = "group.com.CYC.NotionJournal"
    private let cacheKey = "nj.widget.goal_journal.snapshot.v1"
    func loadSnapshot() throws -> NJJournalGoalSnapshot {
        guard let snapshot = loadCachedSnapshot() else {
            throw NSError(domain: "NJGoalJournalWidget", code: 1, userInfo: [NSLocalizedDescriptionKey: "Local snapshot unavailable"])
        }
        return snapshot
    }

    private func loadCachedSnapshot() -> NJJournalGoalSnapshot? {
        guard let defaults = UserDefaults(suiteName: appGroupID),
              let data = defaults.data(forKey: cacheKey),
              let snapshot = try? JSONDecoder().decode(NJJournalGoalSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}

struct NJGoalJournalTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> NJGoalJournalEntry {
        NJGoalJournalEntry(
            date: Date(),
            snapshot: NJJournalGoalSnapshot(
                days: [
                    NJJournalGoalDay(key: "2026-04-01", shortLabel: "Tue"),
                    NJJournalGoalDay(key: "2026-04-02", shortLabel: "Wed"),
                    NJJournalGoalDay(key: "2026-04-03", shortLabel: "Thu"),
                    NJJournalGoalDay(key: "2026-04-04", shortLabel: "Fri"),
                    NJJournalGoalDay(key: "2026-04-05", shortLabel: "Sat"),
                    NJJournalGoalDay(key: "2026-04-06", shortLabel: "Sun"),
                    NJJournalGoalDay(key: "2026-04-07", shortLabel: "Mon"),
                ],
                sections: [
                    NJJournalGoalSection(owner: "ME", rows: [
                        NJJournalGoalRow(id: "1", owner: "ME", name: "Piano momentum", goalTag: "g.me.music.piano", filledDayKeys: ["2026-04-02", "2026-04-05"]),
                        NJJournalGoalRow(id: "2", owner: "ME", name: "Exercise streak", goalTag: "g.me.health.exercise", filledDayKeys: ["2026-04-01", "2026-04-03", "2026-04-06"]),
                    ])
                ],
                generatedAt: Date()
            ),
            error: nil
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (NJGoalJournalEntry) -> Void) {
        completion(placeholder(in: context))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NJGoalJournalEntry>) -> Void) {
        let provider = NJGoalJournalWidgetProvider()
        do {
            let snapshot = try provider.loadSnapshot()
            let entry = NJGoalJournalEntry(date: Date(), snapshot: snapshot, error: nil)
            completion(Timeline(entries: [entry], policy: .never))
        } catch {
            let entry = NJGoalJournalEntry(date: Date(), snapshot: placeholder(in: context).snapshot, error: "Local snapshot unavailable")
            completion(Timeline(entries: [entry], policy: .never))
        }
    }
}

struct NJGoalJournalWidget: Widget {
    let kind = "NJGoalJournalWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NJGoalJournalTimelineProvider()) { entry in
            NJGoalJournalWidgetView(entry: entry)
        }
        .configurationDisplayName("Goal Journal")
        .description("Past 7 days by goal and owner.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

private struct NJGoalJournalWidgetView: View {
    let entry: NJGoalJournalEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text("Goal Journal")
                    .font(.system(size: 12, weight: .semibold))
                Spacer(minLength: 0)
                Text("7 days")
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
            }

            if let error = entry.error {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else if visibleRows.isEmpty {
                Text("No active tagged goals")
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
                Text("Goal")
                    .font(.system(size: 8, weight: .medium))
                    .frame(width: labelWidth, alignment: .leading)
                ForEach(entry.snapshot.days) { day in
                    Text(day.shortLabel)
                        .font(.system(size: 7))
                        .foregroundStyle(.secondary)
                        .frame(width: cellWidth)
                }
            }

            ForEach(visibleRows, id: \.id) { row in
                HStack(spacing: 2) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(row.owner) \(row.name)")
                            .font(.system(size: 7.5, weight: .medium))
                            .lineLimit(1)
                        Text(row.goalTag)
                            .font(.system(size: 6))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(width: labelWidth, alignment: .leading)

                    ForEach(entry.snapshot.days) { day in
                        let filled = row.filledDayKeySet.contains(day.key)
                        ZStack {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(filled ? Color.green.opacity(0.22) : Color(.secondarySystemBackground))
                            if filled {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 7, weight: .bold))
                                    .foregroundStyle(Color.green)
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

    private var visibleRows: [NJJournalGoalRow] {
        let allRows = entry.snapshot.sections.flatMap(\.rows)
        return Array(allRows.prefix(maxRows))
    }

    private var labelWidth: CGFloat { family == .systemLarge ? 120 : 102 }
    private var cellWidth: CGFloat { family == .systemLarge ? 24 : 20 }
    private var rowHeight: CGFloat { family == .systemLarge ? 20 : 18 }
    private var maxRows: Int { 10 }
}
