import Foundation
import Combine

enum NJTimeSlotCategory: String, CaseIterable, Codable, Identifiable {
    case piano = "Piano"
    case exercise = "Exercise"
    case personal = "Personal"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .piano: return "pianokeys"
        case .exercise: return "figure.run"
        case .personal: return "person"
        }
    }
}

enum NJGoalFocus: String, CaseIterable, Codable, Identifiable {
    case piano = "Piano"
    case exercise = "Exercise"
    case keyword = "Keyword"

    var id: String { rawValue }
}

struct NJTimeSlot: Identifiable, Codable {
    let id: String
    var title: String
    var category: NJTimeSlotCategory
    var startDate: Date
    var endDate: Date
    var notes: String
}

struct NJPersonalGoal: Identifiable, Codable {
    let id: String
    let title: String
    let focus: NJGoalFocus
    let keyword: String
    let weeklyTarget: Int
}

@MainActor
final class NJTimeSlotStore: ObservableObject {
    @Published private(set) var slots: [NJTimeSlot] = []
    @Published private(set) var goals: [NJPersonalGoal] = []

    static let appGroupID = "group.com.CYC.NotionJournal"

    private let slotsKey = "nj_time_module_slots_v1"
    private let goalsKey = "nj_time_module_goals_v1"
    private let defaults: UserDefaults
    private let calendar = Calendar.current

    init(defaults: UserDefaults? = nil) {
        if let defaults {
            self.defaults = defaults
        } else if let shared = UserDefaults(suiteName: Self.appGroupID) {
            self.defaults = shared
        } else {
            self.defaults = .standard
        }
        load()
        seedDefaultGoalsIfNeeded()
    }

    static func quickCreateNow(
        category: NJTimeSlotCategory,
        durationMinutes: Int,
        title: String,
        notes: String = ""
    ) -> Bool {
        let defaults: UserDefaults
        if let shared = UserDefaults(suiteName: appGroupID) {
            defaults = shared
        } else {
            defaults = .standard
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? category.rawValue : cleanTitle
        let start = Date()
        let durationSec = max(15 * 60, durationMinutes * 60)
        let end = start.addingTimeInterval(TimeInterval(durationSec))

        var slots: [NJTimeSlot] = []
        if let data = defaults.data(forKey: "nj_time_module_slots_v1"),
           let decoded = try? JSONDecoder().decode([NJTimeSlot].self, from: data) {
            slots = decoded
        }

        let slot = NJTimeSlot(
            id: UUID().uuidString.lowercased(),
            title: finalTitle,
            category: category,
            startDate: start,
            endDate: end,
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        slots.append(slot)

        guard let data = try? JSONEncoder().encode(slots) else { return false }
        defaults.set(data, forKey: "nj_time_module_slots_v1")
        return true
    }

    var sortedSlots: [NJTimeSlot] {
        slots.sorted { a, b in
            if a.startDate == b.startDate { return a.id > b.id }
            return a.startDate < b.startDate
        }
    }

    var sortedGoals: [NJPersonalGoal] {
        goals.sorted { a, b in
            if a.title.caseInsensitiveCompare(b.title) == .orderedSame { return a.id > b.id }
            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    func addSlot(title: String, category: NJTimeSlotCategory, startDate: Date, endDate: Date, notes: String) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? category.rawValue : cleanTitle
        let slot = NJTimeSlot(
            id: UUID().uuidString.lowercased(),
            title: finalTitle,
            category: category,
            startDate: startDate,
            endDate: max(endDate, startDate.addingTimeInterval(15 * 60)),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        slots.append(slot)
        saveSlots()
    }

    func removeSlots(at offsets: IndexSet) {
        let base = sortedSlots
        let ids: [String] = offsets.compactMap { idx in
            guard idx >= 0, idx < base.count else { return nil }
            return base[idx].id
        }
        guard !ids.isEmpty else { return }
        slots.removeAll { ids.contains($0.id) }
        saveSlots()
    }

    func updateSlot(id: String, title: String, category: NJTimeSlotCategory, startDate: Date, endDate: Date, notes: String) {
        guard let idx = slots.firstIndex(where: { $0.id == id }) else { return }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        slots[idx].title = cleanTitle.isEmpty ? category.rawValue : cleanTitle
        slots[idx].category = category
        slots[idx].startDate = startDate
        slots[idx].endDate = max(endDate, startDate.addingTimeInterval(15 * 60))
        slots[idx].notes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        saveSlots()
    }

    func addGoal(title: String, focus: NJGoalFocus, keyword: String, weeklyTarget: Int) {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanKeyword = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        let target = max(1, min(14, weeklyTarget))
        goals.append(
            NJPersonalGoal(
                id: UUID().uuidString.lowercased(),
                title: cleanTitle,
                focus: focus,
                keyword: cleanKeyword,
                weeklyTarget: target
            )
        )
        saveGoals()
    }

    func removeGoals(at offsets: IndexSet) {
        let base = sortedGoals
        let ids: [String] = offsets.compactMap { idx in
            guard idx >= 0, idx < base.count else { return nil }
            return base[idx].id
        }
        guard !ids.isEmpty else { return }
        goals.removeAll { ids.contains($0.id) }
        saveGoals()
    }

    func progressThisWeek(for goal: NJPersonalGoal, now: Date = Date()) -> Int {
        let weekStart = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
        return slots.filter { slot in
            guard slot.startDate >= weekStart, slot.startDate < weekEnd else { return false }
            return matches(goal: goal, slot: slot)
        }.count
    }

    func reload() {
        load()
    }

    private func matches(goal: NJPersonalGoal, slot: NJTimeSlot) -> Bool {
        let haystack = "\(slot.title) \(slot.notes) \(slot.category.rawValue)".lowercased()
        switch goal.focus {
        case .piano:
            return slot.category == .piano || haystack.contains("piano")
        case .exercise:
            if slot.category == .exercise { return true }
            let exerciseHints = ["exercise", "workout", "run", "walk", "swim", "gym", "cycle", "bike", "tennis"]
            return exerciseHints.contains { haystack.contains($0) }
        case .keyword:
            let key = goal.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { return false }
            return haystack.contains(key)
        }
    }

    private func load() {
        if let data = defaults.data(forKey: slotsKey),
           let decoded = try? JSONDecoder().decode([NJTimeSlot].self, from: data) {
            slots = decoded
        }
        if let data = defaults.data(forKey: goalsKey),
           let decoded = try? JSONDecoder().decode([NJPersonalGoal].self, from: data) {
            goals = decoded
        }
    }

    private func seedDefaultGoalsIfNeeded() {
        guard goals.isEmpty else { return }
        goals = [
            NJPersonalGoal(
                id: UUID().uuidString.lowercased(),
                title: "Practice piano consistently",
                focus: .piano,
                keyword: "piano",
                weeklyTarget: 5
            ),
            NJPersonalGoal(
                id: UUID().uuidString.lowercased(),
                title: "Exercise consistently",
                focus: .exercise,
                keyword: "exercise",
                weeklyTarget: 4
            )
        ]
        saveGoals()
    }

    private func saveSlots() {
        guard let data = try? JSONEncoder().encode(slots) else { return }
        defaults.set(data, forKey: slotsKey)
    }

    private func saveGoals() {
        guard let data = try? JSONEncoder().encode(goals) else { return }
        defaults.set(data, forKey: goalsKey)
    }
}
