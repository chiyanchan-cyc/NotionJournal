import SwiftUI

struct NJGoalSeedlingListSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var goals: [NJGoalSummary] = []
    @State private var searchText: String = ""

    var body: some View {
        List {
            let filtered = filteredGoals()
            let seedlings = filtered.filter { $0.goalTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let goalsWithTags = filtered.filter { !$0.goalTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

            Section(header: Text("Seedlings")) {
                if seedlings.isEmpty {
                    Text("No seedlings")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(seedlings) { item in
                        NavigationLink {
                            NJGoalDetailView(goalID: item.goalID)
                                .environmentObject(store)
                        } label: {
                            GoalRow(item: item)
                        }
                    }
                }
            }

            Section(header: Text("Goals")) {
                if goalsWithTags.isEmpty {
                    Text("No goals")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(goalsWithTags) { item in
                        NavigationLink {
                            NJGoalDetailView(goalID: item.goalID)
                                .environmentObject(store)
                        } label: {
                            GoalRow(item: item)
                        }
                    }
                }
            }
        }
        .navigationTitle("Goals / Seedlings")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Refresh") { reload() }
            }
        }
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
        .onAppear { reload() }
    }

    private func filteredGoals() -> [NJGoalSummary] {
        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return goals.filter { item in
            if trimmedSearch.isEmpty { return true }
            if item.name.lowercased().contains(trimmedSearch) { return true }
            if item.goalTag.lowercased().contains(trimmedSearch) { return true }
            return false
        }
    }

    private func reload() {
        goals = store.notes.listGoalSummaries()
    }
}

private struct GoalRow: View {
    let item: NJGoalSummary

    var body: some View {
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

            if item.updatedAtMs > 0 {
                Text(dateString(item.updatedAtMs))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func dateString(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
