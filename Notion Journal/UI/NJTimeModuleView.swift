import SwiftUI
import Foundation
import UIKit

private enum NJTimeModuleSection: String, CaseIterable, Identifiable {
    case slots = "Time Slots"
    case goals = "Personal Goals"

    var id: String { rawValue }
}

struct NJTimeModuleView: View {
    @EnvironmentObject var store: AppStore
    @AppStorage("nj.time.use_sections") private var useSections: Bool = true
    @AppStorage("nj.time.slots.collapsed") private var slotsCollapsed: Bool = false
    @AppStorage("nj.time.goals.collapsed") private var goalsCollapsed: Bool = false
    @State private var selectedSection: NJTimeModuleSection = .slots
    @State private var showAddSlot = false
    @State private var showAddGoal = false
    @State private var editingSlot: NJTimeSlotRecord? = nil
    @State private var slots: [NJTimeSlotRecord] = []
    @State private var goals: [NJPersonalGoalRecord] = []

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(NJTimeModuleSection.allCases) { section in
                    Text(section.rawValue).tag(section)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            if selectedSection == .slots {
                timeSlotsView()
            } else {
                goalsView()
            }
        }
        .navigationTitle("Time")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    if selectedSection == .slots {
                        showAddSlot = true
                    } else {
                        showAddGoal = true
                    }
                } label: {
                    Image(systemName: "plus")
                }

                Menu {
                    Toggle("Use Sections", isOn: $useSections)
                    if useSections {
                        Divider()
                        Button(slotsCollapsed ? "Expand Time Slots" : "Collapse Time Slots") {
                            slotsCollapsed.toggle()
                        }
                        Button(goalsCollapsed ? "Expand Personal Goals" : "Collapse Personal Goals") {
                            goalsCollapsed.toggle()
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .sheet(isPresented: $showAddSlot) {
            NJAddTimeSlotSheet { title, category, startDate, endDate, notes in
                let now = DBNoteRepository.nowMs()
                let row = NJTimeSlotRecord(
                    timeSlotID: UUID().uuidString.lowercased(),
                    ownerScope: "ME",
                    title: cleanedTitle(title, category: category),
                    category: category.rawValue.lowercased(),
                    startAtMs: ms(startDate),
                    endAtMs: max(ms(endDate), ms(startDate) + 15 * 60 * 1000),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
                store.notes.upsertTimeSlot(row)
                store.sync.schedulePush(debounceMs: 0)
                reload()
            }
        }
        .sheet(isPresented: $showAddGoal) {
            NJAddPersonalGoalSheet { title, focus, keyword, weeklyTarget in
                let now = DBNoteRepository.nowMs()
                let row = NJPersonalGoalRecord(
                    goalID: UUID().uuidString.lowercased(),
                    ownerScope: "ME",
                    title: title.trimmingCharacters(in: .whitespacesAndNewlines),
                    focus: focus.rawValue.lowercased(),
                    keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines),
                    weeklyTarget: Int64(max(1, weeklyTarget)),
                    status: "active",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
                store.notes.upsertPersonalGoal(row)
                store.sync.schedulePush(debounceMs: 0)
                reload()
            }
        }
        .sheet(item: $editingSlot) { slot in
            NJEditTimeSlotSheet(slot: slot, initialCategory: categoryFromString(slot.category)) { title, category, startDate, endDate, notes in
                let now = DBNoteRepository.nowMs()
                let updated = NJTimeSlotRecord(
                    timeSlotID: slot.timeSlotID,
                    ownerScope: slot.ownerScope,
                    title: cleanedTitle(title, category: category),
                    category: category.rawValue.lowercased(),
                    startAtMs: ms(startDate),
                    endAtMs: max(ms(endDate), ms(startDate) + 15 * 60 * 1000),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    createdAtMs: slot.createdAtMs,
                    updatedAtMs: now,
                    deleted: 0
                )
                store.notes.upsertTimeSlot(updated)
                store.sync.schedulePush(debounceMs: 0)
                reload()
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        slots = store.notes.listTimeSlots(ownerScope: "ME")
        goals = store.notes.listPersonalGoals(ownerScope: "ME")
    }

    private func timeSlotsView() -> some View {
        List {
            if useSections {
                Section {
                    if slotsCollapsed {
                        Text(slotsSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        if sortedSlots.isEmpty {
                            Text("No time slots yet. Add piano or exercise sessions.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sortedSlots) { slot in
                                Button {
                                    editingSlot = slot
                                } label: {
                                    VStack(alignment: .leading, spacing: 6) {
                                        HStack(spacing: 8) {
                                            Image(systemName: categoryFromString(slot.category).icon)
                                                .foregroundStyle(.secondary)
                                            Text(slot.title)
                                                .font(.headline)
                                            Spacer(minLength: 0)
                                            Text(categoryFromString(slot.category).rawValue)
                                                .font(.caption)
                                                .padding(.horizontal, 8)
                                                .padding(.vertical, 4)
                                                .background(Color(UIColor.secondarySystemBackground))
                                                .clipShape(Capsule())
                                        }
                                        Text("\(dateTime(msToDate(slot.startAtMs))) - \(timeOnly(msToDate(slot.endAtMs)))")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        if !slot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                            Text("Comment: \(slot.notes)")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .padding(.vertical, 4)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)
                            }
                            .onDelete(perform: deleteSlots)
                        }
                    }
                } header: {
                    sectionHeader(title: "Time Slots", summary: slotsSummary, collapsed: $slotsCollapsed)
                }
            } else {
                if sortedSlots.isEmpty {
                    Text("No time slots yet. Add piano or exercise sessions.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedSlots) { slot in
                        Button {
                            editingSlot = slot
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Image(systemName: categoryFromString(slot.category).icon)
                                        .foregroundStyle(.secondary)
                                    Text(slot.title)
                                        .font(.headline)
                                    Spacer(minLength: 0)
                                    Text(categoryFromString(slot.category).rawValue)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color(UIColor.secondarySystemBackground))
                                        .clipShape(Capsule())
                                }
                                Text("\(dateTime(msToDate(slot.startAtMs))) - \(timeOnly(msToDate(slot.endAtMs)))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if !slot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("Comment: \(slot.notes)")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                    .onDelete(perform: deleteSlots)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var sortedSlots: [NJTimeSlotRecord] {
        slots.sorted { a, b in
            if a.startAtMs == b.startAtMs { return a.timeSlotID > b.timeSlotID }
            return a.startAtMs < b.startAtMs
        }
    }

    private func deleteSlots(at offsets: IndexSet) {
        let ids: [String] = offsets.compactMap { idx in
            guard idx >= 0, idx < sortedSlots.count else { return nil }
            return sortedSlots[idx].timeSlotID
        }
        guard !ids.isEmpty else { return }
        let now = DBNoteRepository.nowMs()
        for id in ids {
            store.notes.deleteTimeSlot(timeSlotID: id, nowMs: now)
        }
        store.sync.schedulePush(debounceMs: 0)
        reload()
    }

    private func goalsView() -> some View {
        List {
            if useSections {
                Section {
                    if goalsCollapsed {
                        Text(goalsSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    } else {
                        if sortedGoals.isEmpty {
                            Text("No goals yet.")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(sortedGoals) { goal in
                                let progress = progressThisWeek(for: goal)
                                let target = max(1, Int(goal.weeklyTarget))
                                let ratio = min(1.0, max(0.0, Double(progress) / Double(target)))
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        Text(goal.title)
                                            .font(.headline)
                                        Spacer(minLength: 0)
                                        Text("\(progress)/\(target)")
                                            .font(.caption)
                                            .foregroundStyle(progress >= target ? .green : .secondary)
                                    }
                                    ProgressView(value: ratio)
                                    Text(goalSubtitle(goal))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 4)
                            }
                            .onDelete(perform: deleteGoals)
                        }
                    }
                } header: {
                    sectionHeader(title: "Personal Goals", summary: goalsSummary, collapsed: $goalsCollapsed)
                } footer: {
                    Text("Progress is based on time slots in the current week.")
                }
            } else {
                if sortedGoals.isEmpty {
                    Text("No goals yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedGoals) { goal in
                        let progress = progressThisWeek(for: goal)
                        let target = max(1, Int(goal.weeklyTarget))
                        let ratio = min(1.0, max(0.0, Double(progress) / Double(target)))
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(goal.title)
                                    .font(.headline)
                                Spacer(minLength: 0)
                                Text("\(progress)/\(target)")
                                    .font(.caption)
                                    .foregroundStyle(progress >= target ? .green : .secondary)
                            }
                            ProgressView(value: ratio)
                            Text(goalSubtitle(goal))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete(perform: deleteGoals)
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private var sortedGoals: [NJPersonalGoalRecord] {
        goals.sorted { a, b in
            if a.updatedAtMs == b.updatedAtMs { return a.goalID > b.goalID }
            return a.updatedAtMs > b.updatedAtMs
        }
    }

    private func deleteGoals(at offsets: IndexSet) {
        let ids: [String] = offsets.compactMap { idx in
            guard idx >= 0, idx < sortedGoals.count else { return nil }
            return sortedGoals[idx].goalID
        }
        guard !ids.isEmpty else { return }
        let now = DBNoteRepository.nowMs()
        for id in ids {
            store.notes.deletePersonalGoal(goalID: id, nowMs: now)
        }
        store.sync.schedulePush(debounceMs: 0)
        reload()
    }

    private var slotsSummary: String {
        let count = sortedSlots.count
        guard let next = sortedSlots.first(where: { $0.startAtMs >= ms(Date()) }) else {
            return "\(count) slot\(count == 1 ? "" : "s")"
        }
        return "\(count) slot\(count == 1 ? "" : "s") • next \(dateTime(msToDate(next.startAtMs)))"
    }

    private var goalsSummary: String {
        let goalCount = sortedGoals.count
        let progress = sortedGoals.reduce(0) { $0 + progressThisWeek(for: $1) }
        let target = sortedGoals.reduce(0) { $0 + max(1, Int($1.weeklyTarget)) }
        return "\(goalCount) goal\(goalCount == 1 ? "" : "s") • \(progress)/\(max(1, target)) this week"
    }

    private func sectionHeader(title: String, summary: String, collapsed: Binding<Bool>) -> some View {
        Button {
            collapsed.wrappedValue.toggle()
        } label: {
            HStack(spacing: 8) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                if collapsed.wrappedValue {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Image(systemName: collapsed.wrappedValue ? "chevron.right" : "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func progressThisWeek(for goal: NJPersonalGoalRecord, now: Date = Date()) -> Int {
        let cal = Calendar.current
        let start = cal.dateInterval(of: .weekOfYear, for: now)?.start ?? cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        let startMs = ms(start)
        let endMs = ms(end)
        return slots.filter { slot in
            guard slot.startAtMs >= startMs, slot.startAtMs < endMs else { return false }
            return slotMatchesGoal(slot: slot, goal: goal)
        }.count
    }

    private func slotMatchesGoal(slot: NJTimeSlotRecord, goal: NJPersonalGoalRecord) -> Bool {
        let haystack = "\(slot.title) \(slot.notes) \(slot.category)".lowercased()
        switch goal.focus.lowercased() {
        case "piano":
            return slot.category.lowercased() == "piano" || haystack.contains("piano")
        case "exercise":
            if slot.category.lowercased() == "exercise" { return true }
            let hints = ["exercise", "workout", "run", "walk", "swim", "gym", "cycle", "bike", "tennis"]
            return hints.contains { haystack.contains($0) }
        default:
            let key = goal.keyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !key.isEmpty else { return false }
            return haystack.contains(key)
        }
    }

    private func goalSubtitle(_ goal: NJPersonalGoalRecord) -> String {
        switch goal.focus.lowercased() {
        case "piano":
            return "Focus: Piano"
        case "exercise":
            return "Focus: Exercise"
        default:
            let clean = goal.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty ? "Focus: Keyword" : "Focus: Keyword (\(clean))"
        }
    }

    private func categoryFromString(_ raw: String) -> NJTimeSlotCategory {
        switch raw.lowercased() {
        case "piano": return .piano
        case "exercise": return .exercise
        default: return .personal
        }
    }

    private func cleanedTitle(_ title: String, category: NJTimeSlotCategory) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? category.rawValue : clean
    }

    private func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000.0)
    }

    private func msToDate(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }

    private func dateTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct NJAddTimeSlotSheet: View {
    let onSave: (String, NJTimeSlotCategory, Date, Date, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var category: NJTimeSlotCategory = .piano
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date().addingTimeInterval(45 * 60)
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(NJTimeSlotCategory.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Comment", text: $notes)
                }
            }
            .navigationTitle("Add Time Slot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, category, startDate, endDate, notes)
                        dismiss()
                    }
                }
            }
            .onChange(of: startDate) { _, next in
                if endDate <= next {
                    endDate = next.addingTimeInterval(30 * 60)
                }
            }
        }
    }
}

private struct NJEditTimeSlotSheet: View {
    let slot: NJTimeSlotRecord
    let initialCategory: NJTimeSlotCategory
    let onSave: (String, NJTimeSlotCategory, Date, Date, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: NJTimeSlotCategory
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String

    init(
        slot: NJTimeSlotRecord,
        initialCategory: NJTimeSlotCategory,
        onSave: @escaping (String, NJTimeSlotCategory, Date, Date, String) -> Void
    ) {
        self.slot = slot
        self.initialCategory = initialCategory
        self.onSave = onSave
        _title = State(initialValue: slot.title)
        _category = State(initialValue: initialCategory)
        _startDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(slot.startAtMs) / 1000.0))
        _endDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(slot.endAtMs) / 1000.0))
        _notes = State(initialValue: slot.notes)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        ForEach(NJTimeSlotCategory.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Comment", text: $notes)
                }
            }
            .navigationTitle("Edit Time Slot")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, category, startDate, endDate, notes)
                        dismiss()
                    }
                }
            }
            .onChange(of: startDate) { _, next in
                if endDate <= next {
                    endDate = next.addingTimeInterval(30 * 60)
                }
            }
        }
    }
}

private struct NJAddPersonalGoalSheet: View {
    let onSave: (String, NJGoalFocus, String, Int) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String = ""
    @State private var focus: NJGoalFocus = .piano
    @State private var keyword: String = ""
    @State private var weeklyTarget: Int = 5

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("Title", text: $title)
                    Picker("Focus", selection: $focus) {
                        ForEach(NJGoalFocus.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    if focus == .keyword {
                        TextField("Keyword", text: $keyword)
                    }
                    Stepper("Weekly target: \(weeklyTarget)", value: $weeklyTarget, in: 1...14)
                }
            }
            .navigationTitle("Add Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title, focus, keyword, weeklyTarget)
                        dismiss()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
