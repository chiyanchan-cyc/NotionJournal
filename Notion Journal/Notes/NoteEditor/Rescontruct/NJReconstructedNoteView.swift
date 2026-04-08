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
import WeatherKit

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")

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
        if loadForecastFromLastLoggedLocationIfAvailable() {
            statusText = "Using last logged location"
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
        if loadForecastFromLastLoggedLocationIfAvailable() {
            statusText = "Refreshing weather..."
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
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        for attempt in 1...3 {
            do {
                let next = try await fetchWeatherKitForecast(for: location)
                forecastByDayKey = next
                statusText = next.isEmpty ? "Weather unavailable" : "Weather updated"
                return
            } catch {
                let formatted = Self.formatWeatherError(error)
                print("NJ_WEEKLY_WEATHER weatherkit_failed attempt=\(attempt) \(formatted)")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }
        if forecastByDayKey.isEmpty {
            statusText = "Weather unavailable"
        }
    }

    private func fetchWeatherKitForecast(for location: CLLocation) async throws -> [String: NJWeeklyWeatherDay] {
        let weather = try await WeatherService.shared.weather(for: location)
        var next: [String: NJWeeklyWeatherDay] = [:]
        for day in weather.dailyForecast {
            let key = Self.dayKey(for: day.date, calendar: Calendar.current)
            next[key] = NJWeeklyWeatherDay(
                symbolName: day.symbolName,
                minC: day.lowTemperature.converted(to: .celsius).value,
                maxC: day.highTemperature.converted(to: .celsius).value
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

}

struct NJReconstructedNoteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    
    let spec: NJReconstructedSpec
    
    @StateObject private var persistence: NJReconstructedNotePersistence
    
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
        .onDisappear { forceCommitFocusedIfAny() }
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
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    
    private func list() -> some View {
        List {
            ForEach(persistence.blocks, id: \.id) { b in
                row(b)
            }
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
            persistence.markDirty(id)
            persistence.scheduleCommit(id)
        }
        
        return NJBlockHostView(
                index: rowIndex,
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
                    persistence.hydrateProton(id)
                    h.focus()
                },
                onCtrlReturn: {
                    persistence.forceEndEditingAndCommitNow(id)
                },
                onDelete: { },
                onHydrateProton: { persistence.hydrateProton(id) },
                onCommitProton: {
                    persistence.markDirty(id)
                    persistence.scheduleCommit(id)
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
        .id("\(id.uuidString)-\(collapsedBinding.wrappedValue ? "c" : "e")")
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(persistence.rowBackgroundColor(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear {
            persistence.hydrateProton(id)
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
        .onChange(of: collapsedBinding.wrappedValue) { _, v in
            guard !v else { return }
            DispatchQueue.main.async {
                persistence.hydrateProton(id)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                persistence.hydrateProton(id)
            }
        }
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
        persistence.reload(makeHandle: {
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
            return h
        })
    }
    
    private func onLoadOnce() {
        if loaded { return }
        if !store.sync.initialPullCompleted { return }
        loaded = true
        persistence.configure(store: store)
        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
        persistence.updateSpec(spec)
        persistence.reload(makeHandle: {
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
            return h
        })
    }
    
    private func forceCommitFocusedIfAny() {
        if let id = persistence.focusedBlockID {
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
                    arr[i].attr = v
                    persistence.blocks = arr
                    persistence.markDirty(id)
                    persistence.scheduleCommit(id)
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

            Button("") { fire { $0.toggleBullet() } }
                .keyboardShortcut("7", modifiers: .command)

            Button("") { fire { $0.toggleNumber() } }
                .keyboardShortcut("8", modifiers: .command)

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
        f(h)
        h.snapshot()
    }

}
