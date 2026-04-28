//
//  NJReconstructedNoteView.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/23.
//

import SwiftUI
import Combine
import UIKit
import Proton
import os
import PhotosUI
import CoreLocation

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")

private enum NJWeeklyWeatherServiceConfig {
    static let host = "n32vhft6q7.re.qweatherapi.com"
    static let apiKey = "3d507a30a2364b3f8befc5b9448233db"
}

private struct NJWeeklyWeatherDay {
    let symbolName: String
    let minC: Double
    let maxC: Double
}

private struct NJWeeklyWeatherBadgeModel {
    let symbolName: String
    let temperatureText: String
    let accessibilityLabel: String
}

@MainActor
private final class NJWeeklyWeatherForecastProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var forecastByDayKey: [String: NJWeeklyWeatherDay] = [:]
    @Published private(set) var authorizationStatus: CLAuthorizationStatus
    @Published private(set) var statusText: String = "Loading weather..."

    private let manager = CLLocationManager()
    private var isFetchingLocation = false
    private var lastFetchCoordinate: CLLocationCoordinate2D? = nil

    override init() {
        authorizationStatus = CLLocationManager.authorizationStatus()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func startIfNeeded() {
        authorizationStatus = manager.authorizationStatus
        let hasLoggedLocation = loadForecastFromLastLoggedLocationIfAvailable()
        if hasLoggedLocation {
            statusText = Self.shouldPreferLoggedMobileLocation ? "Using iPhone location" : "Using last logged location"
        }
        if Self.shouldPreferLoggedMobileLocation, hasLoggedLocation {
            return
        }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationIfNeeded()
        case .notDetermined:
            statusText = "Waiting for location permission"
            manager.requestWhenInUseAuthorization()
        default:
            if forecastByDayKey.isEmpty {
                statusText = "Location unavailable"
            }
            break
        }
    }

    func refresh() {
        let hasLoggedLocation = loadForecastFromLastLoggedLocationIfAvailable()
        if hasLoggedLocation {
            statusText = Self.shouldPreferLoggedMobileLocation ? "Using iPhone location" : "Refreshing weather..."
        }
        if Self.shouldPreferLoggedMobileLocation, hasLoggedLocation {
            return
        } else {
            statusText = "Loading weather..."
        }
        requestLocationIfNeeded(force: true)
    }

    func badge(for createdAtMs: Int64?) -> NJWeeklyWeatherBadgeModel? {
        guard let createdAtMs, createdAtMs > 0 else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let date = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
        let startOfBlockDay = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: Date())

        guard startOfBlockDay >= today else { return nil }

        let dayKey = Self.dayKey(for: date, calendar: calendar)
        guard let day = forecastByDayKey[dayKey] else { return nil }

        let minC = Int(day.minC.rounded())
        let maxC = Int(day.maxC.rounded())
        let rangeText = minC == maxC ? "\(minC)C" : "\(minC)-\(maxC)C"
        return NJWeeklyWeatherBadgeModel(
            symbolName: day.symbolName,
            temperatureText: rangeText,
            accessibilityLabel: rangeText
        )
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            statusText = "Updating weather..."
            requestLocationIfNeeded(force: true)
        } else if forecastByDayKey.isEmpty {
            statusText = "Location unavailable"
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isFetchingLocation = false
            return
        }
        isFetchingLocation = false
        lastFetchCoordinate = location.coordinate
        statusText = "Updating weather..."
        Task {
            await fetchForecast(for: location.coordinate)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("NJ_WEEKLY_WEATHER location_failed \(error.localizedDescription)")
        isFetchingLocation = false
        if forecastByDayKey.isEmpty {
            if loadForecastFromLastLoggedLocationIfAvailable() {
                statusText = "Using last logged location"
            } else {
                statusText = "Weather unavailable"
            }
        }
    }

    private func requestLocationIfNeeded(force: Bool = false) {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        if isFetchingLocation { return }
        if !force, !forecastByDayKey.isEmpty { return }
        isFetchingLocation = true
        statusText = "Updating weather..."
        manager.requestLocation()
    }

    private func fetchForecast(for coordinate: CLLocationCoordinate2D) async {
        for attempt in 1...3 {
            do {
                let next = try await fetchQWeatherForecast(for: coordinate)
                forecastByDayKey = next
                statusText = next.isEmpty ? "Weather unavailable" : "Weather updated"
                return
            } catch {
                let formatted = Self.formatWeatherError(error)
                print("NJ_WEEKLY_WEATHER qweather_failed attempt=\(attempt) \(formatted)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }
        if forecastByDayKey.isEmpty {
            statusText = "Weather unavailable"
        }
    }

    private func fetchQWeatherForecast(for coordinate: CLLocationCoordinate2D) async throws -> [String: NJWeeklyWeatherDay] {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = NJWeeklyWeatherServiceConfig.host
        comps.path = "/v7/weather/3d"
        comps.queryItems = [
            URLQueryItem(name: "location", value: Self.qweatherLocationString(for: coordinate)),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "unit", value: "m")
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(NJWeeklyWeatherServiceConfig.apiKey, forHTTPHeaderField: "X-QW-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTP(response)

        let payload = try JSONDecoder().decode(QWeatherDailyPayload.self, from: data)
        var next: [String: NJWeeklyWeatherDay] = [:]
        for day in payload.daily {
            next[day.fxDate] = NJWeeklyWeatherDay(
                symbolName: Self.symbolName(forQWeatherIcon: day.iconDay, textDay: day.textDay),
                minC: Double(day.tempMin) ?? 0,
                maxC: Double(day.tempMax) ?? 0
            )
        }
        return next
    }

    private func loadForecastFromLastLoggedLocationIfAvailable() -> Bool {
        guard let coordinate = latestLoggedCoordinate() else { return false }
        let shouldFetch = {
            guard let lastFetchCoordinate else { return true }
            let last = CLLocation(latitude: lastFetchCoordinate.latitude, longitude: lastFetchCoordinate.longitude)
            let next = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
            return last.distance(from: next) > 250
        }()
        guard shouldFetch else { return !forecastByDayKey.isEmpty }
        lastFetchCoordinate = coordinate
        Task {
            await fetchForecast(for: coordinate)
        }
        return true
    }

    private func latestLoggedCoordinate() -> CLLocationCoordinate2D? {
        let fm = FileManager.default
        let roots: [URL] = [
            fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal")?.appendingPathComponent("Documents", isDirectory: true),
            fm.urls(for: .documentDirectory, in: .userDomainMask).first
        ].compactMap { $0 }

        for root in roots {
            let gpsDir = root.appendingPathComponent("GPS", isDirectory: true)
            guard let enumerator = fm.enumerator(at: gpsDir, includingPropertiesForKeys: [.contentModificationDateKey], options: [.skipsHiddenFiles]) else {
                continue
            }

            var candidates: [URL] = []
            for case let url as URL in enumerator where url.pathExtension.lowercased() == "ndjson" {
                candidates.append(url)
            }

            let sorted = candidates.sorted {
                let d0 = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let d1 = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return d0 > d1
            }

            for fileURL in sorted.prefix(5) {
                if let coordinate = parseLatestCoordinate(from: fileURL) {
                    return coordinate
                }
            }
        }

        return nil
    }

    private func parseLatestCoordinate(from url: URL) -> CLLocationCoordinate2D? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        let lines = text
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .reversed()

        for line in lines {
            guard let lineData = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any],
                  let lat = json["lat"] as? Double,
                  let lon = json["lon"] as? Double else { continue }
            return CLLocationCoordinate2D(latitude: lat, longitude: lon)
        }
        return nil
    }

    private static func dayKey(for date: Date, calendar: Calendar) -> String {
        let comps = calendar.dateComponents([.year, .month, .day], from: date)
        let year = comps.year ?? 0
        let month = comps.month ?? 0
        let day = comps.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func formatWeatherError(_ error: Error) -> String {
        let nsError = error as NSError
        let desc = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.isEmpty {
            return "\(nsError.domain) \(nsError.code)"
        }
        return "\(nsError.domain) \(nsError.code): \(desc)"
    }

    private static func qweatherLocationString(for coordinate: CLLocationCoordinate2D) -> String {
        let lon = String(format: "%.2f", coordinate.longitude)
        let lat = String(format: "%.2f", coordinate.latitude)
        return "\(lon),\(lat)"
    }

    private static func validateHTTP(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200..<300).contains(http.statusCode) else {
            throw NSError(
                domain: "NJWeatherHTTP",
                code: http.statusCode,
                userInfo: [NSLocalizedDescriptionKey: HTTPURLResponse.localizedString(forStatusCode: http.statusCode)]
            )
        }
    }

    private static var shouldPreferLoggedMobileLocation: Bool {
        #if targetEnvironment(macCatalyst)
        return true
        #else
        if #available(iOS 14.0, *) {
            return ProcessInfo.processInfo.isiOSAppOnMac
        }
        return false
        #endif
    }

    private static func symbolName(forQWeatherIcon icon: String, textDay: String) -> String {
        switch icon {
        case "100", "150":
            return "sun.max.fill"
        case "101", "102", "103", "151", "152", "153":
            return "cloud.sun.fill"
        case "104", "154":
            return "cloud.fill"
        case "300", "301", "305", "306", "307", "308", "309", "310", "311", "312", "313", "314", "315", "316", "317", "318", "350", "351", "399":
            return "cloud.rain.fill"
        case "400", "401", "402", "403", "404", "405", "406", "407", "408", "409", "410", "456", "457", "499":
            return "cloud.snow.fill"
        case "500", "501", "502", "503", "504", "507", "508", "509", "510", "511", "512", "513", "514", "515":
            return "cloud.fog.fill"
        case "302", "303", "304":
            return "cloud.bolt.rain.fill"
        default:
            let lowered = textDay.lowercased()
            if lowered.contains("rain") { return "cloud.rain.fill" }
            if lowered.contains("snow") { return "cloud.snow.fill" }
            if lowered.contains("thunder") { return "cloud.bolt.rain.fill" }
            if lowered.contains("sun") || lowered.contains("clear") { return "sun.max.fill" }
            return "cloud.fill"
        }
    }

    private struct QWeatherDailyPayload: Decodable {
        struct Day: Decodable {
            let fxDate: String
            let tempMax: String
            let tempMin: String
            let iconDay: String
            let textDay: String
        }

        let daily: [Day]
    }

}

