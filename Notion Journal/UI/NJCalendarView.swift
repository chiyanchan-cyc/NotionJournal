import SwiftUI
import Photos
import UIKit
import EventKit
#if canImport(HealthKit)
import HealthKit
#endif

private enum NJCalendarDisplayMode: String, CaseIterable, Identifiable {
    case month = "Monthly"
    case week = "Weekly"

    var id: String { rawValue }
}

private enum NJCalendarContentMode: String, CaseIterable, Identifiable {
    case memory
    case health

    var id: String { rawValue }
    var icon: String { self == .memory ? "photo" : "heart.text.square" }
}

private struct NJCalendarHealthDay {
    struct ActivityStat {
        var distanceKm: Double = 0
        var durationMin: Double = 0
    }

    var sleepHours: Double = 0
    var workoutDistanceKm: Double = 0
    var workoutDurationMin: Double = 0
    var workoutCount: Int = 0
    var workoutByActivity: [String: ActivityStat] = [:]
    var medDoseCount: Int = 0
    var bpSystolicSum: Double = 0
    var bpSystolicCount: Int = 0
    var bpDiastolicSum: Double = 0
    var bpDiastolicCount: Int = 0

    var avgSystolic: Double? {
        guard bpSystolicCount > 0 else { return nil }
        return bpSystolicSum / Double(bpSystolicCount)
    }

    var avgDiastolic: Double? {
        guard bpDiastolicCount > 0 else { return nil }
        return bpDiastolicSum / Double(bpDiastolicCount)
    }

    var paceMinPerKm: Double? {
        guard workoutDistanceKm > 0 else { return nil }
        return workoutDurationMin / workoutDistanceKm
    }
}

