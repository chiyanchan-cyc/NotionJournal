import SwiftUI

struct NJGoalQuickPickSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let onInsert: ([NJGoalSummary]) -> Void

    @State private var goals: [NJGoalSummary] = []
    @State private var selectedGoalIDs: Set<String> = []
    @State private var searchText: String = ""
    @State private var domainFilter: String = ""
    @State private var lastJournaledByTag: [String: Int64] = [:]

    private let excludedGoalTag = "g.zz.adhd.efinitiation"
    private let staleDays: Int = 14

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar()
                Divider()
                list()
            }
            .navigationTitle("Active Goals")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        let picked = goals.filter { selectedGoalIDs.contains($0.goalID) }
                        onInsert(picked)
                        dismiss()
                    }
                    .disabled(selectedGoalIDs.isEmpty)
                }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear { reload() }
    }

    private func filterBar() -> some View {
        HStack(spacing: 12) {
            TextField("Filter by domain (e.g. zz.adhd)", text: $domainFilter)
                .textFieldStyle(.roundedBorder)
            Button("Clear") { domainFilter = "" }
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func list() -> some View {
        List {
            let filtered = filteredGoals()
            if filtered.isEmpty {
                Text("No goals")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filtered) { item in
                    Button {
                        toggle(item.goalID)
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: selectedGoalIDs.contains(item.goalID) ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(selectedGoalIDs.contains(item.goalID) ? Color.accentColor : Color.secondary)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.name.isEmpty ? "Untitled" : item.name)
                                    .font(.body)
                                    .lineLimit(1)
                                if !item.goalTag.isEmpty {
                                    Text(item.goalTag)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Text(lastJournaledString(item.goalTag))
                                    .font(.caption2)
                                    .foregroundStyle(lastJournaledColor(item.goalTag))
                                Text(lastUpdatedString(item.updatedAtMs))
                                    .font(.caption2)
                                    .foregroundStyle(isStale(item.updatedAtMs) ? .red : .secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .listStyle(.plain)
    }

    private func toggle(_ id: String) {
        if selectedGoalIDs.contains(id) {
            selectedGoalIDs.remove(id)
        } else {
            selectedGoalIDs.insert(id)
        }
    }

    private func filteredGoals() -> [NJGoalSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let domFilter = domainFilter.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return goals.filter { item in
            if item.goalTag == excludedGoalTag { return false }
            if isArchived(item.status) { return false }
            if item.goalTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return false }
            if !domFilter.isEmpty {
                let domains = parseDomainTags(item.domainTagsJSON)
                let hit = domains.contains { $0.lowercased().contains(domFilter) }
                if !hit { return false }
            }
            if trimmedSearch.isEmpty { return true }
            if item.name.lowercased().contains(trimmedSearch) { return true }
            if item.goalTag.lowercased().contains(trimmedSearch) { return true }
            return false
        }
    }

    private func parseDomainTags(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr
    }

    private func isArchived(_ status: String) -> Bool {
        let s = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["archive", "archived", "done", "closed"].contains(s)
    }

    private func isStale(_ updatedAtMs: Int64) -> Bool {
        if updatedAtMs <= 0 { return true }
        let now = Date().timeIntervalSince1970 * 1000.0
        let ageMs = now - Double(updatedAtMs)
        return ageMs > Double(staleDays) * 24 * 60 * 60 * 1000
    }

    private func lastUpdatedString(_ ms: Int64) -> String {
        if ms <= 0 { return "-" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func reload() {
        goals = store.notes.listGoalSummaries()
        lastJournaledByTag = [:]
        for g in goals {
            let tag = g.goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if tag.isEmpty { continue }
            let ms = store.notes.lastJournaledAtMsForTag(tag)
            lastJournaledByTag[tag] = ms
        }
    }

    private func lastJournaledString(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ms = lastJournaledByTag[trimmed], ms > 0 else { return "Last journaled: -" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return "Last journaled: \(f.string(from: d))"
    }

    private func lastJournaledColor(_ tag: String) -> Color {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let ms = lastJournaledByTag[trimmed], ms > 0 else { return .secondary }
        let now = Date().timeIntervalSince1970 * 1000.0
        let ageDays = (now - Double(ms)) / (24 * 60 * 60 * 1000)
        if ageDays > 7 { return .red }
        if ageDays > 3 { return .pink }
        return .secondary
    }
}
