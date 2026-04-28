import SwiftUI
import Foundation
import UIKit
#if canImport(HealthKit)
import HealthKit
#endif

private struct NJTimeTimelineBlock: Identifiable, Hashable {
    let id: String
    let record: NJTimeSlotRecord
    let source: Source

    enum Source: Hashable {
        case local
        case health
    }
}

private enum NJTimePresentationMode: String, CaseIterable, Identifiable {
    case timeline = "Timeline"
    case list = "List"

    var id: String { rawValue }
}

struct NJTimeModuleView: View {
    @EnvironmentObject var store: AppStore

    @State private var showAddSlot = false
    @State private var editingSlot: NJTimeSlotRecord? = nil
    @State private var slots: [NJTimeSlotRecord] = []
    @State private var healthExerciseSlots: [NJTimeSlotRecord] = []
    @State private var weekStart: Date = NJTimeModuleView.defaultWeekStart(for: Date())
    @State private var presentationMode: NJTimePresentationMode = .timeline
    @State private var timelineZoom: CGFloat = 1.0
    @GestureState private var pinchScale: CGFloat = 1.0
    @State private var addSlotTitle: String = ""
    @State private var addSlotCategory: NJTimeSlotCategory = .personal
    @State private var addSlotStartDate: Date = Date()
    @State private var addSlotEndDate: Date = Date().addingTimeInterval(45 * 60)
    @State private var addSlotNotes: String = ""

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }()

    private let timelineStartHour = 6
    private let timelineEndHour = 24
    private let baseHourRowHeight: CGFloat = 64
    private let baseDayColumnWidth: CGFloat = 126
    private let baseHourLabelWidth: CGFloat = 54

    var body: some View {
        VStack(spacing: 0) {
            weekHeader()
            Divider()
            if weekBlocks.isEmpty {
                emptyWeekView()
            } else {
                if presentationMode == .timeline {
                    weeklyTimelineView()
                } else {
                    weeklyListView()
                }
            }
        }
        .navigationTitle("Time")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    store.runTimeModuleInboxIngestIfNeeded()
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            bottomBar()
        }
        .sheet(isPresented: $showAddSlot) {
            NJAddTimeSlotSheet(
                initialWeekStart: weekStart,
                initialTitle: addSlotTitle,
                initialCategory: addSlotCategory,
                initialStartDate: addSlotStartDate,
                initialEndDate: addSlotEndDate,
                initialNotes: addSlotNotes
            ) { title, category, startDate, endDate, notes in
                saveTimeSlot(title: title, category: category, startDate: startDate, endDate: endDate, notes: notes)
            }
        }
        .sheet(item: $editingSlot) { slot in
            NJEditTimeSlotSheet(
                slot: slot,
                initialWeekStart: Self.defaultWeekStart(for: msToDate(slot.startAtMs)),
                initialCategory: categoryFromString(slot.category),
                onDelete: {
                    let now = DBNoteRepository.nowMs()
                    store.notes.deleteTimeSlot(timeSlotID: slot.timeSlotID, nowMs: now)
                    store.publishTimeSlotWidgetSnapshot()
                    store.syncTimeSlotOverrunNotifications()
                    store.sync.schedulePush(debounceMs: 0)
                    reload()
                }
            ) { title, category, startDate, endDate, notes in
                let now = DBNoteRepository.nowMs()
                let updated = NJTimeSlotRecord(
                    timeSlotID: slot.timeSlotID,
                    ownerScope: slot.ownerScope,
                    title: cleanedTitle(title, category: category),
                    category: categoryStorageValue(category),
                    startAtMs: ms(startDate),
                    endAtMs: max(ms(endDate), ms(startDate) + 15 * 60 * 1000),
                    notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                    createdAtMs: slot.createdAtMs,
                    updatedAtMs: now,
                    deleted: 0
                )
                store.notes.upsertTimeSlot(updated)
                store.publishTimeSlotWidgetSnapshot()
                store.syncTimeSlotOverrunNotifications()
                store.sync.schedulePush(debounceMs: 0)
                reload()
            }
        }
        .onAppear {
            store.runTimeModuleInboxIngestIfNeeded()
            reload()
        }
        .onReceive(NotificationCenter.default.publisher(for: .njTimeSlotInboxDidChange)) { _ in
            store.runTimeModuleInboxIngestIfNeeded()
            reload()
        }
    }

    private var weekDays: [Date] {
        (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: weekStart) }
    }

    private var weekEndExclusive: Date {
        calendar.date(byAdding: .day, value: 7, to: weekStart) ?? weekStart
    }

    private var timelineHeight: CGFloat {
        CGFloat(timelineEndHour - timelineStartHour) * hourRowHeight
    }

    private var effectiveTimelineZoom: CGFloat {
        clampedTimelineZoom(timelineZoom * pinchScale)
    }

    private var hourRowHeight: CGFloat {
        baseHourRowHeight * effectiveTimelineZoom
    }

    private var dayColumnWidth: CGFloat {
        baseDayColumnWidth * effectiveTimelineZoom
    }

    private var hourLabelWidth: CGFloat {
        baseHourLabelWidth * max(0.9, sqrt(effectiveTimelineZoom))
    }

    private var weekBlocks: [NJTimeTimelineBlock] {
        let localBlocks = slots.map { NJTimeTimelineBlock(id: $0.timeSlotID, record: $0, source: .local) }
        let healthBlocks = healthExerciseSlots.map { NJTimeTimelineBlock(id: $0.timeSlotID, record: $0, source: .health) }
        return (localBlocks + healthBlocks)
            .filter { block in
                let start = msToDate(block.record.startAtMs)
                return start >= weekStart && start < weekEndExclusive
            }
            .sorted {
                if $0.record.startAtMs == $1.record.startAtMs { return $0.id > $1.id }
                return $0.record.startAtMs < $1.record.startAtMs
            }
    }

    private func reload() {
        slots = store.notes.listTimeSlots(ownerScope: "ME").filter { $0.deleted == 0 }
        healthExerciseSlots = loadHealthExerciseSlots()
    }

    private func weekHeader() -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    if let prev = calendar.date(byAdding: .day, value: -7, to: weekStart) {
                        weekStart = prev
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrentWeek(weekStart) ? "Current Week" : "Week of \(weekShortDate(weekStart))")
                        .font(.headline)
                    Text("\(weekTitle()) • Weekly timesheet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Today") {
                    weekStart = Self.defaultWeekStart(for: Date())
                }
                .font(.subheadline.weight(.semibold))

                Button {
                    if let next = calendar.date(byAdding: .day, value: 7, to: weekStart) {
                        weekStart = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
            }

            Picker("View", selection: $presentationMode) {
                ForEach(NJTimePresentationMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func weeklyTimelineView() -> some View {
        ScrollView([.horizontal, .vertical]) {
            HStack(spacing: 0) {
                hourAxisView()
                ForEach(weekDays, id: \.self) { day in
                    dayTimelineColumn(day)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 18)
        }
        .gesture(
            MagnificationGesture()
                .updating($pinchScale) { value, state, _ in
                    state = value
                }
                .onEnded { value in
                    timelineZoom = clampedTimelineZoom(timelineZoom * value)
                }
        )
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func weeklyListView() -> some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(weekBlocks) { block in
                    weekListRow(block)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func hourAxisView() -> some View {
        VStack(spacing: 0) {
            Color.clear
                .frame(width: hourLabelWidth, height: 40)
            ForEach(timelineStartHour..<timelineEndHour, id: \.self) { hour in
                ZStack(alignment: .topTrailing) {
                    Rectangle()
                        .fill(Color(UIColor.separator).opacity(0.25))
                        .frame(height: 1)
                        .offset(y: 0)
                    Text(hourLabel(hour))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.top, -8)
                        .padding(.trailing, 6)
                }
                .frame(width: hourLabelWidth, height: hourRowHeight, alignment: .topTrailing)
            }
        }
    }

    private func dayTimelineColumn(_ day: Date) -> some View {
        let daySlots = blocks(for: day)
        let laneMap = laneIndexMap(for: daySlots)
        let laneCount = max(1, laneMap.values.max().map { $0 + 1 } ?? 1)
        let laneWidth = max(28, (dayColumnWidth - 10) / CGFloat(laneCount))

        return VStack(spacing: 0) {
            VStack(spacing: 2) {
                Text(dayHeaderLabel(day))
                    .font(.caption.weight(.semibold))
                Text(dayNumberLabel(day))
                    .font(.headline)
                    .foregroundStyle(calendar.isDateInToday(day) ? .blue : .primary)
            }
            .frame(width: dayColumnWidth, height: 40)
            .background(calendar.isDateInToday(day) ? Color.blue.opacity(0.08) : Color(UIColor.secondarySystemBackground))

            ZStack(alignment: .topLeading) {
                dayGridBackground()
                ForEach(daySlots) { slot in
                    let lane = laneMap[slot.id] ?? 0
                    timeBlockView(slot)
                        .frame(width: laneWidth - 6, height: blockHeight(for: slot.record), alignment: .topLeading)
                        .offset(
                            x: 5 + CGFloat(lane) * laneWidth,
                            y: blockOffsetY(for: slot.record)
                        )
                        .onTapGesture(count: 2) {
                            guard slot.source == .local else { return }
                            editingSlot = slot.record
                        }
                }
            }
            .frame(width: dayColumnWidth, height: timelineHeight)
            .overlay(
                Rectangle()
                    .stroke(Color(UIColor.separator).opacity(0.4), lineWidth: 1)
            )
        }
    }

    private func dayGridBackground() -> some View {
        VStack(spacing: 0) {
            ForEach(timelineStartHour..<timelineEndHour, id: \.self) { _ in
                Rectangle()
                    .stroke(Color(UIColor.separator).opacity(0.22), lineWidth: 0.5)
                    .frame(height: hourRowHeight)
            }
        }
    }

    private func timeBlockView(_ slot: NJTimeTimelineBlock) -> some View {
        let category = categoryFromString(slot.record.category)
        let tint = categoryColor(category)

        return VStack(alignment: .leading, spacing: 4) {
            Text(slot.record.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.rawValue : slot.record.title)
                .font(.caption.weight(.semibold))
                .lineLimit(2)
            Text("\(timeOnly(msToDate(slot.record.startAtMs))) - \(timeOnly(msToDate(slot.record.endAtMs)))")
                .font(.caption2)
                .lineLimit(1)
                .opacity(0.9)
            if !slot.record.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(slot.record.notes)
                    .font(.caption2)
                    .lineLimit(2)
                    .opacity(0.95)
            } else if slot.source == .health {
                Text("Health")
                    .font(.caption2)
                    .lineLimit(1)
                    .opacity(0.95)
            }
        }
        .foregroundStyle(.white)
        .padding(6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(tint.opacity(0.7), lineWidth: 1)
        )
    }

    private func weekListRow(_ block: NJTimeTimelineBlock) -> some View {
        let slot = block.record
        let category = categoryFromString(slot.category)
        let tint = categoryColor(category)

        return Button {
            guard block.source == .local else { return }
            editingSlot = slot
        } label: {
            HStack(alignment: .top, spacing: 12) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tint)
                    .frame(width: 8, height: 54)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(slot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? category.rawValue : slot.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer(minLength: 8)
                        Text(dayHeaderLabel(msToDate(slot.startAtMs)))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text("\(dayNumberLabel(msToDate(slot.startAtMs))) • \(timeOnly(msToDate(slot.startAtMs))) - \(timeOnly(msToDate(slot.endAtMs)))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        Text(category.rawValue)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(tint)
                        if block.source == .health {
                            Text("Health")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if !slot.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(slot.notes)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(UIColor.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func emptyWeekView() -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("No time blocks this week")
                    .font(.title3.weight(.semibold))
                Text("The weekly timesheet shows only the current week from Sunday to Saturday. Add a block in app or sync one from watch.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 10) {
                    ForEach(weekDays, id: \.self) { day in
                        VStack(spacing: 6) {
                            Text(dayHeaderLabel(day))
                                .font(.caption.weight(.semibold))
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(UIColor.secondarySystemBackground))
                                .frame(width: 44, height: 64)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }

                Text("Use Timeline for the calendar layout or List for chronological rows.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    private func bottomBar() -> some View {
        HStack {
            Spacer()
            Button {
                prepareManualAddSlot(category: .personal)
                showAddSlot = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.accentColor))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func blocks(for day: Date) -> [NJTimeTimelineBlock] {
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return weekBlocks.filter { slot in
            let date = msToDate(slot.record.startAtMs)
            return date >= start && date < end
        }
    }

    private func laneIndexMap(for daySlots: [NJTimeTimelineBlock]) -> [String: Int] {
        var result: [String: Int] = [:]
        var laneEndMs: [Int64] = []

        for slot in daySlots.sorted(by: { $0.record.startAtMs < $1.record.startAtMs }) {
            var assignedLane = 0
            var foundLane = false
            for idx in laneEndMs.indices {
                if slot.record.startAtMs >= laneEndMs[idx] {
                    assignedLane = idx
                    laneEndMs[idx] = slot.record.endAtMs
                    foundLane = true
                    break
                }
            }
            if !foundLane {
                assignedLane = laneEndMs.count
                laneEndMs.append(slot.record.endAtMs)
            }
            result[slot.id] = assignedLane
        }
        return result
    }

    private func blockOffsetY(for slot: NJTimeSlotRecord) -> CGFloat {
        let date = msToDate(slot.startAtMs)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let relativeHours = max(0.0, Double(hour - timelineStartHour) + (Double(minute) / 60.0))
        return CGFloat(relativeHours) * hourRowHeight
    }

    private func blockHeight(for slot: NJTimeSlotRecord) -> CGFloat {
        let minutes = max(15.0, Double(slot.endAtMs - slot.startAtMs) / 60000.0)
        return max(34, CGFloat(minutes / 60.0) * hourRowHeight - 2)
    }

    private func clampedTimelineZoom(_ value: CGFloat) -> CGFloat {
        min(max(value, 0.7), 2.0)
    }

    private func categoryFromString(_ raw: String) -> NJTimeSlotCategory {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "piano":
            return .piano
        case "exercise":
            return .exercise
        case "programming":
            return .programming
        case "video editing", "video_editing", "video-editing":
            return .videoEditing
        default:
            return .personal
        }
    }

    private func categoryStorageValue(_ category: NJTimeSlotCategory) -> String {
        switch category {
        case .videoEditing:
            return "video_editing"
        default:
            return category.rawValue.lowercased()
        }
    }

    private func categoryColor(_ category: NJTimeSlotCategory) -> Color {
        switch category {
        case .personal:
            return Color.blue
        case .piano:
            return Color.orange
        case .exercise:
            return Color.green
        case .programming:
            return Color.indigo
        case .videoEditing:
            return Color.pink
        }
    }

    private func loadHealthExerciseSlots() -> [NJTimeSlotRecord] {
        let sql = """
        SELECT sample_id, start_ms, end_ms, value_str, metadata_json
        FROM health_samples
        WHERE type = 'workout'
        ORDER BY start_ms ASC;
        """
        return store.db.queryRows(sql).compactMap { row in
            guard
                let sampleID = row["sample_id"], !sampleID.isEmpty,
                let startAtMs = Int64(row["start_ms"] ?? ""),
                let endAtMs = Int64(row["end_ms"] ?? "")
            else {
                return nil
            }

            let metadata = parseJSONDict(row["metadata_json"] ?? "")
            let activity = normalizedWorkoutActivityName(valueStr: row["value_str"] ?? "", metadata: metadata)
            guard shouldIncludeHealthWorkout(named: activity) else { return nil }

            let title = activity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Exercise" : activity
            return NJTimeSlotRecord(
                timeSlotID: "health-workout-\(sampleID)",
                ownerScope: "HEALTH",
                title: title,
                category: categoryStorageValue(.exercise),
                startAtMs: startAtMs,
                endAtMs: max(endAtMs, startAtMs + 15 * 60 * 1000),
                notes: "",
                createdAtMs: startAtMs,
                updatedAtMs: endAtMs,
                deleted: 0
            )
        }
    }

    private func shouldIncludeHealthWorkout(named name: String) -> Bool {
        let normalized = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return true }
        let hints = [
            "run", "running", "jog", "jogging",
            "cycle", "cycling", "bike", "biking",
            "walk", "walking", "hike", "hiking",
            "swim", "swimming", "tennis", "strength", "workout"
        ]
        return hints.contains { normalized.contains($0) }
    }

    private func parseJSONDict(_ raw: String) -> [String: Any] {
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data, options: [])) as? [String: Any] ?? [:]
    }

    private func normalizedWorkoutActivityName(valueStr: String, metadata: [String: Any]) -> String {
        if let n = metadata["activity_type"] as? NSNumber,
           let mapped = activityNameFromRaw(Int(n.int64Value)) {
            return mapped
        }
        if let raw = rawActivityFromValueStr(valueStr),
           let mapped = activityNameFromRaw(raw) {
            return mapped
        }
        let cleaned = prettyWorkoutActivityName(valueStr)
        if cleaned.lowercased().contains("rawvalue") { return "Workout" }
        return cleaned
    }

    private func prettyWorkoutActivityName(_ raw: String) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleaned.isEmpty { return "Workout" }
        return cleaned.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func rawActivityFromValueStr(_ valueStr: String) -> Int? {
        let digits = valueStr.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private func activityNameFromRaw(_ raw: Int) -> String? {
        #if canImport(HealthKit)
        guard let type = HKWorkoutActivityType(rawValue: UInt(raw)) else { return nil }
        switch type {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        case .tennis: return "Tennis"
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private func prepareManualAddSlot(category: NJTimeSlotCategory) {
        let start = Date()
        addSlotTitle = category == .personal ? "" : category.rawValue
        addSlotCategory = category
        addSlotStartDate = start
        addSlotEndDate = start.addingTimeInterval(45 * 60)
        addSlotNotes = ""
    }

    private func saveTimeSlot(title: String, category: NJTimeSlotCategory, startDate: Date, endDate: Date, notes: String) {
        let now = DBNoteRepository.nowMs()
        let row = NJTimeSlotRecord(
            timeSlotID: UUID().uuidString.lowercased(),
            ownerScope: "ME",
            title: cleanedTitle(title, category: category),
            category: categoryStorageValue(category),
            startAtMs: ms(startDate),
            endAtMs: max(ms(endDate), ms(startDate) + 15 * 60 * 1000),
            notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAtMs: now,
            updatedAtMs: now,
            deleted: 0
        )
        store.notes.upsertTimeSlot(row)
        store.publishTimeSlotWidgetSnapshot()
        store.syncTimeSlotOverrunNotifications()
        store.sync.schedulePush(debounceMs: 0)
        reload()
    }

    private func cleanedTitle(_ title: String, category: NJTimeSlotCategory) -> String {
        let clean = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return clean.isEmpty ? category.rawValue : clean
    }

    private func weekTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: end))"
    }

    private func dayHeaderLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEE"
        return formatter.string(from: date)
    }

    private func dayNumberLabel(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "d"
        return formatter.string(from: date)
    }

    private func hourLabel(_ hour: Int) -> String {
        let components = DateComponents(hour: hour)
        let date = calendar.date(from: components) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "ha"
        return formatter.string(from: date).lowercased()
    }

    private func ms(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000.0)
    }

    private func msToDate(_ ms: Int64) -> Date {
        Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
    }

    private func timeOnly(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func weekShortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func isCurrentWeek(_ date: Date) -> Bool {
        calendar.isDate(date, equalTo: Self.defaultWeekStart(for: Date()), toGranularity: .weekOfYear)
    }

    static func defaultWeekStart(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}

private struct NJAddTimeSlotSheet: View {
    let initialWeekStart: Date
    let initialTitle: String
    let initialCategory: NJTimeSlotCategory
    let initialStartDate: Date
    let initialEndDate: Date
    let initialNotes: String
    let onSave: (String, NJTimeSlotCategory, Date, Date, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: NJTimeSlotCategory
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var weekStart: Date

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }()

    init(
        initialWeekStart: Date = NJTimeModuleView.defaultWeekStart(for: Date()),
        initialTitle: String = "",
        initialCategory: NJTimeSlotCategory = .personal,
        initialStartDate: Date = Date(),
        initialEndDate: Date = Date().addingTimeInterval(45 * 60),
        initialNotes: String = "",
        onSave: @escaping (String, NJTimeSlotCategory, Date, Date, String) -> Void
    ) {
        self.initialWeekStart = initialWeekStart
        self.initialTitle = initialTitle
        self.initialCategory = initialCategory
        self.initialStartDate = initialStartDate
        self.initialEndDate = initialEndDate
        self.initialNotes = initialNotes
        self.onSave = onSave
        _title = State(initialValue: initialTitle)
        _category = State(initialValue: initialCategory)
        _startDate = State(initialValue: initialStartDate)
        _endDate = State(initialValue: initialEndDate)
        _notes = State(initialValue: initialNotes)
        _weekStart = State(initialValue: initialWeekStart)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NJWeekPickerHeader(weekStart: $weekStart)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("Time Block") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $category) {
                        ForEach(NJTimeSlotCategory.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Comment", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Add Time Block")
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
                weekStart = Self.defaultWeekStart(for: next)
            }
            .onChange(of: weekStart) { _, next in
                moveSelectionIntoWeek(next)
            }
        }
    }

    private func moveSelectionIntoWeek(_ nextWeekStart: Date) {
        let oldWeekStart = Self.defaultWeekStart(for: startDate)
        guard !calendar.isDate(oldWeekStart, equalTo: nextWeekStart, toGranularity: .day) else { return }
        let shift = nextWeekStart.timeIntervalSince(oldWeekStart)
        startDate = startDate.addingTimeInterval(shift)
        endDate = endDate.addingTimeInterval(shift)
    }

    private static func defaultWeekStart(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}

private struct NJEditTimeSlotSheet: View {
    let slot: NJTimeSlotRecord
    let initialWeekStart: Date
    let initialCategory: NJTimeSlotCategory
    let onDelete: () -> Void
    let onSave: (String, NJTimeSlotCategory, Date, Date, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: NJTimeSlotCategory
    @State private var startDate: Date
    @State private var endDate: Date
    @State private var notes: String
    @State private var weekStart: Date

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }()

    init(
        slot: NJTimeSlotRecord,
        initialWeekStart: Date,
        initialCategory: NJTimeSlotCategory,
        onDelete: @escaping () -> Void,
        onSave: @escaping (String, NJTimeSlotCategory, Date, Date, String) -> Void
    ) {
        self.slot = slot
        self.initialWeekStart = initialWeekStart
        self.initialCategory = initialCategory
        self.onDelete = onDelete
        self.onSave = onSave
        _title = State(initialValue: slot.title)
        _category = State(initialValue: initialCategory)
        _startDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(slot.startAtMs) / 1000.0))
        _endDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(slot.endAtMs) / 1000.0))
        _notes = State(initialValue: slot.notes)
        _weekStart = State(initialValue: initialWeekStart)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NJWeekPickerHeader(weekStart: $weekStart)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        .listRowBackground(Color.clear)
                }

                Section("Time Block") {
                    TextField("Title", text: $title)
                    Picker("Type", selection: $category) {
                        ForEach(NJTimeSlotCategory.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    DatePicker("Start", selection: $startDate, displayedComponents: [.date, .hourAndMinute])
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Comment", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button("Delete Time Block", role: .destructive) {
                        onDelete()
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Time Block")
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
                weekStart = Self.defaultWeekStart(for: next)
            }
            .onChange(of: weekStart) { _, next in
                moveSelectionIntoWeek(next)
            }
        }
    }

    private func moveSelectionIntoWeek(_ nextWeekStart: Date) {
        let oldWeekStart = Self.defaultWeekStart(for: startDate)
        guard !calendar.isDate(oldWeekStart, equalTo: nextWeekStart, toGranularity: .day) else { return }
        let shift = nextWeekStart.timeIntervalSince(oldWeekStart)
        startDate = startDate.addingTimeInterval(shift)
        endDate = endDate.addingTimeInterval(shift)
    }

    private static func defaultWeekStart(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}

private struct NJWeekPickerHeader: View {
    @Binding var weekStart: Date

    private let calendar: Calendar = {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal
    }()

    var body: some View {
        HStack(spacing: 10) {
            Button {
                if let prev = calendar.date(byAdding: .day, value: -7, to: weekStart) {
                    weekStart = prev
                }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)

            VStack(spacing: 2) {
                Text(isCurrentWeek ? "Current Week" : "Week of \(shortDate(weekStart))")
                    .font(.subheadline.weight(.semibold))
                Text(weekRangeTitle())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            Button {
                if let next = calendar.date(byAdding: .day, value: 7, to: weekStart) {
                    weekStart = next
                }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
        }
    }

    private var isCurrentWeek: Bool {
        calendar.isDate(weekStart, equalTo: defaultWeekStart(for: Date()), toGranularity: .weekOfYear)
    }

    private func weekRangeTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(formatter.string(from: weekStart)) - \(formatter.string(from: end))"
    }

    private func shortDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    private func defaultWeekStart(for date: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 1
        return cal.dateInterval(of: .weekOfYear, for: date)?.start ?? cal.startOfDay(for: date)
    }
}
