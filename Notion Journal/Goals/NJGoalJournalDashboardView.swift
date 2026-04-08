import SwiftUI

private struct NJGoalJournalDay: Identifiable, Hashable {
    let date: Date
    let key: String

    var id: String { key }
}

private struct NJGoalJournalRow: Identifiable, Hashable {
    let goalID: String
    let owner: String
    let name: String
    let goalTag: String
    let dateKeysWithEntries: Set<String>

    var id: String { goalID }
}

private struct NJGoalJournalSection: Identifiable, Hashable {
    let owner: String
    let rows: [NJGoalJournalRow]

    var id: String { owner }
}

struct NJGoalJournalDashboardView: View {
    @EnvironmentObject var store: AppStore

    @State private var days: [NJGoalJournalDay] = []
    @State private var sections: [NJGoalJournalSection] = []

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            VStack(alignment: .leading, spacing: 16) {
                headerCard()

                if sections.isEmpty {
                    ContentUnavailableView(
                        "No Active Goals",
                        systemImage: "square.grid.3x3",
                        description: Text("Add a goal tag to an in-progress goal and it will appear here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 320)
                } else {
                    dashboardGrid()
                }
            }
            .padding(20)
        }
        .background(Color(UIColor.systemGroupedBackground))
        .navigationTitle("Goal Journal")
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .njGoalUpdated)) { _ in
            reload()
        }
    }

    private func headerCard() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Past 7 Days")
                .font(.title3.weight(.semibold))
            Text("Rows are active goals grouped by owner. Each cell reads whether a tagged journal entry exists on that day, and empty cells stay blank.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(Color(UIColor.secondarySystemGroupedBackground))
        )
    }

    private func dashboardGrid() -> some View {
        VStack(alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                VStack(alignment: .leading, spacing: 10) {
                    Text(section.owner)
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    VStack(spacing: 0) {
                        gridHeader()
                        Divider()
                        ForEach(Array(section.rows.enumerated()), id: \.element.id) { index, row in
                            gridRow(row)
                            if index < section.rows.count - 1 {
                                Divider()
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 18)
                            .stroke(Color.black.opacity(0.06), lineWidth: 1)
                    )
                }
            }
        }
    }

    private func gridHeader() -> some View {
        HStack(spacing: 0) {
            Text("Goal")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 240, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

            ForEach(days) { day in
                VStack(spacing: 3) {
                    Text(weekdayString(day.date))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(dayNumberString(day.date))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .frame(width: 66)
                .padding(.vertical, 10)
            }
        }
    }

    private func gridRow(_ row: NJGoalJournalRow) -> some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(row.name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
                Text(row.goalTag)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(width: 240, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            ForEach(days) { day in
                entryCell(hasEntry: row.dateKeysWithEntries.contains(day.key))
                    .frame(width: 66, height: 52)
            }
        }
    }

    private func entryCell(hasEntry: Bool) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(hasEntry ? Color.accentColor.opacity(0.16) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(hasEntry ? Color.accentColor.opacity(0.28) : Color.black.opacity(0.06), lineWidth: 1)
                )

            if hasEntry {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Color.accentColor)
            } else {
                Text(" ")
                    .font(.caption)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
    }

    private func reload(now: Date = Date()) {
        let recentDays = buildDays(now: now)
        let startMs = ms(Calendar.current.startOfDay(for: recentDays.first?.date ?? now))
        let endBoundary = Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: recentDays.last?.date ?? now)) ?? now
        let endMs = ms(endBoundary)

        let allGoals = store.notes.listGoalSummaries()
        let activeGoals = allGoals
            .filter { isActiveGoal(status: $0.status, goalTag: $0.goalTag) }
            .filter { !$0.goalTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        let tags = activeGoals.map(\.goalTag)
        let entryKeysByTag = store.notes.listJournalEntryDateKeysByGoalTag(
            tags: tags,
            startMs: startMs,
            endMs: endMs
        )

        let rows = activeGoals.map { goal in
            NJGoalJournalRow(
                goalID: goal.goalID,
                owner: ownerLabel(for: goal.domainTagsJSON),
                name: goal.name.isEmpty ? "Untitled" : goal.name,
                goalTag: goal.goalTag,
                dateKeysWithEntries: entryKeysByTag[goal.goalTag] ?? []
            )
        }

        days = recentDays
        sections = groupRows(rows)
    }

    private func buildDays(now: Date) -> [NJGoalJournalDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            return NJGoalJournalDay(date: date, key: DBNoteRepository.dateKey(date))
        }
    }

    private func groupRows(_ rows: [NJGoalJournalRow]) -> [NJGoalJournalSection] {
        let grouped = Dictionary(grouping: rows) { $0.owner }
        return ownerOrder(rows: rows).compactMap { owner in
            guard let ownerRows = grouped[owner], !ownerRows.isEmpty else { return nil }
            return NJGoalJournalSection(
                owner: owner,
                rows: ownerRows.sorted {
                    if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                        return $0.goalTag.localizedCaseInsensitiveCompare($1.goalTag) == .orderedAscending
                    }
                    return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            )
        }
    }

    private func ownerOrder(rows: [NJGoalJournalRow]) -> [String] {
        let preferred = ["ME", "MM", "ZZ", "DEV", "OTHER"]
        let available = Set(rows.map(\.owner))
        let orderedPreferred = preferred.filter { available.contains($0) }
        let extras = available.subtracting(preferred).sorted()
        return orderedPreferred + extras
    }

    private func ownerLabel(for domainTagsJSON: String) -> String {
        let domains = parseDomainTags(domainTagsJSON)
        let preferred = ["ME", "MM", "ZZ", "DEV"]
        for owner in preferred {
            if domains.contains(where: { topLevelDomain(of: $0) == owner }) {
                return owner
            }
        }
        if let first = domains.first.map(topLevelDomain(of:)), !first.isEmpty {
            return first
        }
        return "OTHER"
    }

    private func parseDomainTags(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr
    }

    private func topLevelDomain(of domain: String) -> String {
        let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }
        return trimmed
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).uppercased() } ?? ""
    }

    private func isActiveGoal(status: String, goalTag: String) -> Bool {
        let trimmedTag = goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { return false }
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["archive", "archived", "done", "closed"].contains(normalized) {
            return false
        }
        return true
    }

    private func weekdayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dayNumberString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "M/d"
        return formatter.string(from: date)
    }

    private func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000.0)
    }
}