struct NJCalendarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var displayMode: NJCalendarDisplayMode = .month
    @State private var contentMode: NJCalendarContentMode = .memory
    @State private var focusedDate: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var itemsByDate: [String: NJCalendarItem] = [:]
    @State private var healthByDate: [String: NJCalendarHealthDay] = [:]
    @State private var plannedByDate: [String: [NJPlannedExercise]] = [:]
    @State private var eventsByDate: [String: [EKEvent]] = [:]
    @State private var calendarAuth: EKAuthorizationStatus = .notDetermined
    @State private var showPhotoPicker = false
    @State private var photoPickerDate: Date = Date()
    @State private var showPlanExerciseSheet = false
    @State private var planExerciseDate: Date = Date()
    @State private var showPlanningNoteSheet = false
    @State private var planningNoteKind: String = "daily"
    @State private var planningNoteTargetKey: String = ""
    @State private var planningNoteTitle: String = ""
    @State private var planningNoteText: String = ""

    private let calendar = Calendar.current
    private let eventStore = EKEventStore()

    init() {
        #if os(iOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        _displayMode = State(initialValue: idiom == .phone ? .week : .month)
        #endif
    }

    var body: some View {
        VStack(spacing: 0) {
            headerSection()
            if displayMode == .month {
                calendarGrid()
            } else {
                calendarGrid()
            }
        }
        .navigationTitle("Calendar")
        .toolbar { toolbar() }
        .onAppear { reloadAll() }
        .onChange(of: displayMode) { _, _ in reloadAll() }
        .onChange(of: contentMode) { _, _ in reloadAll() }
        .onChange(of: focusedDate) { _, _ in reloadItemsForVisibleRange() }
        .onChange(of: selectedDate) { _, _ in syncSelectedItem() }
        .sheet(isPresented: $showPhotoPicker) {
            NJDatePhotoPicker(date: photoPickerDate) { image, localID in
                savePhoto(image: image, localIdentifier: localID)
            }
        }
        .sheet(isPresented: $showPlanExerciseSheet) {
            NJPlanExerciseSheet(date: planExerciseDate) { sport, distKm, durMin, notes in
                savePlannedExercise(date: planExerciseDate, sport: sport, distanceKm: distKm, durationMin: durMin, notes: notes)
            }
        }
        .sheet(isPresented: $showPlanningNoteSheet) {
            NJPlanningNoteSheet(
                title: planningNoteTitle,
                text: $planningNoteText,
                onSave: { text in
                    savePlanningNote(kind: planningNoteKind, targetKey: planningNoteTargetKey, text: text)
                }
            )
        }
    }

    @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if isPastDate(selectedDate) {
                Button("Add Photo") {
                    photoPickerDate = selectedDate
                    showPhotoPicker = true
                }
            }
        }
    }

    private func headerBar() -> some View {
        HStack {
            if displayMode == .month {
                HStack(spacing: 10) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                    Text(headerTitle())
                        .font(.headline)
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                }
            } else {
                Text(headerTitle())
                    .font(.headline)
            }
            Spacer(minLength: 0)
            contentModePicker()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func headerSection() -> some View {
        VStack(spacing: 0) {
            headerBar()
            modePicker()
            if displayMode == .month {
                weekdayHeader()
            }
        }
        .background(Color(UIColor.systemBackground))
        .zIndex(1)
    }

    private func modePicker() -> some View {
        Picker("View", selection: $displayMode) {
            ForEach(NJCalendarDisplayMode.allCases) { mode in
                Text(mode.rawValue).tag(mode)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func contentModePicker() -> some View {
        HStack(spacing: 10) {
            ForEach(NJCalendarContentMode.allCases) { mode in
                let isOn = contentMode == mode
                Button {
                    contentMode = mode
                } label: {
                    Image(systemName: mode.icon)
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(isOn ? Color.accentColor.opacity(0.2) : Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func weekdayHeader() -> some View {
        let symbols = weekdaySymbols()
        return HStack(spacing: 0) {
            ForEach(symbols, id: \.self) { s in
                Text(s)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 6)
    }

    private func calendarGrid() -> some View {
        let dates = gridDates()
        switch displayMode {
        case .month:
            let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)
            return AnyView(
                GeometryReader { geo in
                    let rows = max(1, dates.count / 7)
                    let spacing: CGFloat = 6
                    let totalSpacing = spacing * CGFloat(max(0, rows - 1))
                    let rowHeight = max(56, (geo.size.height - totalSpacing) / CGFloat(rows))
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: spacing) {
                            ForEach(dates, id: \.self) { date in
                                dayCell(date, isWeekly: false, monthHeight: rowHeight)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                        .frame(minHeight: geo.size.height, alignment: .top)
                    }
                }
            )
        case .week:
            return AnyView(
                GeometryReader { geo in
                    let columns = 2
                    let rowHeight = max(140, (geo.size.height - 12 * 5) / 4)
                    let cells: [Date?] = [nil] + dates
                    ScrollView {
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 12) {
                            ForEach(Array(cells.enumerated()), id: \.offset) { _, date in
                                if let date {
                                    dayCell(date, isWeekly: true)
                                        .frame(height: rowHeight)
                                } else {
                                    weeklyHeaderBlock()
                                        .frame(height: rowHeight)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                    }
                }
            )
        }
    }

    private func dayCell(_ date: Date, isWeekly: Bool, monthHeight: CGFloat = 96) -> some View {
        let key = dateKey(date)
        let item = itemsByDate[key]
        let events = eventsByDate[key] ?? []
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isInMonth = calendar.isDate(date, equalTo: focusedDate, toGranularity: .month)
        let textColor: Color = isInMonth ? .primary : .secondary
        let photo = selectedPhotoImage(item)
        let dayLabel = isWeekly ? "\(weekdayName(date)), \(dayNumber(date))" : dayNumber(date)
        let photoLayer = Group {
            if let photo {
                if isWeekly {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()
                        .overlay(Color.black.opacity(0.15))
                } else {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .overlay(Color.black.opacity(0.05))
                }
            } else {
                Color(UIColor.secondarySystemBackground)
            }
        }

        return ZStack {
            if isWeekly {
                weekBlockLines()
                    .zIndex(1)
            }

            VStack(alignment: .leading, spacing: 6) {
                if isWeekly {
                    HStack(alignment: .center, spacing: 8) {
                        Text(dayLabel)
                            .font(.headline)
                            .foregroundStyle(textColor)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.22))
                            .cornerRadius(4)
                        Spacer(minLength: 0)
                        if contentMode == .memory, let localID = photoLocalIdentifier(for: item) {
                            Button {
                                openPhotoWindow(localIdentifier: localID)
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.plain)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 4)
                            .background(Color(UIColor.systemBackground).opacity(0.9))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                        }
                    }
                } else {
                    Text(dayLabel)
                        .font(.caption2)
                        .foregroundStyle(textColor)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(Color(UIColor.systemBackground).opacity(0.9))
                        .cornerRadius(2)
                }

                if !events.isEmpty {
                    if contentMode == .memory {
                        ForEach(events.prefix(isWeekly ? 6 : 2), id: \.eventIdentifier) { ev in
                            Text(ev.title)
                                .font(isWeekly ? .callout : .caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        healthSummaryView(date: date, isWeekly: isWeekly)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    if contentMode == .memory {
                        Text(" ")
                            .font(.caption2)
                    } else {
                        healthSummaryView(date: date, isWeekly: isWeekly)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .zIndex(2)
        }
        .frame(maxWidth: .infinity, minHeight: isWeekly ? 120 : monthHeight, maxHeight: isWeekly ? .infinity : monthHeight)
        .background(contentMode == .memory ? AnyView(photoLayer) : AnyView(Color(UIColor.secondarySystemBackground)))
        .overlay(isSelected ? Color.accentColor.opacity(0.18) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(UIColor.separator).opacity(0.6), lineWidth: 1)
        )
        .overlay(alignment: .bottomTrailing) {
            if isWeekly, contentMode == .memory, isFutureDate(date) {
                Button {
                    openDayPlanningNoteEditor(for: date)
                } label: {
                    Image(systemName: hasPlanningNote(kind: "daily", targetKey: key) ? "note.text" : "note.text.badge.plus")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(6)
                        .background(Color(UIColor.systemBackground).opacity(0.92))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .padding(6)
            }
        }
        .opacity(displayMode == .month && !isInMonth ? 0.35 : 1.0)
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .simultaneousGesture(TapGesture().onEnded { selectedDate = date })
        .contextMenu {
            if contentMode == .memory {
                if displayMode == .month, isFutureDate(date) {
                    Button("Edit Day Planning Note") {
                        openDayPlanningNoteEditor(for: date)
                    }
                }
                if item?.photoThumbPath.isEmpty == false {
                    if let localID = photoLocalIdentifier(for: item) {
                        Button("Open Photo") { openPhotoWindow(localIdentifier: localID) }
                    }
                }
                if isPastDate(date) {
                    Button("Add Photo") {
                        selectedDate = date
                        photoPickerDate = date
                        showPhotoPicker = true
                    }
                    if item?.photoThumbPath.isEmpty == false {
                        Button("Remove Photo", role: .destructive) {
                            selectedDate = date
                            removePhoto()
                        }
                    }
                }
            }
            if contentMode == .health, !isPastDate(date) {
                Button("Plan Exercise") {
                    planExerciseDate = date
                    showPlanExerciseSheet = true
                }
            }
        }
    }

    private func reloadAll() {
        reloadItemsForVisibleRange()
        syncSelectedItem()
    }

    private func reloadItemsForVisibleRange() {
        store.notes.cleanupCalendarItemsOlderThan3Months()
        let dates = gridDates()
        guard let start = dates.first, let end = dates.last else { return }
        let startKey = dateKey(start)
        let endKey = dateKey(end)
        let items = store.notes.listCalendarItems(startKey: startKey, endKey: endKey)
        itemsByDate = Dictionary(uniqueKeysWithValues: items.map { ($0.dateKey, $0) })
        for item in items where !item.photoAttachmentID.isEmpty {
            ensureThumbCached(attachmentID: item.photoAttachmentID, dateKey: item.dateKey)
        }
        loadEventsForVisibleRange(start: start, end: end)
        reloadHealthForVisibleRange(start: start, end: end)
        reloadPlansForVisibleRange(start: start, end: end)
    }

    private func syncSelectedItem() {
        _ = dateKey(selectedDate)
    }

    private func savePhoto(image: UIImage, localIdentifier: String) {
        let key = dateKey(selectedDate)
        let now = DBNoteRepository.nowMs()
        var item = itemsByDate[key] ?? NJCalendarItem.empty(dateKey: key, nowMs: now)
        let attachmentID = item.photoAttachmentID.isEmpty ? UUID().uuidString.lowercased() : item.photoAttachmentID

        let priorPath = item.photoThumbPath
        if !priorPath.isEmpty, priorPath != NJAttachmentCache.fileURL(for: attachmentID)?.path {
            try? FileManager.default.removeItem(atPath: priorPath)
        }

        if let saved = NJAttachmentCache.saveThumbnail(image: image, attachmentID: attachmentID, width: 400) {
            item.photoAttachmentID = attachmentID
            item.photoLocalID = localIdentifier
            item.photoThumbPath = saved.url.path
            item.updatedAtMs = now
            item.deleted = 0

            store.notes.upsertCalendarItem(item)
            itemsByDate[key] = item

            let record = NJAttachmentRecord(
                attachmentID: attachmentID,
                blockID: "calendar:\(key)",
                noteID: nil,
                kind: .photo,
                thumbPath: saved.url.path,
                fullPhotoRef: localIdentifier,
                displayW: Int(saved.size.width),
                displayH: Int(saved.size.height),
                createdAtMs: item.createdAtMs,
                updatedAtMs: now,
                deleted: 0
            )
            store.notes.upsertAttachment(record, nowMs: now)
        }
    }

    private func openPhotoWindow(localIdentifier: String) {
        let id = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        openWindow(id: "photo-viewer", value: id)
    }

    private func photoLocalIdentifier(for item: NJCalendarItem?) -> String? {
        guard let item, !item.photoThumbPath.isEmpty else { return nil }
        let direct = item.photoLocalID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        if !item.photoAttachmentID.isEmpty,
           let att = store.notes.attachmentByID(item.photoAttachmentID) {
            let ref = att.fullPhotoRef.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ref.isEmpty { return ref }
        }
        return nil
    }

    private func removePhoto() {
        let key = dateKey(selectedDate)
        let now = DBNoteRepository.nowMs()
        guard var item = itemsByDate[key] else { return }

        if !item.photoThumbPath.isEmpty {
            try? FileManager.default.removeItem(atPath: item.photoThumbPath)
        }

        if !item.photoAttachmentID.isEmpty {
            store.notes.markAttachmentDeleted(attachmentID: item.photoAttachmentID, nowMs: now)
        }

        item.photoAttachmentID = ""
        item.photoLocalID = ""
        item.photoThumbPath = ""
        item.updatedAtMs = now

        if item.title.isEmpty {
            store.notes.deleteCalendarItem(dateKey: key, nowMs: now)
            itemsByDate[key] = nil
        } else {
            store.notes.upsertCalendarItem(item)
            itemsByDate[key] = item
        }
    }

    private func savePlannedExercise(date: Date, sport: String, distanceKm: Double, durationMin: Double, notes: String) {
        let key = dateKey(date)
        let now = DBNoteRepository.nowMs()
        let plan = NJPlannedExercise(
            planID: UUID().uuidString.lowercased(),
            dateKey: key,
            sport: sport,
            targetDistanceKm: distanceKm,
            targetDurationMin: durationMin,
            notes: notes,
            createdAtMs: now,
            updatedAtMs: now,
            deleted: 0
        )
        store.notes.upsertPlannedExercise(plan)
        reloadPlansForVisibleRange(start: gridDates().first ?? date, end: gridDates().last ?? date)
    }

    private func selectedPhotoImage(_ item: NJCalendarItem?) -> UIImage? {
        guard let item else { return nil }
        if !item.photoThumbPath.isEmpty {
            return NJAttachmentCache.imageFromPath(item.photoThumbPath)
        }
        if !item.photoAttachmentID.isEmpty {
            if let att = store.notes.attachmentByID(item.photoAttachmentID),
               !att.thumbPath.isEmpty,
               FileManager.default.fileExists(atPath: att.thumbPath) {
                return NJAttachmentCache.imageFromPath(att.thumbPath)
            }
            if let url = NJAttachmentCache.fileURL(for: item.photoAttachmentID),
               FileManager.default.fileExists(atPath: url.path) {
                return NJAttachmentCache.imageFromPath(url.path)
            }
        }
        return nil
    }

    private func step(_ delta: Int) {
        let component: Calendar.Component = (displayMode == .month) ? .month : .weekOfYear
        if let next = calendar.date(byAdding: component, value: delta, to: focusedDate) {
            focusedDate = next
            if !isDate(selectedDate, within: next) {
                selectedDate = next
            }
        }
    }

    private func isDate(_ date: Date, within focus: Date) -> Bool {
        switch displayMode {
        case .month:
            return calendar.isDate(date, equalTo: focus, toGranularity: .month)
        case .week:
            return calendar.isDate(date, equalTo: focus, toGranularity: .weekOfYear)
        }
    }

    private func headerTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        if displayMode == .month {
            formatter.dateFormat = "MMMM yyyy"
            return formatter.string(from: focusedDate)
        }

        let interval = calendar.dateInterval(of: .weekOfYear, for: focusedDate)
        guard let start = interval?.start, let end = interval?.end else {
            formatter.dateFormat = "MMM d"
            return formatter.string(from: focusedDate)
        }

        let endDate = calendar.date(byAdding: .day, value: -1, to: end) ?? end
        formatter.dateFormat = "MMM d"
        return "\(formatter.string(from: start)) - \(formatter.string(from: endDate))"
    }

    private func weekdaySymbols() -> [String] {
        var symbols = calendar.shortStandaloneWeekdaySymbols
        let startIndex = calendar.firstWeekday - 1
        if startIndex > 0 {
            let head = symbols[..<startIndex]
            let tail = symbols[startIndex...]
            symbols = Array(tail + head)
        }
        return symbols
    }

    private func gridDates() -> [Date] {
        switch displayMode {
        case .month:
            return monthGridDates(for: focusedDate)
        case .week:
            return weekDates(for: focusedDate)
        }
    }

    private func monthGridDates(for date: Date) -> [Date] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else { return [] }
        let firstOfMonth = monthInterval.start
        let daysInMonth = calendar.range(of: .day, in: .month, for: date)?.count ?? 30

        let weekday = calendar.component(.weekday, from: firstOfMonth)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        var dates: [Date] = []
        dates.reserveCapacity(42)

        for offset in stride(from: -leading, to: 0, by: 1) {
            if let d = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                dates.append(d)
            }
        }

        for offset in 0..<daysInMonth {
            if let d = calendar.date(byAdding: .day, value: offset, to: firstOfMonth) {
                dates.append(d)
            }
        }

        while dates.count % 7 != 0 {
            if let last = dates.last,
               let next = calendar.date(byAdding: .day, value: 1, to: last) {
                dates.append(next)
            } else {
                break
            }
        }

        return dates
    }

    private func weekDates(for date: Date) -> [Date] {
        guard let weekInterval = calendar.dateInterval(of: .weekOfYear, for: date) else { return [] }
        var dates: [Date] = []
        for offset in 0..<7 {
            if let d = calendar.date(byAdding: .day, value: offset, to: weekInterval.start) {
                dates.append(d)
            }
        }
        return dates
    }

    private func dayNumber(_ date: Date) -> String {
        let day = calendar.component(.day, from: date)
        return String(day)
    }

    private func weekdayName(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "EEEE"
        return formatter.string(from: date)
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    private func dateKey(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private func reloadPlansForVisibleRange(start: Date, end: Date) {
        let startKey = dateKey(start)
        let endKey = dateKey(end)
        let plans = store.notes.listPlannedExercises(startKey: startKey, endKey: endKey)
        plannedByDate = Dictionary(grouping: plans, by: { $0.dateKey })
    }

    private func reloadHealthForVisibleRange(start: Date, end: Date) {
        let startMs = Int64(calendar.startOfDay(for: start).timeIntervalSince1970 * 1000.0)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000.0)
        let sql = """
        SELECT type, start_ms, end_ms, value_num, value_str, metadata_json
        FROM health_samples
        WHERE start_ms >= \(startMs)
          AND start_ms < \(endMs)
          AND type IN ('sleep', 'workout', 'blood_pressure_systolic', 'blood_pressure_diastolic', 'medication_dose', 'medication_record')
        ORDER BY start_ms ASC;
        """
        let rows = store.db.queryRows(sql)
        var out: [String: NJCalendarHealthDay] = [:]

        for r in rows {
            let type = r["type"] ?? ""
            let sMs = Int64(r["start_ms"] ?? "") ?? 0
            let eMs = Int64(r["end_ms"] ?? "") ?? sMs
            let value = Double(r["value_num"] ?? "") ?? 0
            let d = Date(timeIntervalSince1970: TimeInterval(sMs) / 1000.0)
            let key = dateKey(d)
            var day = out[key] ?? NJCalendarHealthDay()

            switch type {
            case "sleep":
                day.sleepHours += Double(max(0, eMs - sMs)) / 1000.0 / 3600.0
            case "workout":
                day.workoutCount += 1
                day.workoutDurationMin += value / 60.0
                let md = parseJSONDict(r["metadata_json"] ?? "")
                let distM = (md["distance_m"] as? NSNumber)?.doubleValue ?? 0
                let distKm = distM / 1000.0
                day.workoutDistanceKm += distKm
                let activity = normalizedActivityName(valueStr: r["value_str"] ?? "", metadata: md)
                var stat = day.workoutByActivity[activity] ?? NJCalendarHealthDay.ActivityStat()
                stat.distanceKm += distKm
                stat.durationMin += value / 60.0
                day.workoutByActivity[activity] = stat
            case "blood_pressure_systolic":
                day.bpSystolicSum += value
                day.bpSystolicCount += 1
            case "blood_pressure_diastolic":
                day.bpDiastolicSum += value
                day.bpDiastolicCount += 1
            case "medication_dose", "medication_record":
                day.medDoseCount += 1
            default:
                break
            }
            out[key] = day
        }
        healthByDate = out
    }

    private func parseJSONDict(_ s: String) -> [String: Any] {
        if s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [:] }
        guard let d = s.data(using: .utf8) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d, options: [])) as? [String: Any] ?? [:]
    }

    private func prettyActivityName(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "Workout" }
        return s.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func normalizedActivityName(valueStr: String, metadata: [String: Any]) -> String {
        if let n = metadata["activity_type"] as? NSNumber,
           let mapped = activityNameFromRaw(Int(n.int64Value)) {
            return mapped
        }
        if let raw = rawActivityFromValueStr(valueStr),
           let mapped = activityNameFromRaw(raw) {
            return mapped
        }
        let cleaned = prettyActivityName(valueStr)
        if cleaned.lowercased().contains("rawvalue") { return "Workout" }
        return cleaned
    }

    private func rawActivityFromValueStr(_ valueStr: String) -> Int? {
        let digits = valueStr.filter { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        return Int(digits)
    }

    private func activityNameFromRaw(_ raw: Int) -> String? {
        #if canImport(HealthKit)
        guard let t = HKWorkoutActivityType(rawValue: UInt(raw)) else { return nil }
        switch t {
        case .running: return "Running"
        case .cycling: return "Cycling"
        case .tennis: return "Tennis"
        case .walking: return "Walking"
        case .swimming: return "Swimming"
        case .traditionalStrengthTraining, .functionalStrengthTraining: return "Strength"
        default: return nil
        }
        #else
        return nil
        #endif
    }

    private func isDistanceActivity(_ name: String) -> Bool {
        let n = name.lowercased()
        return n.contains("run") || n.contains("jog") || n.contains("cycl") || n.contains("bike")
    }

    private func activityIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cycl") || n.contains("bike") { return "bicycle" }
        if n.contains("run") || n.contains("jog") { return "figure.run" }
        if n.contains("walk") { return "figure.walk" }
        if n.contains("swim") { return "figure.pool.swim" }
        if n.contains("tennis") { return "sportscourt" }
        if n.contains("strength") || n.contains("gym") { return "dumbbell" }
        return "figure.mixed.cardio"
    }

    @ViewBuilder
    private func healthSummaryView(date: Date, isWeekly: Bool) -> some View {
        let key = dateKey(date)
        let day = healthByDate[key] ?? NJCalendarHealthDay()
        let plans = plannedByDate[key] ?? []
        let medTaken = day.medDoseCount > 0
        let activityRows = day.workoutByActivity
            .map { (name: $0.key, stat: $0.value) }
            .sorted { a, b in
                if a.stat.durationMin == b.stat.durationMin {
                    return a.name < b.name
                }
                return a.stat.durationMin > b.stat.durationMin
            }
        let distanceRows = activityRows.filter { isDistanceActivity($0.name) }
        let distanceKmTotal = distanceRows.reduce(0.0) { $0 + $1.stat.distanceKm }
        let distanceDurationMinTotal = distanceRows.reduce(0.0) { $0 + $1.stat.durationMin }
        let weeklyPace: Double? = distanceKmTotal > 0 ? (distanceDurationMinTotal / distanceKmTotal) : nil

        if isWeekly {
            VStack(alignment: .leading, spacing: 2) {
                if !plans.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(plans.prefix(3), id: \.planID) { p in
                            HStack(spacing: 3) {
                                Image(systemName: "calendar.badge.plus")
                                Text("\(p.sport) \(fmtNum(p.targetDistanceKm))km / \(fmtNum(p.targetDurationMin))m")
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        }
                    }
                }
                Spacer(minLength: 2)
                if !activityRows.isEmpty {
                    let primaryIcon = activityRows.count == 1 ? activityIcon(activityRows[0].name) : "figure.mixed.cardio"
                    HStack(spacing: 6) {
                        Image(systemName: primaryIcon)
                        if distanceKmTotal > 0 {
                            Text("\(fmtNum(distanceKmTotal))km")
                        }
                        Image(systemName: "timer")
                        Text("\(fmtNum(day.workoutDurationMin))m")
                        if let pace = weeklyPace {
                            Image(systemName: "speedometer")
                            Text("\(fmtNum(pace))")
                        }
                    }
                    .font(.system(size: 9))
                    .lineLimit(1)
                }
                HStack(spacing: 4) {
                    Image(systemName: "bed.double")
                    Text("Sleep \(fmtNum(day.sleepHours)) h")
                }
                .font(.system(size: 9))
                HStack(spacing: 4) {
                    Image(systemName: "pills.fill")
                    Circle()
                        .fill(medTaken ? Color.green : Color.red)
                        .frame(width: 7, height: 7)
                    Text(medTaken ? "Medication logged" : "Medication missing")
                }
                .font(.system(size: 9))
                if let s = day.avgSystolic, let d = day.avgDiastolic {
                    HStack(spacing: 4) {
                        Image(systemName: "heart.text.square")
                        Text("BP \(Int(s))/\(Int(d))")
                    }
                    .font(.system(size: 9))
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    if let first = plans.first {
                        HStack(spacing: 3) {
                            Image(systemName: "calendar.badge.plus")
                            Text("\(first.sport) \(fmtNum(first.targetDistanceKm))km / \(fmtNum(first.targetDurationMin))m")
                        }
                        .font(.system(size: 8))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                VStack(alignment: .leading, spacing: 1) {
                    if !activityRows.isEmpty {
                        let displayRows = Array(activityRows.prefix(4))
                        ForEach(displayRows, id: \.name) { row in
                            HStack(spacing: 3) {
                                Image(systemName: activityIcon(row.name))
                                if isDistanceActivity(row.name), row.stat.distanceKm > 0 {
                                    Text("\(fmtNum(row.stat.distanceKm))km")
                                } else {
                                    Text("\(fmtNum(row.stat.durationMin))m")
                                }
                            }
                            .font(.system(size: 8))
                            .lineLimit(1)
                        }
                    }
                    HStack(spacing: 3) {
                        Image(systemName: "pills.fill")
                        Circle()
                            .fill(medTaken ? Color.green : Color.red)
                            .frame(width: 6, height: 6)
                    }
                    .font(.system(size: 8))
                    if day.sleepHours > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "bed.double")
                            Text("\(fmtNum(day.sleepHours)) h")
                        }
                        .font(.system(size: 8))
                    }
                    if let s = day.avgSystolic, let d = day.avgDiastolic {
                        HStack(spacing: 3) {
                            Image(systemName: "heart.text.square")
                            Text("\(Int(s))/\(Int(d))")
                        }
                        .font(.system(size: 8))
                    }
                }
            }
        }
    }

    private func fmtNum(_ v: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    private func isPastDate(_ date: Date) -> Bool {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return target < today
    }

    private func isFutureDate(_ date: Date) -> Bool {
        let today = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: date)
        return target > today
    }

    private func ensureThumbCached(attachmentID: String, dateKey: String) {
        guard let url = NJAttachmentCache.fileURL(for: attachmentID) else { return }
        if FileManager.default.fileExists(atPath: url.path) { return }
        if let att = store.notes.attachmentByID(attachmentID),
           !att.thumbPath.isEmpty,
           FileManager.default.fileExists(atPath: att.thumbPath) {
            DispatchQueue.main.async {
                guard var item = itemsByDate[dateKey] else { return }
                if item.photoThumbPath.isEmpty {
                    item.photoThumbPath = att.thumbPath
                    itemsByDate[dateKey] = item
                }
            }
            return
        }
        NJAttachmentCloudFetcher.fetchThumbIfNeeded(attachmentID: attachmentID) { _ in
            let path = url.path
            DispatchQueue.main.async {
                guard var item = itemsByDate[dateKey] else { return }
                if item.photoThumbPath.isEmpty && FileManager.default.fileExists(atPath: path) {
                    item.photoThumbPath = path
                    itemsByDate[dateKey] = item
                }
            }
        }
    }

    private func weeklyHeaderBlock() -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                miniMonthView()
                Spacer(minLength: 0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("WEEK OF")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button { step(-1) } label: { Image(systemName: "chevron.left") }
                        .buttonStyle(.plain)
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                    Text(weekRangeTitle())
                        .font(.callout)
                        .fontWeight(.semibold)
                    Button { step(1) } label: { Image(systemName: "chevron.right") }
                        .buttonStyle(.plain)
                        .frame(minWidth: 36, minHeight: 36)
                        .contentShape(Rectangle())
                    if contentMode == .memory {
                        Button {
                            openWeekPlanningNoteEditor(for: focusedDate)
                        } label: {
                            let targetKey = weekPlanningTargetKey(for: focusedDate)
                            Image(systemName: hasPlanningNote(kind: "weekly", targetKey: targetKey) ? "note.text" : "note.text.badge.plus")
                                .font(.subheadline)
                                .frame(width: 30, height: 30)
                                .background(Color(UIColor.systemBackground).opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canOpenWeekPlanningNote(for: focusedDate))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color(UIColor.separator).opacity(0.6), lineWidth: 1)
        )
    }

    private func weekRangeTitle() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        let interval = calendar.dateInterval(of: .weekOfYear, for: focusedDate)
        guard let start = interval?.start,
              let end = interval?.end,
              let endDate = calendar.date(byAdding: .day, value: -1, to: end) else {
            return formatter.string(from: focusedDate)
        }
        return "\(formatter.string(from: start))  –  \(formatter.string(from: endDate))"
    }

    private func weekPlanningTargetKey(for date: Date) -> String {
        DBNoteRepository.sundayWeekStartKey(for: date)
    }

    private func hasPlanningNote(kind: String, targetKey: String) -> Bool {
        guard !targetKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        let text = store.notes.planningNote(kind: kind, targetKey: targetKey)?.note ?? ""
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func openDayPlanningNoteEditor(for date: Date) {
        guard isFutureDate(date) else { return }
        let key = dateKey(date)
        planningNoteKind = "daily"
        planningNoteTargetKey = key
        planningNoteTitle = "Day Planning Note (\(formattedDate(date)))"
        planningNoteText = store.notes.planningNote(kind: "daily", targetKey: key)?.note ?? ""
        showPlanningNoteSheet = true
    }

    private func openWeekPlanningNoteEditor(for date: Date) {
        guard canOpenWeekPlanningNote(for: date) else { return }
        let key = weekPlanningTargetKey(for: date)
        planningNoteKind = "weekly"
        planningNoteTargetKey = key
        planningNoteTitle = "Week Planning Note (\(weekRangeTitle()))"
        planningNoteText = store.notes.planningNote(kind: "weekly", targetKey: key)?.note ?? ""
        showPlanningNoteSheet = true
    }

    private func savePlanningNote(kind: String, targetKey: String, text: String) {
        let now = DBNoteRepository.nowMs()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            store.notes.deletePlanningNote(kind: kind, targetKey: targetKey, nowMs: now)
            return
        }
        store.notes.upsertPlanningNote(kind: kind, targetKey: targetKey, note: trimmed, nowMs: now)
    }

    private func canOpenWeekPlanningNote(for date: Date) -> Bool {
        let today = calendar.startOfDay(for: Date())
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        return week.end > today
    }

    private func miniMonthView() -> some View {
        let dates = monthGridDates(for: focusedDate)
        let columns = Array(repeating: GridItem(.flexible(), spacing: 2), count: 7)
        let monthFormatter = DateFormatter()
        monthFormatter.locale = Locale.current
        monthFormatter.dateFormat = "MMMM yyyy"
        let monthTitle = monthFormatter.string(from: focusedDate)
        return VStack(alignment: .leading, spacing: 4) {
            Text(monthTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)

            HStack(spacing: 2) {
                ForEach(weekdaySymbols(), id: \.self) { s in
                    Text(String(s.prefix(1)))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 2) {
                ForEach(dates, id: \.self) { date in
                    let isInMonth = calendar.isDate(date, equalTo: focusedDate, toGranularity: .month)
                    let isInWeek = calendar.isDate(date, equalTo: focusedDate, toGranularity: .weekOfYear)
                    Text(dayNumber(date))
                        .font(.caption2)
                        .frame(maxWidth: .infinity, minHeight: 14)
                        .padding(.vertical, 1)
                        .background(isInWeek ? Color.accentColor.opacity(0.2) : Color.clear)
                        .foregroundStyle(isInMonth ? .primary : .secondary)
                        .cornerRadius(2)
                }
            }
        }
    }

    private func weekBlockLines() -> some View {
        GeometryReader { geo in
            let lineCount = 6
            let spacing = geo.size.height / CGFloat(lineCount + 1)
            Path { path in
                for i in 1...lineCount {
                    let y = CGFloat(i) * spacing
                    path.move(to: CGPoint(x: 8, y: y))
                    path.addLine(to: CGPoint(x: geo.size.width - 8, y: y))
                }
            }
            .stroke(Color(UIColor.separator).opacity(0.35), lineWidth: 1)
        }
    }

    private func loadEventsForVisibleRange(start: Date, end: Date) {
        requestCalendarAccessIfNeeded { granted in
            guard granted else {
                eventsByDate = [:]
                return
            }

            let cal = eventStore.calendars(for: .event).first { $0.title == "Calendar" }
            guard let cal else {
                eventsByDate = [:]
                return
            }

            let startDay = calendar.startOfDay(for: start)
            let endDay = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
            let predicate = eventStore.predicateForEvents(withStart: startDay, end: endDay, calendars: [cal])
            let events = eventStore.events(matching: predicate)

            var grouped: [String: [EKEvent]] = [:]
            let visibleStart = startDay
            let visibleEnd = endDay
            for ev in events {
                let eventStartDay = calendar.startOfDay(for: ev.startDate)
                let eventEndExclusive = calendar.startOfDay(for: ev.endDate)
                let clampedStart = max(visibleStart, eventStartDay)
                let clampedEndExclusive = min(visibleEnd, eventEndExclusive)

                if clampedStart == clampedEndExclusive {
                    let key = dateKey(clampedStart)
                    grouped[key, default: []].append(ev)
                    continue
                }

                var day = clampedStart
                while day < clampedEndExclusive {
                    let key = dateKey(day)
                    grouped[key, default: []].append(ev)
                    guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
                    day = next
                }
            }
            for (k, v) in grouped {
                grouped[k] = v.sorted { $0.startDate < $1.startDate }
            }
            eventsByDate = grouped
        }
    }

    private func requestCalendarAccessIfNeeded(_ completion: @escaping (Bool) -> Void) {
        let status = EKEventStore.authorizationStatus(for: .event)
        calendarAuth = status
        #if os(iOS)
        if #available(iOS 17.0, *) {
            if status == .authorized || status == .fullAccess {
                completion(true)
                return
            }
        } else {
            if status == .authorized {
                completion(true)
                return
            }
        }
        #else
        if status == .authorized {
            completion(true)
            return
        }
        #endif
        if status == .denied || status == .restricted {
            completion(false)
            return
        }
        #if os(iOS)
        if #available(iOS 17.0, *) {
            eventStore.requestFullAccessToEvents { granted, _ in
                DispatchQueue.main.async {
                    calendarAuth = granted ? .fullAccess : .denied
                    completion(granted)
                }
            }
        } else {
            eventStore.requestAccess(to: .event) { granted, _ in
                DispatchQueue.main.async {
                    calendarAuth = granted ? .authorized : .denied
                    completion(granted)
                }
            }
        }
        #else
        completion(false)
        #endif
    }
}

private struct NJDatePhotoPicker: View {
    let date: Date
    let onSelect: (UIImage, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var assets: [PHAsset] = []
    @State private var status: PHAuthorizationStatus = .notDetermined

    private let grid = [GridItem(.adaptive(minimum: 90), spacing: 8)]
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                if status == .denied || status == .restricted {
                    Text("Photos access is required to pick a memory photo.")
                        .multilineTextAlignment(.center)
                        .padding()
                } else if assets.isEmpty {
                    Text("No photos for this date.")
                        .foregroundStyle(.secondary)
                        .padding(.top, 24)
                } else {
                    ScrollView {
                        LazyVGrid(columns: grid, spacing: 8) {
                            ForEach(assets, id: \.localIdentifier) { asset in
                                NJPhotoAssetThumb(asset: asset) {
                                    select(asset)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 12)
                    }
                }
            }
            .navigationTitle(title())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await loadAssets() }
        }
    }

    private func title() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }

    private func loadAssets() async {
        let nextStatus = await requestAuthorization()
        status = nextStatus
        guard nextStatus == .authorized || nextStatus == .limited else { return }

        let start = calendar.startOfDay(for: date)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return }

        let options = PHFetchOptions()
        options.predicate = NSPredicate(format: "creationDate >= %@ AND creationDate < %@", start as NSDate, end as NSDate)
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]

        let result = PHAsset.fetchAssets(with: .image, options: options)
        var out: [PHAsset] = []
        out.reserveCapacity(result.count)
        result.enumerateObjects { asset, _, _ in
            out.append(asset)
        }
        assets = out
    }

    private func requestAuthorization() async -> PHAuthorizationStatus {
        let current = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        if current != .notDetermined { return current }
        return await withCheckedContinuation { cont in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                cont.resume(returning: status)
            }
        }
    }

    private func select(_ asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .none

        PHImageManager.default().requestImageDataAndOrientation(for: asset, options: options) { data, _, _, _ in
            guard let data, let image = UIImage(data: data) else { return }
            onSelect(image, asset.localIdentifier)
            dismiss()
        }
    }
}