struct NJReconstructedNoteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    
    let spec: NJReconstructedSpec
    
    @StateObject private var persistence: NJReconstructedNotePersistence
    @AppStorage("nj_reconstructed_weekly_show_past_days") private var showPastDays = false
    
    @State private var loaded = false
    @State private var pendingFocusID: UUID? = nil
    @State private var pendingFocusToStart: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @StateObject private var weeklyWeather = NJWeeklyWeatherForecastProvider()
    
    init(spec: NJReconstructedSpec) {
        self.spec = spec
        _persistence = StateObject(wrappedValue: NJReconstructedNotePersistence(spec: spec))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            if persistence.hasPendingRemoteRefresh {
                remoteRefreshStrip()
            }
            list()
        }
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let h = focusedHandle() {
                NJProtonFloatingFormatBar(handle: h, pickedPhotoItem: $pickedPhotoItem)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar { toolbar() }
        .task { onLoadOnce() }
        .task {
            if spec.isWeekly {
                weeklyWeather.startIfNeeded()
            }
        }
        .onChange(of: store.sync.initialPullCompleted) { _ in
            onLoadOnce()
        }
        .onDisappear { persistence.forceEndEditingAndCommitAllDirtyNow() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistence.forceEndEditingAndCommitAllDirtyNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        // Add these lines to allow it to resize/popup on iPadOS
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
    }
    
    private func header() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(persistence.tab.isEmpty ? "" : persistence.tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    reloadNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 10)

            Text(persistence.title)
                .font(.title2)
                .fontWeight(.semibold)

            if spec.isWeekly {
                Text(weeklyWeather.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Show past days", isOn: $showPastDays)
                    .toggleStyle(.switch)
                    .font(.subheadline)
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    
    private func list() -> some View {
        List {
            ForEach(displayedBlocks, id: \.id) { b in
                row(b)
            }

            NJBlockListBottomRunwayRow()
        }
        .listStyle(.plain)
    }

    private func row(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
        let collapsedBinding = bindingCollapsed(id)
        let rowIndex = (persistence.blocks.firstIndex(where: { $0.id == id }) ?? 0) + 1
        let liveTagJSON: String? = persistence.blocks.first(where: { $0.id == id })?.tagJSON
        let weatherBadge = spec.isWeekly ? weeklyWeather.badge(for: b.createdAtMs) : nil

        let onSaveTags: (String) -> Void = { newJSON in
            if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                var arr = persistence.blocks
                arr[i].tagJSON = newJSON
                persistence.blocks = arr
            }
            persistence.markDirty(id, source: "recon.view.saveTags")
            persistence.scheduleCommit(id, source: "recon.view.saveTags")
        }
        
        return NJBlockHostView(
                index: rowIndex,
                blockID: b.blockID,
                createdAtMs: b.createdAtMs,
                domainPreview: b.domainPreview,
                onEditTags: { },
                goalPreview: b.goalPreview,
                onAddGoal: { },
                hasClipPDF: false,
                onOpenClipPDF: { },
                protonHandle: h,
                isCollapsed: collapsedBinding,
                isFocused: id == persistence.focusedBlockID,
                attr: bindingAttr(id),
                sel: bindingSel(id),
                onFocus: {
                    let prev = persistence.focusedBlockID
                    if let prev, prev != id {
                        persistence.forceEndEditingAndCommitNow(prev)
                    }
                    persistence.focusedBlockID = id
                    if !collapsedBinding.wrappedValue {
                        h.focus()
                    }
                },
                onCtrlReturn: {
                    persistence.forceEndEditingAndCommitNow(id)
                },
                onDelete: { },
                onHydrateProton: { persistence.hydrateProton(id) },
                onCommitProton: {
                    if persistence.blocks.first(where: { $0.id == id })?.isDirty == true {
                        persistence.scheduleCommit(id, source: "recon.view.onCommitProton.alreadyDirty")
                    }
                },
                onMoveToClipboard: nil,
                headerBadgeSymbolName: weatherBadge?.symbolName,
                headerBadgeText: weatherBadge?.temperatureText,
                inheritedTags: [],
                editableTags: [],
                tagJSON: liveTagJSON,
                onSaveTagJSON: onSaveTags,
                tagSuggestionsProvider: { prefix, limit in
                    store.notes.listTagSuggestions(prefix: prefix, limit: limit)
                }
            )
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(persistence.rowBackgroundColor(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear {
            if pendingFocusID == id {
                if pendingFocusToStart, let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    arr[i].sel = NSRange(location: 0, length: 0)
                    persistence.blocks = arr
                }
                persistence.focusedBlockID = id
                pendingFocusID = nil
                pendingFocusToStart = false
                h.focus()
            }
        }
    }

    private func remoteRefreshStrip() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
            Text("Remote update detected. This device will not save over it until you reload.")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button {
                reloadNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption2)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.ultraThinMaterial)
    }

    @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                forceCommitFocusedIfAny()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
        }
        
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                forceCommitFocusedIfAny()
                reloadNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private func reloadNow() {
        forceCommitFocusedIfAny()
        if spec.isWeekly {
            weeklyWeather.refresh()
        }
        persistence.reload(makeHandle: makeWiredHandle)
    }
    
    private func onLoadOnce() {
        if loaded { return }
        if !store.sync.initialPullCompleted { return }
        loaded = true
        persistence.configure(store: store)
        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
        persistence.updateSpec(spec)
        persistence.reload(makeHandle: makeWiredHandle)
    }

    private func makeWiredHandle() -> NJProtonEditorHandle {
        let h = NJProtonEditorHandle()
        h.attachmentResolver = { [weak store] id in
            store?.notes.attachmentByID(id)
        }
        h.attachmentThumbPathCleaner = { [weak store] id in
            store?.notes.clearAttachmentThumbPath(attachmentID: id, nowMs: DBNoteRepository.nowMs())
        }
        h.onOpenFullPhoto = { id in
            NJPhotoLibraryPresenter.presentFullPhoto(localIdentifier: id)
        }
        h.onUserTyped = { [weak persistence, weak h] _, _ in
            guard let persistence, let handle = h, let id = handle.ownerBlockUUID else { return }
            if handle.isRunningProgrammaticUpdate { return }
            persistence.enqueueEditorChange(id, source: "recon.view.onUserTyped.\(handle.userEditSourceHint)")
        }
        h.onSnapshot = { _, _ in
            // Passive snapshots can be emitted by layout/hydration on idle devices.
            // Only explicit user edits should enqueue a save.
        }
        return h
    }
    
    private func forceCommitFocusedIfAny() {
        if let id = persistence.focusedBlockID {
            guard let block = persistence.blocks.first(where: { $0.id == id }) else { return }
            guard block.isDirty || block.protonHandle.isEditing else { return }
            persistence.forceEndEditingAndCommitNow(id)
        }
    }
    
    private func bindingCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { v in
                persistence.setCollapsed(id: id, collapsed: v)
            }
        )
    }
    
    private func bindingAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? NSAttributedString(string: "\u{200B}") },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    if persistence.focusedBlockID != arr[i].id {
                        persistence.focusedBlockID = arr[i].id
                    }
                    if !arr[i].attr.isEqual(to: v) {
                        arr[i].attr = v
                        persistence.blocks = arr
                    }
                }
            }
        )
    }
    
    private func bindingSel(_ id: UUID) -> Binding<NSRange> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    arr[i].sel = v
                    persistence.blocks = arr
                }
            }
        )
    }

    private func focusedHandle() -> NJProtonEditorHandle? {
        guard let id = persistence.focusedBlockID else { return nil }
        return persistence.blocks.first(where: { $0.id == id })?.protonHandle
    }

    private var displayedBlocks: [NJNoteEditorContainerPersistence.BlockState] {
        guard spec.isWeekly, !showPastDays else { return persistence.blocks }
        return persistence.blocks.filter { !shouldHidePastWeeklyDayRow($0) }
    }

    private func shouldHidePastWeeklyDayRow(_ block: NJNoteEditorContainerPersistence.BlockState) -> Bool {
        guard !isWeeklyMarkerRow(block) else { return false }
        guard isDailyFocusRow(block) else { return false }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        let blockDate = Date(timeIntervalSince1970: TimeInterval(block.createdAtMs) / 1000.0)
        let startOfBlockDay = calendar.startOfDay(for: blockDate)
        let startOfToday = calendar.startOfDay(for: Date())
        return startOfBlockDay < startOfToday
    }

    private func isWeeklyMarkerRow(_ block: NJNoteEditorContainerPersistence.BlockState) -> Bool {
        let tags = decodeTagJSON(block.tagJSON)
        let normalized = Set(tags.map { $0.uppercased() })
        return normalized.contains("#YEAR") || normalized.contains("#MONTH")
    }

    private func isDailyFocusRow(_ block: NJNoteEditorContainerPersistence.BlockState) -> Bool {
        let title = firstLineText(block).lowercased()
        return title.contains("daily focus")
    }

    private func firstLineText(_ block: NJNoteEditorContainerPersistence.BlockState) -> String {
        block.attr.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .split(whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) } ?? ""
    }

    private func decodeTagJSON(_ json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let raw = try? JSONSerialization.jsonObject(with: data) as? [Any] else {
            return []
        }
        return raw.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    
}