private struct NJPhotoAssetThumb: View {
    let asset: PHAsset
    let onTap: () -> Void

    @State private var image: UIImage? = nil

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Color(UIColor.secondarySystemBackground)
                }
            }
            .frame(width: 90, height: 90)
            .clipped()
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .onAppear { loadThumb() }
    }

    private func loadThumb() {
        guard image == nil else { return }
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast

        PHImageManager.default().requestImage(
            for: asset,
            targetSize: CGSize(width: 120, height: 120),
            contentMode: .aspectFill,
            options: options
        ) { img, _ in
            image = img
        }
    }
}

private struct NJPlanningNoteSheet: View {
    let title: String
    @Binding var text: String
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ZStack(alignment: .topLeading) {
                TextEditor(text: $text)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)

                if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Write planning note...")
                        .foregroundStyle(.secondary)
                        .padding(.top, 14)
                        .padding(.leading, 14)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        onSave(text)
                        dismiss()
                    }
                }
            }
        }
    }
}

private struct NJPlanExerciseSheet: View {
    let date: Date
    let onSave: (String, Double, Double, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var sport: String = "Running"
    @State private var distance: String = ""
    @State private var duration: String = ""
    @State private var notes: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Exercise") {
                    Picker("Sport", selection: $sport) {
                        Text("Running").tag("Running")
                        Text("Cycling").tag("Cycling")
                        Text("Walking").tag("Walking")
                        Text("Swimming").tag("Swimming")
                        Text("Gym").tag("Gym")
                    }
                    TextField("Distance (km)", text: $distance)
                        .keyboardType(.decimalPad)
                    TextField("Duration (min)", text: $duration)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes)
                }
            }
            .navigationTitle(title())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let dist = Double(distance) ?? 0
                        let dur = Double(duration) ?? 0
                        onSave(sport, dist, dur, notes)
                        dismiss()
                    }
                }
            }
        }
    }

    private func title() -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        return "Plan \(f.string(from: date))"
    }
}