private struct NJHiddenShortcuts: View {
    let getHandle: () -> NJProtonEditorHandle?

    var body: some View {
        Group {
            Button("") { fire { $0.toggleBold() } }
                .keyboardShortcut("b", modifiers: .command)

            Button("") { fire { $0.toggleItalic() } }
                .keyboardShortcut("i", modifiers: .command)

            Button("") { fire { $0.toggleUnderline() } }
                .keyboardShortcut("u", modifiers: .command)

            Button("") { fire { $0.toggleStrike() } }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Button("") { fire { $0.indent() } }
                .keyboardShortcut("]", modifiers: .command)

            Button("") { fire { $0.outdent() } }
                .keyboardShortcut("[", modifiers: .command)
            Button("") {
                NJShortcutLog.info("SHORTCUT TEST CMD+K HIT")
            }
            .keyboardShortcut("k", modifiers: .command)

        }
        .opacity(0.001)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    private func fire(_ f: (NJProtonEditorHandle) -> Void) {
        NJShortcutLog.info("SHORTCUT HIT (SwiftUI layer)")

        guard let h = getHandle() else {
            NJShortcutLog.error("SHORTCUT: getHandle() returned nil")
            return
        }

        NJShortcutLog.info("SHORTCUT: has handle owner=\(String(describing: h.ownerBlockUUID)) editor_nil=\(h.editor == nil) tv_nil=\(h.textView == nil)")
        h.isEditing = true
        f(h)
        h.snapshot(markUserEdit: true)
    }

}
