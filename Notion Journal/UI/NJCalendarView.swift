import SwiftUI
import Charts
import Combine
import Photos
import PhotosUI
import UIKit
import EventKit
import Proton
import UniformTypeIdentifiers
import CoreLocation
@preconcurrency import Vision
import CryptoKit
#if canImport(HealthKit)
import HealthKit
#endif

private enum NJWeatherServiceConfig {
    static let host = "n32vhft6q7.re.qweatherapi.com"
    static let apiKey = "3d507a30a2364b3f8befc5b9448233db"
}

private struct NJCalendarWeatherDay {
    let symbolName: String
    let minC: Double
    let maxC: Double
}

private struct NJCalendarWeatherBadgeModel {
    let symbolName: String
    let temperatureText: String
}

@MainActor
private final class NJCalendarWeatherForecastProvider: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var forecastByDayKey: [String: NJCalendarWeatherDay] = [:]

    private let manager = CLLocationManager()
    private var authorizationStatus: CLAuthorizationStatus
    private var isFetchingLocation = false
    private var lastFetchCoordinate: CLLocationCoordinate2D? = nil

    override init() {
        authorizationStatus = CLLocationManager.authorizationStatus()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func startIfNeeded() {
        let hasLoggedLocation = loadForecastFromLastLoggedLocationIfAvailable()
        authorizationStatus = manager.authorizationStatus
        if Self.shouldPreferLoggedMobileLocation, hasLoggedLocation {
            return
        }
        switch authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            requestLocationIfNeeded()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        default:
            break
        }
    }

    func refresh() {
        let hasLoggedLocation = loadForecastFromLastLoggedLocationIfAvailable()
        if Self.shouldPreferLoggedMobileLocation, hasLoggedLocation {
            return
        }
        requestLocationIfNeeded(force: true)
    }

    func badge(for date: Date) -> NJCalendarWeatherBadgeModel? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        guard calendar.startOfDay(for: date) >= calendar.startOfDay(for: Date()) else { return nil }
        let key = Self.dayKey(for: date, calendar: calendar)
        guard let day = forecastByDayKey[key] else { return nil }
        let minC = Int(day.minC.rounded())
        let maxC = Int(day.maxC.rounded())
        let temperatureText = minC == maxC ? "\(minC)C" : "\(minC)-\(maxC)C"
        return NJCalendarWeatherBadgeModel(symbolName: day.symbolName, temperatureText: temperatureText)
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse {
            requestLocationIfNeeded(force: true)
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isFetchingLocation = false
            return
        }
        isFetchingLocation = false
        lastFetchCoordinate = location.coordinate
        Task { await fetchForecast(for: location.coordinate) }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("NJ_CAL_WEATHER location_failed \(error.localizedDescription)")
        isFetchingLocation = false
        _ = loadForecastFromLastLoggedLocationIfAvailable()
    }

    private func requestLocationIfNeeded(force: Bool = false) {
        guard authorizationStatus == .authorizedAlways || authorizationStatus == .authorizedWhenInUse else { return }
        if isFetchingLocation { return }
        if !force, !forecastByDayKey.isEmpty { return }
        isFetchingLocation = true
        manager.requestLocation()
    }

    private func fetchForecast(for coordinate: CLLocationCoordinate2D) async {
        for attempt in 1...3 {
            do {
                let next = try await fetchQWeatherForecast(for: coordinate)
                forecastByDayKey = next
                return
            } catch {
                print("NJ_CAL_WEATHER qweather_failed attempt=\(attempt) \(Self.formatWeatherError(error))")
                if attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
                }
            }
        }
    }

    private func fetchQWeatherForecast(for coordinate: CLLocationCoordinate2D) async throws -> [String: NJCalendarWeatherDay] {
        var comps = URLComponents()
        comps.scheme = "https"
        comps.host = NJWeatherServiceConfig.host
        comps.path = "/v7/weather/3d"
        comps.queryItems = [
            URLQueryItem(name: "location", value: Self.qweatherLocationString(for: coordinate)),
            URLQueryItem(name: "lang", value: "en"),
            URLQueryItem(name: "unit", value: "m")
        ]
        guard let url = comps.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue(NJWeatherServiceConfig.apiKey, forHTTPHeaderField: "X-QW-Api-Key")
        let (data, response) = try await URLSession.shared.data(for: request)
        try Self.validateHTTP(response)

        let payload = try JSONDecoder().decode(QWeatherDailyPayload.self, from: data)
        var next: [String: NJCalendarWeatherDay] = [:]
        for day in payload.daily {
            next[day.fxDate] = NJCalendarWeatherDay(
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
        Task { await fetchForecast(for: coordinate) }
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
        let lines = text.split(whereSeparator: \.isNewline).map(String.init).reversed()
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
        return String(format: "%04d-%02d-%02d", comps.year ?? 0, comps.month ?? 0, comps.day ?? 0)
    }

    private static func formatWeatherError(_ error: Error) -> String {
        let nsError = error as NSError
        let desc = nsError.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        if desc.isEmpty { return "\(nsError.domain) \(nsError.code)" }
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

private enum NJCalendarDisplayMode: String, CaseIterable, Identifiable {
    case month = "Monthly"
    case week = "Weekly"

    var id: String { rawValue }
}

private enum NJCalendarContentMode: String, CaseIterable, Identifiable {
    case memory
    case health
    case quickLog
    case finance

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .memory: return "photo"
        case .health: return "heart.text.square"
        case .quickLog: return "clock.badge"
        case .finance: return "dollarsign.circle"
        }
    }
}

private enum NJFinanceWorkspaceMode: String, CaseIterable, Identifiable {
    case calendar = "Calendar"
    case research = "Research"
    case spending = "Spending"
    var id: String { rawValue }
}

private enum NJFinanceSpendingWindow: String, CaseIterable, Identifiable {
    case week = "Week"
    case month = "Month"
    case custom = "Date Range"

    var id: String { rawValue }
}

private struct NJFinanceIssueTab: Identifiable, Hashable {
    let premiseID: String
    let themeID: String
    let title: String
    let promptHint: String
    var id: String { premiseID }
    var sessionID: String { "issue.\(premiseID)" }
}

private struct NJFinanceComparisonBar: Identifiable {
    let metric: String
    let periodLabel: String
    let totalMinor: Int64

    var id: String { "\(metric):\(periodLabel)" }
}

private struct NJFinanceCategorySlice: Identifiable {
    let category: String
    let total: Int64

    var id: String { category }
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
    var weightKgSum: Double = 0
    var weightKgCount: Int = 0
    var bmiSum: Double = 0
    var bmiCount: Int = 0
    var heightMSum: Double = 0
    var heightMCount: Int = 0
    var bodyFatRawSum: Double = 0
    var bodyFatCount: Int = 0
    var leanMassKgSum: Double = 0
    var leanMassKgCount: Int = 0
    var waistMSum: Double = 0
    var waistMCount: Int = 0

    var avgSystolic: Double? {
        guard bpSystolicCount > 0 else { return nil }
        return bpSystolicSum / Double(bpSystolicCount)
    }

    var avgDiastolic: Double? {
        guard bpDiastolicCount > 0 else { return nil }
        return bpDiastolicSum / Double(bpDiastolicCount)
    }

    var avgWeightKg: Double? {
        guard weightKgCount > 0 else { return nil }
        return weightKgSum / Double(weightKgCount)
    }

    var avgBMI: Double? {
        guard bmiCount > 0 else { return nil }
        return bmiSum / Double(bmiCount)
    }

    var avgHeightM: Double? {
        guard heightMCount > 0 else { return nil }
        return heightMSum / Double(heightMCount)
    }

    var avgHeightCm: Double? {
        guard let m = avgHeightM else { return nil }
        return m * 100.0
    }

    var avgBodyFatFraction: Double? {
        guard bodyFatCount > 0 else { return nil }
        let raw = bodyFatRawSum / Double(bodyFatCount)
        // HealthKit bodyFatPercentage is typically stored as 0...1. Accept older/imported 0...100 too.
        return raw > 1.5 ? (raw / 100.0) : raw
    }

    var avgBodyFatPercent: Double? {
        guard let f = avgBodyFatFraction else { return nil }
        return f * 100.0
    }

    var avgLeanMassKg: Double? {
        guard leanMassKgCount > 0 else { return nil }
        return leanMassKgSum / Double(leanMassKgCount)
    }

    var avgWaistCm: Double? {
        guard waistMCount > 0 else { return nil }
        return (waistMSum / Double(waistMCount)) * 100.0
    }

    var derivedFatMassKg: Double? {
        guard let w = avgWeightKg, let bf = avgBodyFatFraction else { return nil }
        return w * bf
    }

    var derivedBMIFromWeightHeight: Double? {
        guard let w = avgWeightKg, let h = avgHeightM, h > 0 else { return nil }
        return w / (h * h)
    }

    var paceMinPerKm: Double? {
        guard workoutDistanceKm > 0 else { return nil }
        return workoutDurationMin / workoutDistanceKm
    }
}

private struct NJCalendarDateSheetTarget: Identifiable {
    let date: Date
    var id: Int64 { Int64(date.timeIntervalSince1970 * 1000.0) }
}

private struct NJPlanningNoteSheetTarget: Identifiable {
    let kind: String
    let targetKey: String
    let title: String
    let protonJSON: String
    var id: String { "\(kind):\(targetKey)" }
}

private struct NJCalendarDaySummaryTarget: Identifiable {
    let date: Date
    var id: Int64 { Int64(date.timeIntervalSince1970 * 1000.0) }
}

private struct NJCalendarDaySummaryData {
    let title: String
    let sourceText: String
    let aiSummary: String
    let aiMode: String
    let aiError: String?
}

private struct NJFinanceEditorTarget: Identifiable {
    let date: Date
    var id: String { String(Int(date.timeIntervalSince1970)) }
}

private struct NJFinanceTransactionEditorTarget: Identifiable {
    let transactionID: String
    var id: String { transactionID }
}

private struct NJCalendarExportTarget: Identifiable {
    let url: URL
    var id: String { url.path }
}

private struct NJTrainingManageTarget: Identifiable {
    let date: Date
    var id: String { String(Int(date.timeIntervalSince1970)) }
}

private struct NJTrainingEditTarget: Identifiable {
    let plan: NJPlannedExercise
    var id: String { plan.planID }
}

private struct NJTrainingPlannerWeekTarget: Identifiable {
    let weekStart: Date
    var id: String { String(Int(weekStart.timeIntervalSince1970)) }
}

private enum NJFinanceLedgerColumn: String, CaseIterable, Identifiable {
    case date
    case time
    case source
    case merchant
    case details
    case nature
    case category
    case tags
    case originalAmount
    case rmbAmount

    var id: String { rawValue }

    var title: String {
        switch self {
        case .date: return "Date"
        case .time: return "Time"
        case .source: return "Source"
        case .merchant: return "Merchant"
        case .details: return "Details"
        case .nature: return "Nature"
        case .category: return "Category"
        case .tags: return "Tags"
        case .originalAmount: return "Orig"
        case .rmbAmount: return "RMB"
        }
    }

    var width: CGFloat {
        switch self {
        case .date: return 96
        case .time: return 64
        case .source: return 110
        case .merchant: return 210
        case .details: return 280
        case .nature: return 118
        case .category: return 132
        case .tags: return 190
        case .originalAmount: return 110
        case .rmbAmount: return 110
        }
    }

    var alignment: Alignment {
        switch self {
        case .originalAmount, .rmbAmount:
            return .trailing
        default:
            return .leading
        }
    }
}

struct NJCalendarView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow

    @State private var displayMode: NJCalendarDisplayMode = .month
    @State private var contentMode: NJCalendarContentMode = .memory
    @State private var financeWorkspaceMode: NJFinanceWorkspaceMode = .calendar
    @State private var focusedDate: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var itemsByDate: [String: NJCalendarItem] = [:]
    @State private var healthByDate: [String: NJCalendarHealthDay] = [:]
    @State private var renewalItemsByDate: [String: [NJRenewalItemRecord]] = [:]
    @State private var timeLogsByDate: [String: [NJTimeSlotRecord]] = [:]
    @State private var financeEventsByDate: [String: [NJFinanceMacroEvent]] = [:]
    @State private var financeBriefsByDate: [String: NJFinanceDailyBrief] = [:]
    @State private var financeResearchSessions: [String: NJFinanceResearchSession] = [:]
    @State private var financeResearchMessages: [String: [NJFinanceResearchMessage]] = [:]
    @State private var financeResearchTasks: [String: [NJFinanceResearchTask]] = [:]
    @State private var financeFindingsByPremise: [String: [NJFinanceFinding]] = [:]
    @State private var financeSourceItemsByPremise: [String: [NJFinanceSourceItem]] = [:]
    @State private var financeTransactions: [NJFinanceTransaction] = []
    @State private var selectedFinanceIssueID: String = "p1_late_cycle_everything_bubble"
    @State private var financeDraftMessage: String = ""
    @State private var latestHeightMForVisibleRange: Double? = nil
    @State private var plannedByDate: [String: [NJPlannedExercise]] = [:]
    @State private var eventsByDate: [String: [EKEvent]] = [:]
    @State private var calendarAuth: EKAuthorizationStatus = .notDetermined
    @State private var photoPickerTarget: NJCalendarDateSheetTarget? = nil
    @State private var planExerciseTarget: NJCalendarDateSheetTarget? = nil
    @State private var showWeeklyWorkoutSheet = false
    @State private var weeklyWorkoutEntries: [NJWeeklyWorkoutEntry] = []
    @State private var planningNoteTarget: NJPlanningNoteSheetTarget? = nil
    @State private var daySummaryTarget: NJCalendarDaySummaryTarget? = nil
    @State private var planningNoteHandle = NJProtonEditorHandle()
    @State private var planningNoteAttr = NSAttributedString(string: "")
    @State private var planningNoteSel = NSRange(location: 0, length: 0)
    @State private var planningNoteEditorHeight: CGFloat = 120
    @State private var planningNotePickedPhotoItem: PhotosPickerItem? = nil
    @State private var financeEditorTarget: NJFinanceEditorTarget? = nil
    @State private var showPlanningClipboardPreviewSheet = false
    @State private var planningClipboardDrafts: [NJPlanningClipboardDraft] = []
    @State private var showTrainingPlanImporter = false
    @State private var trainingExportTarget: NJCalendarExportTarget? = nil
    @State private var trainingAlertMessage = ""
    @State private var showTrainingAlert = false
    @State private var financeAlertMessage = ""
    @State private var showFinanceAlert = false
    @State private var showFinanceDataImporter = false
    @State private var showFinanceScreenshotImporter = false
    @State private var financeSourceFilters: Set<String> = []
    @State private var financeTagFilters: Set<String> = []
    @State private var financeSpendingWindow: NJFinanceSpendingWindow = .month
    @State private var financeCustomRangeStart: Date = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
    @State private var financeCustomRangeEnd: Date = Date()
    @State private var financeSelectedChartAngle: Double? = nil
    @State private var financeSelectedCategory: String? = nil
    @State private var financeInlineTagDrafts: [String: String] = [:]
    @State private var financeTransactionEditorTarget: NJFinanceTransactionEditorTarget? = nil
    @State private var financeLedgerColumnWidths: [NJFinanceLedgerColumn: CGFloat] = [:]
    @State private var trainingManageTarget: NJTrainingManageTarget? = nil
    @State private var trainingEditTarget: NJTrainingEditTarget? = nil
    @State private var trainingPlannerWeekTarget: NJTrainingPlannerWeekTarget? = nil
    @State private var matchedTrainingResultByPlanID: [String: NJCalendarTrainingResult] = [:]
    @StateObject private var weatherForecast = NJCalendarWeatherForecastProvider()

    private let calendar: Calendar = {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        return calendar
    }()
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
            if contentMode == .finance && financeWorkspaceMode == .research {
                financeResearchWorkspaceView()
            } else if contentMode == .finance && financeWorkspaceMode == .spending {
                financeSpendingWorkspaceView()
            } else if displayMode == .month {
                calendarGrid()
            } else {
                calendarGrid()
            }
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar() }
        .onAppear {
            reloadAll()
            weatherForecast.startIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: .njPullCompleted)) { _ in
            reloadAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .njTimeSlotInboxDidChange)) { _ in
            reloadAll()
        }
        .onChange(of: displayMode) { _, _ in reloadAll() }
        .onChange(of: contentMode) { _, _ in reloadAll() }
        .onChange(of: financeWorkspaceMode) { _, _ in
            reloadFinanceResearchWorkspace()
            reloadFinanceTransactions()
        }
        .onChange(of: focusedDate) { _, _ in reloadItemsForVisibleRange() }
        .onChange(of: selectedDate) { _, _ in syncSelectedItem() }
        .fileImporter(
            isPresented: $showTrainingPlanImporter,
            allowedContentTypes: [.json, .plainText, .text, .data, .content],
            allowsMultipleSelection: false
        ) { result in
            handleTrainingPlanImport(result: result)
        }
        .fileImporter(
            isPresented: $showFinanceDataImporter,
            allowedContentTypes: [.commaSeparatedText, .text, .plainText, .data, .content, .zip],
            allowsMultipleSelection: false
        ) { result in
            handleFinanceDataImport(result: result)
        }
        .fileImporter(
            isPresented: $showFinanceScreenshotImporter,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            handleFinanceScreenshotImport(result: result)
        }
        .sheet(item: $photoPickerTarget) { target in
            NJDatePhotoPicker(date: target.date) { image, localID in
                savePhoto(for: target.date, image: image, localIdentifier: localID)
            }
        }
        .sheet(item: $trainingExportTarget) { target in
            NJDocumentExporter(url: target.url)
        }
        .sheet(item: $trainingManageTarget) { target in
            NJTrainingManageSheet(
                date: target.date,
                plans: (plannedByDate[dateKey(target.date)] ?? []).sorted { ($0.title, $0.updatedAtMs) < ($1.title, $1.updatedAtMs) },
                onEdit: { plan in
                    trainingEditTarget = NJTrainingEditTarget(plan: plan)
                },
                onDelete: { plan in
                    deletePlannedExercise(plan)
                }
            )
        }
        .sheet(item: $trainingEditTarget) { target in
            NJTrainingSessionEditorSheet(
                date: parseDateKey(target.plan.dateKey) ?? selectedDate,
                plan: target.plan,
                onSave: { updated in
                    store.notes.upsertPlannedExercise(updated)
                    reloadItemsForVisibleRange()
                    store.publishTrainingWeekSnapshotToWidget(referenceDate: parseDateKey(updated.dateKey) ?? selectedDate)
                    NJTrainingRuntime.shared.reload(referenceDate: parseDateKey(updated.dateKey) ?? selectedDate)
                },
                onDelete: { plan in
                    deletePlannedExercise(plan)
                }
            )
        }
        .sheet(item: $trainingPlannerWeekTarget) { target in
            NJTrainingWeekPlannerSheet(
                weekStart: target.weekStart,
                loadPlansByDate: { plansForWeek(start: target.weekStart) },
                onImportJSON: {
                    showTrainingPlanImporter = true
                },
                onAdd: { date in
                    trainingEditTarget = NJTrainingEditTarget(plan: makeBlankTrainingPlan(for: date))
                },
                onEdit: { plan in
                    trainingEditTarget = NJTrainingEditTarget(plan: plan)
                },
                onDelete: { plan in
                    deletePlannedExercise(plan)
                }
            )
        }
        .sheet(item: $planExerciseTarget) { target in
            NJPlanExerciseSheet(date: target.date) { sport, distKm, durMin, notes in
                savePlannedExercise(date: target.date, sport: sport, distanceKm: distKm, durationMin: durMin, notes: notes)
            }
        }
        .sheet(isPresented: $showWeeklyWorkoutSheet) {
            NJWeeklyWorkoutListSheet(
                entries: weeklyWorkoutEntries,
                title: weekRangeTitle(for: focusedDate),
                onExportToLLM: exportEntryToLLMJournal(_:),
                onDeleteWorkout: deleteWorkoutEntry
            )
        }
        .sheet(item: $planningNoteTarget) { target in
            NJPlanningNoteSheet(
                title: target.title,
                handle: planningNoteHandle,
                initialAttributedText: planningNoteAttr,
                initialSelectedRange: planningNoteSel,
                initialProtonJSON: target.protonJSON,
                snapshotAttributedText: $planningNoteAttr,
                snapshotSelectedRange: $planningNoteSel,
                measuredHeight: $planningNoteEditorHeight,
                pickedPhotoItem: $planningNotePickedPhotoItem,
                onSave: { plainText, protonJSON in
                    savePlanningNote(kind: target.kind, targetKey: target.targetKey, text: plainText, protonJSON: protonJSON)
                }
            )
            .id(target.id)
        }
        .sheet(item: $daySummaryTarget) { target in
            NJCalendarDaySummarySheet(
                date: target.date,
                loadSummary: { await generateDaySummary(for: target.date) }
            )
        }
        .sheet(item: $financeEditorTarget) { target in
            NJFinanceDaySheet(
                date: target.date,
                initialEvents: (financeEventsByDate[dateKey(target.date)] ?? []).sorted { ($0.timeText, $0.title) < ($1.timeText, $1.title) },
                initialBrief: financeBriefsByDate[dateKey(target.date)],
                onSave: { events, brief in
                    saveFinanceDay(date: target.date, events: events, brief: brief)
                }
            )
        }
        .sheet(item: $financeTransactionEditorTarget) { target in
            if let row = financeTransactions.first(where: { $0.transactionID == target.transactionID }) {
                NJFinanceTransactionEditorSheet(
                    row: row,
                    onSave: { updated in
                        store.notes.upsertFinanceTransaction(updated)
                        store.sync.schedulePush(debounceMs: 0)
                        reloadFinanceTransactions()
                    }
                )
            }
        }
        .sheet(isPresented: $showPlanningClipboardPreviewSheet) {
            NJPlanningClipboardPreviewSheet(
                drafts: planningClipboardDrafts,
                onSubmit: { submitWeekPlanningPreviewToClipboard() }
            )
        }
        .alert("Training Plan", isPresented: $showTrainingAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(trainingAlertMessage)
        }
        .alert("Finance", isPresented: $showFinanceAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(financeAlertMessage)
        }
    }

    @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }

        ToolbarItem(placement: .topBarTrailing) {
            if contentMode == .finance {
                Button("Edit") {
                    openFinanceEditor(for: selectedDate)
                }
            } else if isPastDate(selectedDate) {
                Button("Add Photo") {
                    openPhotoPicker(for: selectedDate)
                }
            }
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button {
                weatherForecast.refresh()
            } label: {
                Image(systemName: "cloud.sun")
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
            if contentMode == .finance {
                Button {
                    openFinanceEditor(for: selectedDate)
                } label: {
                    Image(systemName: "square.and.pencil")
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            if contentMode == .health {
                Button {
                    weeklyWorkoutEntries = loadWeeklyWorkoutEntries()
                    showWeeklyWorkoutSheet = true
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)
            }
            if contentMode == .health {
                Button {
                    if let (start, _) = weekRange(for: focusedDate) {
                        trainingPlannerWeekTarget = NJTrainingPlannerWeekTarget(weekStart: start)
                    }
                } label: {
                    Image(systemName: "calendar.badge.plus")
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                Button {
                    showTrainingPlanImporter = true
                } label: {
                    Image(systemName: "square.and.arrow.down")
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                Button {
                    exportWeeklyTrainingReview()
                } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.subheadline)
                        .frame(width: 32, height: 32)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 8)

                if hasImportedTrainingPlan(in: focusedDate) {
                    Button {
                        deleteImportedTrainingPlan(in: focusedDate)
                    } label: {
                        Image(systemName: "trash")
                            .font(.subheadline)
                            .frame(width: 32, height: 32)
                            .background(Color(UIColor.secondarySystemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 8)
                }
            }
            contentModePicker()
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private func headerSection() -> some View {
        VStack(spacing: 0) {
            headerBar()
            if contentMode == .finance {
                financeWorkspaceModePicker()
            }
            modePicker()
            if displayMode == .month {
                weekdayHeader()
            }
        }
        .background(Color(UIColor.systemBackground))
        .zIndex(1)
    }

    @ViewBuilder
    private func modePicker() -> some View {
        if contentMode == .finance && financeWorkspaceMode != .calendar {
            EmptyView()
        } else {
            Picker("View", selection: $displayMode) {
                ForEach(NJCalendarDisplayMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private func financeWorkspaceModePicker() -> some View {
        Picker("Finance Workspace", selection: $financeWorkspaceMode) {
            ForEach(NJFinanceWorkspaceMode.allCases) { mode in
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
                    let minRowHeight: CGFloat = (contentMode == .finance) ? 132 : 56
                    let rowHeight = max(minRowHeight, (geo.size.height - totalSpacing) / CGFloat(rows))
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
        let renewals = renewalItemsByDate[key] ?? []
        let isSelected = calendar.isDate(date, inSameDayAs: selectedDate)
        let isInMonth = calendar.isDate(date, equalTo: focusedDate, toGranularity: .month)
        let textColor: Color = isInMonth ? .primary : .secondary
        let photo = selectedPhotoImage(item)
        let dayLabel = isWeekly ? "\(weekdayName(date)), \(dayNumber(date))" : dayNumber(date)
        let weatherBadge = weatherForecast.badge(for: date)
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

                if let weatherBadge {
                    weatherBadgeView(weatherBadge, isWeekly: isWeekly)
                }

                let planningPreviewTitle: String = {
                    guard isWeekly, contentMode == .memory else { return "" }
                    return calendar.component(.weekday, from: date) == 1 ? "WEEKLY PLANNING NOTE" : "PLANNING NOTE"
                }()

                let planningPreviewLines: [String] = {
                    guard isWeekly, contentMode == .memory else { return [] }
                    return calendar.component(.weekday, from: date) == 1
                        ? weeklyPlanningPreviewLines(for: date)
                        : dayPlanningPreviewLines(for: date)
                }()

                if !events.isEmpty || !renewals.isEmpty {
                    if contentMode == .memory {
                        ForEach(Array(renewals.prefix(isWeekly ? 4 : 2)), id: \.renewalItemID) { row in
                            Text(renewalCalendarLine(for: row))
                                .font(isWeekly ? .callout : .caption2)
                                .lineLimit(1)
                                .foregroundStyle(renewalCalendarColor(for: row))
                        }
                        ForEach(Array(events.prefix(isWeekly ? 6 : 2).enumerated()), id: \.offset) { _, ev in
                            Text(ev.title)
                                .font(isWeekly ? .callout : .caption2)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                        if !planningPreviewLines.isEmpty {
                            Divider()
                                .padding(.top, 2)
                            Text(planningPreviewTitle)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            ForEach(Array(planningPreviewLines.prefix(3).enumerated()), id: \.offset) { _, line in
                                Text(line)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else {
                        contentSummaryView(date: date, isWeekly: isWeekly)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    }
                } else {
                    if contentMode == .memory {
                        if !planningPreviewLines.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(planningPreviewTitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                ForEach(Array(planningPreviewLines.prefix(4).enumerated()), id: \.offset) { _, line in
                                    Text(line)
                                        .font(.caption)
                                        .lineLimit(1)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        } else {
                            Text(" ")
                                .font(.caption2)
                        }
                    } else {
                        contentSummaryView(date: date, isWeekly: isWeekly)
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
                    activateDate(date)
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
        .onTapGesture {
            activateDate(date)
        }
        .contextMenu {
            if contentMode == .memory {
                Button("Summarize Day") {
                    activateDate(date)
                    openDaySummary(for: date)
                }
                if displayMode == .month, isFutureDate(date) {
                    Button("Edit Day Planning Note") {
                        activateDate(date)
                        openDayPlanningNoteEditor(for: date)
                    }
                }
                if hasSavedPhoto(item) {
                    if let localID = photoLocalIdentifier(for: item) {
                        Button("Open Photo") { openPhotoWindow(localIdentifier: localID) }
                    }
                }
                if isPastDate(date) {
                    Button("Add Photo") {
                        openPhotoPicker(for: date)
                    }
                    if hasSavedPhoto(item) {
                        Button("Remove Photo", role: .destructive) {
                            activateDate(date)
                            removePhoto(for: date)
                        }
                    }
                }
            }
            if contentMode == .health, !isPastDate(date) {
                Button("Plan Exercise") {
                    openPlanExerciseSheet(for: date)
                }
                let plans = plannedByDate[key] ?? []
                if !plans.isEmpty {
                    Button("Manage Training") {
                        trainingManageTarget = NJTrainingManageTarget(date: date)
                    }
                }
            }
            if contentMode == .finance {
                Button("Edit Finance Day") {
                    openFinanceEditor(for: date)
                }
            }
        }
    }

    private func weatherBadgeView(_ badge: NJCalendarWeatherBadgeModel, isWeekly: Bool) -> some View {
        HStack(spacing: 5) {
            Image(systemName: badge.symbolName)
            Text(badge.temperatureText)
        }
        .font(isWeekly ? .caption.weight(.semibold) : .caption2.weight(.semibold))
        .foregroundStyle(.blue)
        .padding(.horizontal, isWeekly ? 8 : 6)
        .padding(.vertical, isWeekly ? 5 : 3)
        .background(Capsule().fill(Color.blue.opacity(0.12)))
    }

    private func reloadAll() {
        reloadItemsForVisibleRange()
        reloadFinanceResearchWorkspace()
        reloadFinanceTransactions()
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
        reloadRenewalsForVisibleRange(startKey: startKey, endKey: endKey)
        for item in items where !item.photoAttachmentID.isEmpty {
            ensureThumbCached(attachmentID: item.photoAttachmentID, dateKey: item.dateKey)
        }
        loadEventsForVisibleRange(start: start, end: end)
        reloadHealthForVisibleRange(start: start, end: end)
        reloadTimeLogsForVisibleRange(start: start, end: end)
        reloadFinanceForVisibleRange(start: start, end: end)
        reloadPlansForVisibleRange(start: start, end: end)
        recomputeMatchedTrainingResults(start: start, end: end)
    }

    private func syncSelectedItem() {
        _ = dateKey(selectedDate)
    }

    private func reloadRenewalsForVisibleRange(startKey: String, endKey: String) {
        let grouped = Dictionary(grouping: store.notes.listRenewalItems(ownerScope: "ME").filter { row in
            let key = row.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !key.isEmpty, key >= startKey, key <= endKey else { return false }
            return shouldShowRenewalOnCalendar(row)
        }) { row in
            row.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        renewalItemsByDate = grouped.mapValues { rows in
            rows.sorted {
                if $0.personName.localizedCaseInsensitiveCompare($1.personName) == .orderedSame {
                    return $0.documentName.localizedCaseInsensitiveCompare($1.documentName) == .orderedAscending
                }
                return $0.personName.localizedCaseInsensitiveCompare($1.personName) == .orderedAscending
            }
        }
    }

    private func shouldShowRenewalOnCalendar(_ row: NJRenewalItemRecord) -> Bool {
        let type = row.documentType.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return type == "passport" || type == "identity_card"
    }

    private func renewalCalendarLine(for row: NJRenewalItemRecord) -> String {
        let person = row.personName.trimmingCharacters(in: .whitespacesAndNewlines)
        let document = row.documentName.trimmingCharacters(in: .whitespacesAndNewlines)
        if person.isEmpty { return "\(document) expiry" }
        return "\(person) • \(document) expiry"
    }

    private func renewalCalendarColor(for row: NJRenewalItemRecord) -> Color {
        switch row.status {
        case "expired":
            return .red
        case "due_soon":
            return .orange
        default:
            return .secondary
        }
    }

    private func savePhoto(for date: Date, image: UIImage, localIdentifier: String) {
        let key = dateKey(date)
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
            item.photoCloudID = cloudIdentifierString(for: localIdentifier)
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

    private func hasSavedPhoto(_ item: NJCalendarItem?) -> Bool {
        guard let item else { return false }
        return !item.photoThumbPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !item.photoAttachmentID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !item.photoLocalID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
            !item.photoCloudID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func photoLocalIdentifier(for item: NJCalendarItem?) -> String? {
        guard let item, hasSavedPhoto(item) else { return nil }
        let direct = item.photoLocalID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !direct.isEmpty { return direct }
        if !item.photoAttachmentID.isEmpty,
           let att = store.notes.attachmentByID(item.photoAttachmentID) {
            let ref = att.fullPhotoRef.trimmingCharacters(in: .whitespacesAndNewlines)
            if !ref.isEmpty { return ref }
        }
        let cloudID = item.photoCloudID.trimmingCharacters(in: .whitespacesAndNewlines)
        if !cloudID.isEmpty, let mapped = localIdentifierFromCloudID(cloudID) {
            return mapped
        }
        return nil
    }

    private func cloudIdentifierString(for localIdentifier: String) -> String {
        let id = localIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return "" }
        if #available(iOS 15.0, *) {
            let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: [id])
            if case .success(let cloudID)? = mappings[id] {
                return cloudID.stringValue
            }
        }
        return ""
    }

    private func localIdentifierFromCloudID(_ cloudID: String) -> String? {
        let s = cloudID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }
        if #available(iOS 15.0, *) {
            let cid = PHCloudIdentifier(stringValue: s)
            let mappings = PHPhotoLibrary.shared().localIdentifierMappings(for: [cid])
            if case .success(let localID)? = mappings[cid] {
                let trimmed = localID.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }
            }
        }
        return nil
    }

    private func removePhoto(for date: Date) {
        let key = dateKey(date)
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
        item.photoCloudID = ""
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
        let now = DBNoteRepository.nowMs()
        let plan = NJPlannedExercise(
            planID: UUID().uuidString.lowercased(),
            dateKey: dateKey(date),
            weekKey: DBNoteRepository.sundayWeekStartKey(for: date, calendar: calendar),
            title: sport,
            category: plannedCategory(for: sport),
            sport: sport,
            sessionType: manualSessionType(for: sport),
            targetDistanceKm: distanceKm,
            targetDurationMin: durationMin,
            notes: notes,
            createdAtMs: now,
            updatedAtMs: now,
            deleted: 0
        )
        store.notes.upsertPlannedExercise(plan)
        store.publishTrainingWeekSnapshotToWidget()
        NJTrainingRuntime.shared.reload(referenceDate: date)
        reloadPlansForVisibleRange(start: gridDates().first ?? date, end: gridDates().last ?? date)
    }

    private func deletePlannedExercise(_ plan: NJPlannedExercise) {
        let now = DBNoteRepository.nowMs()
        store.notes.deletePlannedExercise(planID: plan.planID, nowMs: now)
        reloadItemsForVisibleRange()
        store.publishTrainingWeekSnapshotToWidget(referenceDate: parseDateKey(plan.dateKey) ?? selectedDate)
        NJTrainingRuntime.shared.reload(referenceDate: parseDateKey(plan.dateKey) ?? selectedDate)
    }

    private func plannedCategory(for sport: String) -> String {
        let s = sport.lowercased()
        if s.contains("strength") || s.contains("gym") { return "strength" }
        if s.contains("core") || s.contains("plank") { return "core" }
        return "aerobic"
    }

    private func manualSessionType(for sport: String) -> String {
        let s = sport.lowercased()
        if s.contains("run") { return "run" }
        if s.contains("cycl") || s.contains("bike") { return "bike" }
        if s.contains("swim") { return "swim" }
        if s.contains("hiking") || s.contains("hike") { return "hike" }
        if s.contains("tennis") { return "tennis" }
        if s.contains("strength") || s.contains("gym") { return "strength" }
        return "session"
    }

    private func selectedPhotoImage(_ item: NJCalendarItem?) -> UIImage? {
        guard let item else { return nil }
        if !item.photoThumbPath.isEmpty {
            if let image = NJAttachmentCache.imageFromPath(item.photoThumbPath) {
                return image
            }
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

    private func activateDate(_ date: Date) {
        selectedDate = date
        switch displayMode {
        case .month:
            focusedDate = date
        case .week:
            if !calendar.isDate(date, equalTo: focusedDate, toGranularity: .weekOfYear) {
                focusedDate = date
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
        store.publishTrainingWeekSnapshotToWidget()
    }

    private func reloadTimeLogsForVisibleRange(start: Date, end: Date) {
        let slots = store.notes.listTimeSlots(ownerScope: "ME")
        let startMs = Int64(calendar.startOfDay(for: start).timeIntervalSince1970 * 1000.0)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: end)) ?? end
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000.0)
        let scoped = slots.filter { $0.deleted == 0 && $0.startAtMs >= startMs && $0.startAtMs < endMs }
        timeLogsByDate = Dictionary(grouping: scoped) { slot in
            dateKey(Date(timeIntervalSince1970: TimeInterval(slot.startAtMs) / 1000.0))
        }
    }

    private func reloadFinanceForVisibleRange(start: Date, end: Date) {
        let startKey = dateKey(start)
        let endKey = dateKey(end)
        let events = store.notes.listFinanceMacroEvents(startKey: startKey, endKey: endKey)
        financeEventsByDate = Dictionary(grouping: events, by: { $0.dateKey })
        let briefs = store.notes.listFinanceDailyBriefs(startKey: startKey, endKey: endKey)
        financeBriefsByDate = Dictionary(uniqueKeysWithValues: briefs.map { ($0.dateKey, $0) })
    }

    private func reloadFinanceTransactions() {
        financeTransactions = store.notes.listRecentFinanceTransactions(limit: 300)
    }

    private func financeIssueTabs() -> [NJFinanceIssueTab] {
        [
            NJFinanceIssueTab(premiseID: "p1_late_cycle_everything_bubble", themeID: "late_cycle", title: "Late-Cycle Bubble", promptHint: "What new evidence supports or weakens the late-cycle bubble thesis?"),
            NJFinanceIssueTab(premiseID: "p2_ai_transformative_but_revenue_absent", themeID: "ai_capex_burden", title: "AI Capex Burden", promptHint: "Research whether AI capex is outrunning monetization."),
            NJFinanceIssueTab(premiseID: "p3_consumer_will_crack", themeID: "consumer_crack", title: "Consumer Crack", promptHint: "Track signs the consumer is breaking."),
            NJFinanceIssueTab(premiseID: "p4_private_credit_cre_stress", themeID: "private_credit_cre", title: "Private Credit / CRE", promptHint: "Look for funding stress, CRE rollover pain, and spillover."),
            NJFinanceIssueTab(premiseID: "p5_safe_haven_liquidation_then_buy", themeID: "safe_haven_liquidation", title: "Safe-Haven Flush", promptHint: "What would signal forced liquidation before the real buy window?"),
            NJFinanceIssueTab(premiseID: "p6_japan_as_trigger", themeID: "japan_trigger", title: "Japan Trigger", promptHint: "Research BOJ, carry unwind, and Japan spillover risk."),
            NJFinanceIssueTab(premiseID: "p8_world_news_for_corroboration_or_refutation", themeID: "world_news", title: "World Corroboration", promptHint: "Bring in world news that corroborates or refutes the core thesis.")
        ]
    }

    private func reloadFinanceResearchWorkspace() {
        ensureFinanceResearchSeeded()
        let sessions = store.notes.listFinanceResearchSessions()
        financeResearchSessions = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionID, $0) })
        var messages: [String: [NJFinanceResearchMessage]] = [:]
        var tasks: [String: [NJFinanceResearchTask]] = [:]
        var findings: [String: [NJFinanceFinding]] = [:]
        var sourceItems: [String: [NJFinanceSourceItem]] = [:]
        for issue in financeIssueTabs() {
            messages[issue.sessionID] = store.notes.listFinanceResearchMessages(sessionID: issue.sessionID)
            tasks[issue.sessionID] = store.notes.listFinanceResearchTasks(sessionID: issue.sessionID)
            findings[issue.premiseID] = store.notes.listFinanceFindings(sessionID: issue.sessionID, premiseID: issue.premiseID)
            sourceItems[issue.premiseID] = store.notes.listFinanceSourceItems(premiseID: issue.premiseID, limit: 20)
        }
        financeResearchMessages = messages
        financeResearchTasks = tasks
        financeFindingsByPremise = findings
        financeSourceItemsByPremise = sourceItems
        if !financeIssueTabs().contains(where: { $0.premiseID == selectedFinanceIssueID }) {
            selectedFinanceIssueID = financeIssueTabs().first?.premiseID ?? ""
        }
    }

    private func ensureFinanceResearchSeeded() {
        let now = DBNoteRepository.nowMs()
        for issue in financeIssueTabs() {
            if store.notes.financeResearchSession(sessionID: issue.sessionID) == nil {
                store.notes.upsertFinanceResearchSession(
                    NJFinanceResearchSession(
                        sessionID: issue.sessionID,
                        title: issue.title,
                        themeID: issue.themeID,
                        premiseID: issue.premiseID,
                        status: "active",
                        summary: "",
                        lastMessageAtMs: now,
                        createdAtMs: now,
                        updatedAtMs: now,
                        deleted: 0
                    )
                )
            }
        }
    }

    private func sendFinanceResearchMessage(for issue: NJFinanceIssueTab) {
        let body = financeDraftMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let now = DBNoteRepository.nowMs()
        let messageID = UUID().uuidString.lowercased()
        let existing = store.notes.financeResearchSession(sessionID: issue.sessionID)
        store.notes.upsertFinanceResearchSession(
            NJFinanceResearchSession(
                sessionID: issue.sessionID,
                title: existing?.title ?? issue.title,
                themeID: existing?.themeID ?? issue.themeID,
                premiseID: existing?.premiseID ?? issue.premiseID,
                status: "active",
                summary: existing?.summary ?? "",
                lastMessageAtMs: now,
                createdAtMs: existing?.createdAtMs ?? now,
                updatedAtMs: now,
                deleted: 0
            )
        )
        store.notes.upsertFinanceResearchMessage(
            NJFinanceResearchMessage(
                messageID: messageID,
                sessionID: issue.sessionID,
                role: "user",
                body: body,
                sourceRefsJSON: "[]",
                retrievalContextJSON: "[]",
                taskRequestJSON: "{\"requested_action\":\"research_more\"}",
                syncStatus: "pending",
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )
        store.notes.upsertFinanceResearchTask(
            NJFinanceResearchTask(
                taskID: UUID().uuidString.lowercased(),
                sessionID: issue.sessionID,
                messageID: messageID,
                taskKind: "research_more",
                instruction: body,
                status: "pending",
                priority: 5,
                resultSummary: "",
                resultRefsJSON: "[]",
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )
        financeDraftMessage = ""
        reloadFinanceResearchWorkspace()
    }

    private func exportFinanceResearchMessageToJournal(issue: NJFinanceIssueTab, message: NJFinanceResearchMessage) {
        let body = message.body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        let header = "\(issue.title) Research Update"
        let lines = [
            header,
            "Premise: \(issue.premiseID)",
            "Saved: \(dateKey(Date()))",
            "",
            body
        ]
        saveFinanceResearchEntryToJournal(
            issue: issue,
            header: header,
            body: lines.joined(separator: "\n"),
            messageID: message.messageID,
            findingID: ""
        )
    }

    private func exportFinanceFindingToJournal(issue: NJFinanceIssueTab, finding: NJFinanceFinding) {
        let summary = finding.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !summary.isEmpty else { return }
        let header = "\(issue.title) Finding"
        let confidenceText = String(format: "%.2f", finding.confidence)
        let lines = [
            header,
            "Premise: \(issue.premiseID)",
            "Stance: \(finding.stance.uppercased())",
            "Confidence: \(confidenceText)",
            "Saved: \(dateKey(Date()))",
            "",
            summary
        ]
        saveFinanceResearchEntryToJournal(
            issue: issue,
            header: header,
            body: lines.joined(separator: "\n"),
            messageID: "",
            findingID: finding.findingID
        )
    }

    private func saveFinanceResearchEntryToJournal(
        issue: NJFinanceIssueTab,
        header: String,
        body: String,
        messageID: String,
        findingID: String
    ) {
        guard let notebookID = store.selectedNotebookID,
              let tabDomain = store.currentTabDomain else {
            presentFinanceAlert("Select a notebook and tab before saving finance research to the journal.")
            return
        }

        let noteTitle = "Finance Research \(dateKey(Date()))"
        let existingNote = store.notes.listNotes(tabDomainKey: tabDomain).first {
            $0.deleted == 0 && $0.notebook == notebookID && $0.title == noteTitle
        }
        let note = existingNote ?? store.notes.createNote(notebook: notebookID, tabDomain: tabDomain, title: noteTitle)
        let payloadJSON = NJQuickNotePayload.makePayloadJSON(from: body)

        guard let blockID = store.notes.createQuickNoteBlock(
            payloadJSON: payloadJSON,
            createdAtMs: DBNoteRepository.nowMs(),
            tags: ["finance", "research", issue.themeID]
        ) else {
            presentFinanceAlert("Unable to save this research entry into the journal.")
            return
        }

        let orderKey = store.notes.nextAppendOrderKey(noteID: note.id.raw)
        _ = store.notes.attachExistingBlockToNote(noteID: note.id.raw, blockID: blockID, orderKey: orderKey)

        let now = DBNoteRepository.nowMs()
        store.notes.upsertFinanceJournalLink(
            NJFinanceJournalLink(
                linkID: UUID().uuidString.lowercased(),
                sessionID: issue.sessionID,
                messageID: messageID,
                findingID: findingID,
                noteBlockID: blockID,
                excerpt: String(body.prefix(280)),
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )
        store.sync.schedulePush(debounceMs: 0)
        presentFinanceAlert("Saved “\(header)” into \(noteTitle).")
    }

    private func presentFinanceAlert(_ message: String) {
        financeAlertMessage = message
        showFinanceAlert = true
    }

    private func financeSpendingWorkspaceView() -> some View {
        let availableSources = Set(financeTransactions.map(\.sourceType))
        let availableTags = Set(financeTransactions.flatMap(financeTags(for:)))
        let dateFiltered = financeTransactions.filter { row in
            financeDateRangeContains(row.occurredAtMs)
        }
        let sourceFiltered = dateFiltered.filter { financeSourceFilters.isEmpty || financeSourceFilters.contains($0.sourceType) }
        let filtered = sourceFiltered.filter { row in
            financeTagFilters.isEmpty || !financeTagFilters.isDisjoint(with: Set(financeTags(for: row)))
        }
        let grouped = Dictionary(grouping: filtered) { $0.dateKey }
        let sortedKeys = grouped.keys.sorted(by: >)
        let chartSlices = financeCategorySlices(rows: filtered)
        let ledgerScopeRows = filtered.filter { row in
            guard let financeSelectedCategory else { return true }
            return financeAnalysisCategory(for: row, within: filtered) == financeSelectedCategory
        }
        let ledgerRows = ledgerScopeRows.sorted {
            if $0.occurredAtMs == $1.occurredAtMs {
                return $0.updatedAtMs > $1.updatedAtMs
            }
            return $0.occurredAtMs > $1.occurredAtMs
        }

        return ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Expense")
                            .font(.title3.weight(.semibold))
                        Text(financeRangeTitle())
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Menu {
                        Button {
                            showFinanceDataImporter = true
                        } label: {
                            Label("Import file", systemImage: "doc.badge.plus")
                        }
                        Button {
                            showFinanceScreenshotImporter = true
                        } label: {
                            Label("Import Octopus screenshots", systemImage: "photo.on.rectangle")
                        }
                    } label: {
                        Label("Import", systemImage: "square.and.arrow.down")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                }

                financeWindowControls()
                financeComparisonPanel(rows: filtered)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Source Filter")
                        .font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            financeSourceChip(title: "All", sourceType: nil, isActive: financeSourceFilters.isEmpty)
                            ForEach(Array(availableSources).sorted(), id: \.self) { source in
                                financeSourceChip(
                                    title: source.replacingOccurrences(of: "_", with: " ").capitalized,
                                    sourceType: source,
                                    isActive: financeSourceFilters.contains(source)
                                )
                            }
                        }
                    }
                }

                if !availableTags.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Tag Filter")
                            .font(.headline)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                financeTagChip(title: "All", tag: nil, isActive: financeTagFilters.isEmpty)
                                ForEach(Array(availableTags).sorted(), id: \.self) { tag in
                                    financeTagChip(title: tag, tag: tag, isActive: financeTagFilters.contains(tag))
                                }
                            }
                        }
                    }
                }

                financeSummaryPanel(rows: filtered)
                financeCategoryChartPanel(rows: filtered, slices: chartSlices)
                financeLedgerPanel(rows: ledgerRows)

                if filtered.isEmpty {
                    Text("No spending records imported yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Daily Summary")
                            .font(.headline)
                        ForEach(sortedKeys, id: \.self) { key in
                            let rows = (grouped[key] ?? []).sorted {
                                if $0.occurredAtMs == $1.occurredAtMs {
                                    return $0.updatedAtMs > $1.updatedAtMs
                                }
                                return $0.occurredAtMs > $1.occurredAtMs
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Text(key)
                                        .font(.headline)
                                    Spacer()
                                    Text(financeDayTotalText(rows))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(rows.prefix(3)) { row in
                                    financeTransactionRow(row)
                                }
                                if rows.count > 3 {
                                    Text("\(rows.count - 3) more transaction(s) in ledger below")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(12)
        }
    }

    private func financeWindowControls() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Period", selection: $financeSpendingWindow) {
                ForEach(NJFinanceSpendingWindow.allCases) { window in
                    Text(window.rawValue).tag(window)
                }
            }
            .pickerStyle(.segmented)

            if financeSpendingWindow == .custom {
                HStack(spacing: 12) {
                    DatePicker("From", selection: $financeCustomRangeStart, displayedComponents: .date)
                    DatePicker("To", selection: $financeCustomRangeEnd, in: financeCustomRangeStart..., displayedComponents: .date)
                }
            } else {
                Text("Summary and chart are currently scoped to the \(financeSpendingWindow.rawValue.lowercased()) containing the selected date.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func financeSourceChip(title: String, sourceType: String?, isActive: Bool) -> some View {
        Button {
            if let sourceType {
                if financeSourceFilters.contains(sourceType) {
                    financeSourceFilters.remove(sourceType)
                } else {
                    financeSourceFilters.insert(sourceType)
                }
            } else {
                financeSourceFilters.removeAll()
            }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isActive ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func financeTagChip(title: String, tag: String?, isActive: Bool) -> some View {
        Button {
            if let tag {
                if financeTagFilters.contains(tag) {
                    financeTagFilters.remove(tag)
                } else {
                    financeTagFilters.insert(tag)
                }
            } else {
                financeTagFilters.removeAll()
            }
        } label: {
            Text(title)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(isActive ? Color.green.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private func financeSummaryPanel(rows: [NJFinanceTransaction]) -> some View {
        let grossExpenseMinor = rows.reduce(Int64(0)) { partial, row in
            row.analysisNature == "expense" ? partial + row.amountCNYMinor : partial
        }
        let refundMinor = rows.reduce(Int64(0)) { partial, row in
            row.analysisNature == "refund" ? partial + row.amountCNYMinor : partial
        }
        let expenseMinor = max(0, grossExpenseMinor - refundMinor)
        let incomeMinor = rows.reduce(Int64(0)) { partial, row in
            row.analysisNature == "income" ? partial + row.amountCNYMinor : partial
        }
        let netMinor = incomeMinor - expenseMinor
        let bySource = Dictionary(grouping: rows, by: \.sourceType)
            .mapValues { sourceRows in
                sourceRows.reduce(Int64(0)) { partial, row in
                    switch row.analysisNature {
                    case "income", "refund":
                        return partial + row.amountCNYMinor
                    default:
                        return partial - row.amountCNYMinor
                    }
                }
            }

        return VStack(alignment: .leading, spacing: 10) {
            Text("Summary / Trial Balance")
                .font(.headline)
            HStack {
                financeMetricCard(title: "Expense", value: financeAmountText(totalMinor: -expenseMinor, currencyCode: "CNY"))
                financeMetricCard(title: "Income", value: financeAmountText(totalMinor: incomeMinor, currencyCode: "CNY"))
                financeMetricCard(title: "Refund Offset", value: financeAmountText(totalMinor: refundMinor, currencyCode: "CNY"))
                financeMetricCard(title: "Net", value: financeAmountText(totalMinor: netMinor, currencyCode: "CNY"))
            }
            VStack(alignment: .leading, spacing: 6) {
                ForEach(bySource.keys.sorted(), id: \.self) { source in
                    HStack {
                        Text(source.replacingOccurrences(of: "_", with: " ").capitalized)
                            .font(.subheadline)
                        Spacer()
                        Text(financeAmountText(totalMinor: bySource[source] ?? 0, currencyCode: "CNY"))
                            .font(.subheadline.weight(.medium))
                    }
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func financeComparisonPanel(rows: [NJFinanceTransaction]) -> some View {
        let comparison = financeComparisonPeriods()
        let currentRows = rows.filter { financeRows($0, inside: comparison.currentRange) }
        let previousRows = financeRows(in: rows, matching: comparison.previousRange)
        let currentMetrics = financeMetrics(rows: currentRows)
        let previousMetrics = financeMetrics(rows: previousRows)
        let bars: [NJFinanceComparisonBar] = [
            NJFinanceComparisonBar(metric: "Expense", periodLabel: comparison.currentLabel, totalMinor: currentMetrics.expenseMinor),
            NJFinanceComparisonBar(metric: "Expense", periodLabel: comparison.previousLabel, totalMinor: previousMetrics.expenseMinor),
            NJFinanceComparisonBar(metric: "Refund", periodLabel: comparison.currentLabel, totalMinor: currentMetrics.refundMinor),
            NJFinanceComparisonBar(metric: "Refund", periodLabel: comparison.previousLabel, totalMinor: previousMetrics.refundMinor),
            NJFinanceComparisonBar(metric: "Income", periodLabel: comparison.currentLabel, totalMinor: currentMetrics.incomeMinor),
            NJFinanceComparisonBar(metric: "Income", periodLabel: comparison.previousLabel, totalMinor: previousMetrics.incomeMinor),
            NJFinanceComparisonBar(metric: "Net", periodLabel: comparison.currentLabel, totalMinor: currentMetrics.netMinor),
            NJFinanceComparisonBar(metric: "Net", periodLabel: comparison.previousLabel, totalMinor: previousMetrics.netMinor)
        ]

        return VStack(alignment: .leading, spacing: 12) {
            Text("Period Comparison")
                .font(.headline)
            Text("\(comparison.currentLabel) vs \(comparison.previousLabel)")
                .font(.caption)
                .foregroundStyle(.secondary)

            Chart(bars) { bar in
                BarMark(
                    x: .value("Metric", bar.metric),
                    y: .value("Amount", Decimal(bar.totalMinor) / Decimal(100))
                )
                .foregroundStyle(by: .value("Period", bar.periodLabel))
                .position(by: .value("Period", bar.periodLabel))
            }
            .frame(height: 220)

            HStack {
                Text(comparison.currentLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(comparison.previousLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func financeCategoryChartPanel(rows: [NJFinanceTransaction], slices: [NJFinanceCategorySlice]) -> some View {
        let grouped = slices

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Expense Mix")
                    .font(.headline)
                Spacer()
                if let financeSelectedCategory {
                    Button("Show all categories") {
                        self.financeSelectedCategory = nil
                        financeSelectedChartAngle = nil
                    }
                    .font(.caption.weight(.medium))
                }
            }

            if grouped.isEmpty {
                Text("No expense rows in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Chart(grouped, id: \.category) { slice in
                    SectorMark(
                        angle: .value("Amount", Double(slice.total)),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .foregroundStyle(by: .value("Category", slice.category))
                    .opacity(financeSelectedCategory == nil || financeSelectedCategory == slice.category ? 1 : 0.3)
                }
                .chartAngleSelection(value: $financeSelectedChartAngle)
                .onChange(of: financeSelectedChartAngle) { _, newValue in
                    financeSelectedCategory = financeCategory(forAngle: newValue, slices: grouped)
                }
                .frame(height: 220)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(grouped.prefix(6), id: \.category) { slice in
                        Button {
                            financeSelectedCategory = slice.category
                        } label: {
                            HStack {
                                Text(slice.category)
                                    .font(.subheadline)
                                Spacer()
                                Text(financeAmountText(totalMinor: -slice.total, currencyCode: "CNY"))
                                    .font(.subheadline.weight(.medium))
                            }
                        }
                        .buttonStyle(.plain)
                        HStack {
                            Text(slice.category)
                                .font(.caption)
                                .foregroundStyle(financeSelectedCategory == slice.category ? Color.accentColor : .clear)
                            Spacer()
                            if financeSelectedCategory == slice.category {
                                Text("Ledger scoped here")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func financeLedgerPanel(rows: [NJFinanceTransaction]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Ledger")
                    .font(.headline)
                Spacer()
                if let financeSelectedCategory {
                    Text("Showing \(financeSelectedCategory)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Editable grid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if rows.isEmpty {
                Text("No rows in the selected range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        financeLedgerHeaderRow()
                        ForEach(rows) { row in
                            financeLedgerDataRow(row)
                            Divider()
                        }
                    }
                }
            }
        }
        .padding(14)
        .background(Color(UIColor.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func financeLedgerHeaderRow() -> some View {
        HStack(spacing: 0) {
            ForEach(NJFinanceLedgerColumn.allCases) { column in
                financeLedgerHeaderCell(column)
            }
        }
        .background(Color(UIColor.systemBackground).opacity(0.9))
    }

    private func financeLedgerDataRow(_ row: NJFinanceTransaction) -> some View {
        HStack(spacing: 0) {
            ForEach(NJFinanceLedgerColumn.allCases) { column in
                financeLedgerDataCell(column, row: row)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            financeTransactionEditorTarget = NJFinanceTransactionEditorTarget(transactionID: row.transactionID)
        }
    }

    private func financeLedgerHeaderCell(_ column: NJFinanceLedgerColumn) -> some View {
        financeLedgerCell(column.title, width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: true)
            .overlay(alignment: .trailing) {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 16, height: 30)
                    .overlay(alignment: .center) {
                        Capsule()
                            .fill(Color.secondary.opacity(0.45))
                            .frame(width: 3, height: 18)
                    }
                    .offset(x: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                resizeFinanceLedgerColumn(column, delta: value.translation.width)
                            }
                    )
            }
    }

    @ViewBuilder
    private func financeLedgerDataCell(_ column: NJFinanceLedgerColumn, row: NJFinanceTransaction) -> some View {
        switch column {
        case .date:
            financeLedgerCell(row.dateKey, width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        case .time:
            financeLedgerCell(timeTextFromMs(row.occurredAtMs), width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        case .source:
            financeLedgerCell(row.sourceType.replacingOccurrences(of: "_", with: " ").capitalized, width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        case .merchant:
            financeLedgerCell(row.merchantName.isEmpty ? fallbackTransactionTitle(row) : row.merchantName, width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        case .details:
            financeLedgerCell(row.details, width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        case .nature:
            financeLedgerMenuCell(
                title: row.analysisNature.capitalized,
                width: financeLedgerWidth(for: column),
                options: ["expense", "income", "refund", "transfer"]
            ) { selected in
                saveFinanceTransactionEdit(row: row, analysisNature: selected)
            }
        case .category:
            financeLedgerMenuCell(
                title: normalizedFinanceCategory(row.category),
                width: financeLedgerWidth(for: column),
                options: ["dining", "groceries", "transport", "shopping", "health", "top_up", "transfer", "fees", "other"]
            ) { selected in
                saveFinanceTransactionEdit(row: row, category: selected)
            }
        case .tags:
            financeLedgerTagCell(row, width: financeLedgerWidth(for: column))
        case .originalAmount:
            financeLedgerCell(financeAmountText(row), width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        case .rmbAmount:
            financeLedgerCell(financeAmountText(totalMinor: signedCNYMinor(row), currencyCode: "CNY"), width: financeLedgerWidth(for: column), alignment: column.alignment, isHeader: false)
        }
    }

    private func financeLedgerWidth(for column: NJFinanceLedgerColumn) -> CGFloat {
        financeLedgerColumnWidths[column] ?? column.width
    }

    private func resizeFinanceLedgerColumn(_ column: NJFinanceLedgerColumn, delta: CGFloat) {
        let currentWidth = financeLedgerWidth(for: column)
        let nextWidth = max(60, currentWidth + delta)
        financeLedgerColumnWidths[column] = nextWidth
    }

    private func financeLedgerCell(_ text: String, width: CGFloat, alignment: Alignment, isHeader: Bool) -> some View {
        Text(text)
            .font(isHeader ? .caption.weight(.semibold) : .caption)
            .foregroundStyle(isHeader ? .secondary : .primary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: width, alignment: alignment)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
    }

    private func financeLedgerMenuCell(title: String, width: CGFloat, options: [String], onSelect: @escaping (String) -> Void) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button(option.replacingOccurrences(of: "_", with: " ").capitalized) {
                    onSelect(option)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(.caption)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(width: width, alignment: .leading)
            .padding(.horizontal, 8)
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
    }

    private func financeLedgerTagCell(_ row: NJFinanceTransaction, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            TextField("tags", text: financeInlineTagBinding(for: row), prompt: Text("zhou zhou"))
                .textFieldStyle(.roundedBorder)
                .font(.caption)
                .onSubmit {
                    commitFinanceTagDraft(for: row)
                }
            Button {
                commitFinanceTagDraft(for: row)
            } label: {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .frame(width: width, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private func financeRangeTitle() -> String {
        let range = financeSelectedDateRange()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return "\(formatter.string(from: range.start)) - \(formatter.string(from: range.end))"
    }

    private func financeSelectedDateRange() -> (start: Date, end: Date) {
        let baseDate = selectedDate
        switch financeSpendingWindow {
        case .week:
            let interval = calendar.dateInterval(of: .weekOfYear, for: baseDate) ?? DateInterval(start: calendar.startOfDay(for: baseDate), duration: 86_400)
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .month:
            let interval = calendar.dateInterval(of: .month, for: baseDate) ?? DateInterval(start: calendar.startOfDay(for: baseDate), duration: 86_400)
            return (interval.start, interval.end.addingTimeInterval(-1))
        case .custom:
            let start = calendar.startOfDay(for: min(financeCustomRangeStart, financeCustomRangeEnd))
            let endDay = calendar.startOfDay(for: max(financeCustomRangeStart, financeCustomRangeEnd))
            let end = calendar.date(byAdding: .day, value: 1, to: endDay)?.addingTimeInterval(-1) ?? endDay
            return (start, end)
        }
    }

    private func financeComparisonPeriods() -> (currentRange: (start: Date, end: Date), previousRange: (start: Date, end: Date), currentLabel: String, previousLabel: String) {
        let currentRange = financeSelectedDateRange()
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .short

        let previousRange: (start: Date, end: Date)
        switch financeSpendingWindow {
        case .week:
            let previousStart = calendar.date(byAdding: .day, value: -7, to: currentRange.start) ?? currentRange.start
            let previousEnd = calendar.date(byAdding: .day, value: -7, to: currentRange.end) ?? currentRange.end
            previousRange = (previousStart, previousEnd)
        case .month:
            let priorDate = calendar.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate
            let interval = calendar.dateInterval(of: .month, for: priorDate) ?? DateInterval(start: priorDate, duration: 86_400)
            previousRange = (interval.start, interval.end.addingTimeInterval(-1))
        case .custom:
            let span = max(1, calendar.dateComponents([.day], from: currentRange.start, to: currentRange.end).day ?? 0) + 1
            let previousEnd = calendar.date(byAdding: .day, value: -1, to: currentRange.start) ?? currentRange.start
            let previousStart = calendar.date(byAdding: .day, value: -(span - 1), to: calendar.startOfDay(for: previousEnd)) ?? previousEnd
            let adjustedEnd = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: previousEnd))?.addingTimeInterval(-1) ?? previousEnd
            previousRange = (previousStart, adjustedEnd)
        }

        return (
            currentRange: currentRange,
            previousRange: previousRange,
            currentLabel: "\(formatter.string(from: currentRange.start))-\(formatter.string(from: currentRange.end))",
            previousLabel: "\(formatter.string(from: previousRange.start))-\(formatter.string(from: previousRange.end))"
        )
    }

    private func financeRows(_ row: NJFinanceTransaction, inside range: (start: Date, end: Date)) -> Bool {
        let date = Date(timeIntervalSince1970: TimeInterval(row.occurredAtMs) / 1000.0)
        return date >= range.start && date <= range.end
    }

    private func financeRows(in rows: [NJFinanceTransaction], matching range: (start: Date, end: Date)) -> [NJFinanceTransaction] {
        rows.filter { financeRows($0, inside: range) }
    }

    private func financeMetrics(rows: [NJFinanceTransaction]) -> (expenseMinor: Int64, refundMinor: Int64, incomeMinor: Int64, netMinor: Int64) {
        let grossExpenseMinor = rows.reduce(Int64(0)) { partial, row in
            row.analysisNature == "expense" ? partial + row.amountCNYMinor : partial
        }
        let refundMinor = rows.reduce(Int64(0)) { partial, row in
            row.analysisNature == "refund" ? partial + row.amountCNYMinor : partial
        }
        let expenseMinor = max(0, grossExpenseMinor - refundMinor)
        let incomeMinor = rows.reduce(Int64(0)) { partial, row in
            row.analysisNature == "income" ? partial + row.amountCNYMinor : partial
        }
        return (expenseMinor, refundMinor, incomeMinor, incomeMinor - expenseMinor)
    }

    private func financeDateRangeContains(_ occurredAtMs: Int64) -> Bool {
        let range = financeSelectedDateRange()
        let date = Date(timeIntervalSince1970: TimeInterval(occurredAtMs) / 1000.0)
        return date >= range.start && date <= range.end
    }

    private func normalizedFinanceCategory(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Other" }
        return trimmed.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func financeTags(for row: NJFinanceTransaction) -> [String] {
        row.tagText
            .split { $0 == "," || $0 == "\n" || $0 == ";" }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func financeCategorySlices(rows: [NJFinanceTransaction]) -> [NJFinanceCategorySlice] {
        var totalsByCategory: [String: Int64] = [:]
        for row in rows where row.amountCNYMinor > 0 {
            switch row.analysisNature {
            case "expense":
                let category = financeAnalysisCategory(for: row, within: rows)
                totalsByCategory[category, default: 0] += row.amountCNYMinor
            case "refund":
                let category = financeAnalysisCategory(for: row, within: rows)
                totalsByCategory[category, default: 0] -= row.amountCNYMinor
            default:
                continue
            }
        }

        return totalsByCategory
            .filter { $0.value > 0 }
            .map { NJFinanceCategorySlice(category: $0.key, total: $0.value) }
            .sorted { $0.total > $1.total }
    }

    private func financeCategory(forAngle angle: Double?, slices: [NJFinanceCategorySlice]) -> String? {
        guard let angle else { return financeSelectedCategory }
        var cumulative = 0.0
        for slice in slices {
            cumulative += Double(slice.total)
            if angle <= cumulative {
                return slice.category
            }
        }
        return nil
    }

    private func financeMetricCard(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(UIColor.systemBackground).opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func financeTransactionRow(_ row: NJFinanceTransaction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.merchantName.isEmpty ? fallbackTransactionTitle(row) : row.merchantName)
                        .font(.body.weight(.medium))
                    Text(transactionMetaText(row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(financeAmountText(row))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(financeAmountColor(row))
                    Text(financeAmountText(totalMinor: signedCNYMinor(row), currencyCode: "CNY"))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            if !row.details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(row.details)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
            if !row.itemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               row.itemName != row.merchantName {
                Text(row.itemName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack {
                Text(row.analysisNature.capitalized)
                Text(row.category.replacingOccurrences(of: "_", with: " ").capitalized)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            if !financeTags(for: row).isEmpty {
                Text(financeTags(for: row).joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.green)
            }
        }
        .padding(12)
        .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture {
            financeTransactionEditorTarget = NJFinanceTransactionEditorTarget(transactionID: row.transactionID)
        }
    }

    private func financeDayTotalText(_ rows: [NJFinanceTransaction]) -> String {
        let totalMinor = rows.reduce(Int64(0)) { partial, row in
            switch row.analysisNature {
            case "income", "refund":
                return partial + row.amountCNYMinor
            default:
                return partial - row.amountCNYMinor
            }
        }
        return financeAmountText(totalMinor: totalMinor, currencyCode: "CNY")
    }

    private func financeAmountText(_ row: NJFinanceTransaction) -> String {
        let sign = (row.analysisNature == "income" || row.analysisNature == "refund") ? 1 : -1
        return financeAmountText(totalMinor: row.amountMinor * Int64(sign), currencyCode: row.currencyCode)
    }

    private func financeAmountText(totalMinor: Int64, currencyCode: String) -> String {
        let amount = Decimal(totalMinor) / Decimal(100)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "CNY" : currencyCode
        formatter.locale = Locale.current
        return formatter.string(from: amount as NSDecimalNumber) ?? "\(amount)"
    }

    private func financeAmountColor(_ row: NJFinanceTransaction) -> Color {
        switch row.analysisNature {
        case "income":
            return .green
        case "refund":
            return .blue
        default:
            return .primary
        }
    }

    private func transactionMetaText(_ row: NJFinanceTransaction) -> String {
        let time = timeTextFromMs(row.occurredAtMs)
        let source = row.sourceType.replacingOccurrences(of: "_", with: " ").capitalized
        let account = row.accountLabel.trimmingCharacters(in: .whitespacesAndNewlines)
        if account.isEmpty {
            return "\(time) • \(source) • \(row.status)"
        }
        return "\(time) • \(source) • \(account) • \(row.status)"
    }

    private func signedCNYMinor(_ row: NJFinanceTransaction) -> Int64 {
        switch row.analysisNature {
        case "income", "refund":
            return row.amountCNYMinor
        default:
            return -row.amountCNYMinor
        }
    }

    private func financeInlineTagBinding(for row: NJFinanceTransaction) -> Binding<String> {
        Binding(
            get: { financeInlineTagDrafts[row.transactionID] ?? row.tagText },
            set: { financeInlineTagDrafts[row.transactionID] = $0 }
        )
    }

    private func commitFinanceTagDraft(for row: NJFinanceTransaction) {
        let tagText = financeInlineTagDrafts[row.transactionID] ?? row.tagText
        saveFinanceTransactionEdit(row: row, tagText: tagText)
        financeInlineTagDrafts.removeValue(forKey: row.transactionID)
    }

    private func saveFinanceTransactionEdit(row: NJFinanceTransaction, analysisNature: String? = nil, category: String? = nil, tagText: String? = nil) {
        let nowMs = Int64(Date().timeIntervalSince1970 * 1000.0)
        let updated = NJFinanceTransaction(
            transactionID: row.transactionID,
            fingerprint: row.fingerprint,
            sourceType: row.sourceType,
            accountID: row.accountID,
            accountLabel: row.accountLabel,
            externalRef: row.externalRef,
            occurredAtMs: row.occurredAtMs,
            dateKey: row.dateKey,
            merchantName: row.merchantName,
            amountMinor: row.amountMinor,
            currencyCode: row.currencyCode,
            direction: row.direction,
            analysisNature: analysisNature ?? row.analysisNature,
            category: category ?? row.category,
            tagText: tagText ?? row.tagText,
            fxRateToCNY: row.fxRateToCNY,
            amountCNYMinor: row.amountCNYMinor,
            status: row.status,
            counterparty: row.counterparty,
            itemName: row.itemName,
            details: row.details,
            note: row.note,
            importBatchID: row.importBatchID,
            sourceFileName: row.sourceFileName,
            rawPayloadJSON: row.rawPayloadJSON,
            createdAtMs: row.createdAtMs,
            updatedAtMs: nowMs,
            deleted: row.deleted
        )
        store.notes.upsertFinanceTransaction(updated)
        reloadFinanceTransactions()
    }

    private func financeAnalysisCategory(for row: NJFinanceTransaction, within rows: [NJFinanceTransaction]) -> String {
        if row.analysisNature == "refund",
           let matched = matchedExpenseForRefund(row, within: rows) {
            return normalizedFinanceCategory(matched.category)
        }
        return normalizedFinanceCategory(row.category)
    }

    private func matchedExpenseForRefund(_ refund: NJFinanceTransaction, within rows: [NJFinanceTransaction]) -> NJFinanceTransaction? {
        let merchantKey = normalizedFinanceMerchantKey(refund)
        guard !merchantKey.isEmpty else { return nil }

        return rows
            .filter {
                $0.analysisNature == "expense" &&
                $0.amountCNYMinor > 0 &&
                $0.occurredAtMs <= refund.occurredAtMs &&
                normalizedFinanceMerchantKey($0) == merchantKey
            }
            .sorted { lhs, rhs in
                if lhs.occurredAtMs == rhs.occurredAtMs {
                    return lhs.updatedAtMs > rhs.updatedAtMs
                }
                return lhs.occurredAtMs > rhs.occurredAtMs
            }
            .first
    }

    private func normalizedFinanceMerchantKey(_ row: NJFinanceTransaction) -> String {
        let raw = row.merchantName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? fallbackTransactionTitle(row)
            : row.merchantName
        let lowered = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lowered.isEmpty else { return "" }

        let filteredScalars = lowered.unicodeScalars.filter { scalar in
            CharacterSet.alphanumerics.contains(scalar) || CharacterSet.whitespaces.contains(scalar)
        }
        let cleaned = String(String.UnicodeScalarView(filteredScalars))
        return cleaned
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func fallbackTransactionTitle(_ row: NJFinanceTransaction) -> String {
        let counterparty = row.counterparty.trimmingCharacters(in: .whitespacesAndNewlines)
        if !counterparty.isEmpty { return counterparty }
        let item = row.itemName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !item.isEmpty { return item }
        return row.sourceType.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func timeTextFromMs(_ value: Int64) -> String {
        guard value > 0 else { return "--:--" }
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(value) / 1000.0))
    }

    private func handleFinanceDataImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importFinanceData(from: url)
        case .failure(let error):
            presentFinanceAlert(error.localizedDescription)
        }
    }

    private func handleFinanceScreenshotImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard !urls.isEmpty else { return }
            Task { await importFinanceScreenshots(from: urls) }
        case .failure(let error):
            presentFinanceAlert(error.localizedDescription)
        }
    }

    private func importFinanceData(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }

        do {
            let data = try Data(contentsOf: url)
            let result = try NJFinanceImportService.importFile(
                data: data,
                filename: url.lastPathComponent,
                nowMs: DBNoteRepository.nowMs()
            )
            applyImportedFinanceTransactions(result.rows, importedLabel: result.summaryText)
        } catch {
            presentFinanceAlert("Import failed: \(error.localizedDescription)")
        }
    }

    private func importFinanceScreenshots(from urls: [URL]) async {
        do {
            let result = try await NJFinanceImportService.importOctopusScreenshots(
                urls: urls,
                nowMs: DBNoteRepository.nowMs()
            )
            await MainActor.run {
                applyImportedFinanceTransactions(result.rows, importedLabel: result.summaryText)
            }
        } catch {
            await MainActor.run {
                presentFinanceAlert("Screenshot import failed: \(error.localizedDescription)")
            }
        }
    }

    private func applyImportedFinanceTransactions(_ rows: [NJFinanceTransaction], importedLabel: String) {
        guard !rows.isEmpty else {
            presentFinanceAlert("No new transactions were found.")
            return
        }
        for row in rows {
            if let existing = store.notes.financeTransactionByFingerprint(row.fingerprint) {
                store.notes.upsertFinanceTransaction(
                    NJFinanceTransaction(
                        transactionID: existing.transactionID,
                        fingerprint: row.fingerprint,
                        sourceType: row.sourceType,
                        accountID: row.accountID,
                        accountLabel: row.accountLabel,
                        externalRef: row.externalRef,
                        occurredAtMs: row.occurredAtMs,
                        dateKey: row.dateKey,
                        merchantName: row.merchantName,
                        amountMinor: row.amountMinor,
                        currencyCode: row.currencyCode,
                        direction: row.direction,
                        analysisNature: existing.analysisNature.isEmpty ? row.analysisNature : existing.analysisNature,
                        category: existing.category.isEmpty ? row.category : existing.category,
                        tagText: existing.tagText,
                        fxRateToCNY: existing.fxRateToCNY == 0 ? row.fxRateToCNY : existing.fxRateToCNY,
                        amountCNYMinor: existing.fxRateToCNY == 0 ? row.amountCNYMinor : Int64((Double(row.amountMinor) * existing.fxRateToCNY).rounded()),
                        status: row.status,
                        counterparty: row.counterparty,
                        itemName: row.itemName,
                        details: existing.details,
                        note: row.note,
                        importBatchID: row.importBatchID,
                        sourceFileName: row.sourceFileName,
                        rawPayloadJSON: row.rawPayloadJSON,
                        createdAtMs: existing.createdAtMs == 0 ? row.createdAtMs : existing.createdAtMs,
                        updatedAtMs: row.updatedAtMs,
                        deleted: 0
                    )
                )
            } else {
                store.notes.upsertFinanceTransaction(row)
            }
        }
        store.sync.schedulePush(debounceMs: 0)
        reloadFinanceTransactions()
        presentFinanceAlert(importedLabel)
    }

    private func financePreviewLines(for brief: NJFinanceDailyBrief) -> [String] {
        [
            brief.newsSummary,
            brief.expectationSummary,
            brief.watchItems
        ]
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
    }

    private func financeMonthPreviewRows(events: [NJFinanceMacroEvent], brief: NJFinanceDailyBrief?) -> [String] {
        var rows: [String] = []
        if let bias = brief?.bias.trimmingCharacters(in: .whitespacesAndNewlines), !bias.isEmpty {
            rows.append(bias)
        }
        for event in events {
            let title = normalizedMarketSnapshotTitle(event.title).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            rows.append("\(eventTimeLabel(event.timeText)) \(title)")
        }
        if let brief {
            rows.append(contentsOf: financePreviewLines(for: brief))
        }
        return rows
    }

    private func eventTimeLabel(_ timeText: String) -> String {
        let trimmed = timeText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "TBD" : trimmed
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
          AND type IN ('sleep', 'workout', 'blood_pressure_systolic', 'blood_pressure_diastolic', 'weight', 'bmi', 'height', 'body_fat_percentage', 'lean_body_mass', 'waist_circumference', 'medication_dose', 'medication_record')
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
            case "weight":
                day.weightKgSum += value
                day.weightKgCount += 1
            case "bmi":
                day.bmiSum += value
                day.bmiCount += 1
            case "height":
                day.heightMSum += value
                day.heightMCount += 1
            case "body_fat_percentage":
                day.bodyFatRawSum += value
                day.bodyFatCount += 1
            case "lean_body_mass":
                day.leanMassKgSum += value
                day.leanMassKgCount += 1
            case "waist_circumference":
                day.waistMSum += value
                day.waistMCount += 1
            case "medication_dose", "medication_record":
                day.medDoseCount += 1
            default:
                break
            }
            out[key] = day
        }
        healthByDate = out

        let heightSQL = """
        SELECT value_num
        FROM health_samples
        WHERE type = 'height'
          AND start_ms < \(endMs)
        ORDER BY start_ms DESC
        LIMIT 1;
        """
        if let raw = store.db.queryRows(heightSQL).first?["value_num"],
           let m = Double(raw), m > 0 {
            latestHeightMForVisibleRange = m
        } else {
            latestHeightMForVisibleRange = nil
        }
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
        case .hiking: return "Hiking"
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
        return n.contains("run") || n.contains("jog") || n.contains("cycl") || n.contains("bike") || n.contains("hik")
    }

    private func activityIcon(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("cycl") || n.contains("bike") { return "bicycle" }
        if n.contains("run") || n.contains("jog") { return "figure.run" }
        if n.contains("hik") { return "figure.hiking" }
        if n.contains("walk") { return "figure.walk" }
        if n.contains("swim") { return "figure.pool.swim" }
        if n.contains("tennis") { return "sportscourt" }
        if n.contains("strength") || n.contains("gym") { return "dumbbell" }
        return "figure.mixed.cardio"
    }

    private func normalizedMarketSnapshotTitle(_ title: String) -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.uppercased().hasPrefix("US10Y ") else { return trimmed }

        let parts = trimmed.split(separator: " ", maxSplits: 2).map(String.init)
        guard parts.count >= 2 else { return trimmed }
        let rawValue = parts[1]
            .replacingOccurrences(of: "%", with: "")
            .replacingOccurrences(of: ",", with: "")
        guard let value = Double(rawValue) else { return trimmed }

        let corrected = value < 1 ? value * 10 : value
        let rest = parts.count > 2 ? " \(parts[2])" : ""
        return String(format: "US10Y %.2f%%%@", corrected, rest)
    }

    @ViewBuilder
    private func financeResearchWorkspaceView() -> some View {
        let issues = financeIssueTabs()
        let activeIssue = issues.first(where: { $0.premiseID == selectedFinanceIssueID }) ?? issues.first
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(issues) { issue in
                        Button {
                            selectedFinanceIssueID = issue.premiseID
                        } label: {
                            Text(issue.title)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedFinanceIssueID == issue.premiseID ? Color.accentColor.opacity(0.18) : Color(UIColor.secondarySystemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            if let activeIssue {
                let session = financeResearchSessions[activeIssue.sessionID]
                let messages = financeResearchMessages[activeIssue.sessionID] ?? []
                let tasks = financeResearchTasks[activeIssue.sessionID] ?? []
                let findings = financeFindingsByPremise[activeIssue.premiseID] ?? []
                let sourceItems = financeSourceItemsByPremise[activeIssue.premiseID] ?? []

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(activeIssue.title)
                                .font(.headline)
                            Text(session?.summary.isEmpty == false ? (session?.summary ?? "") : activeIssue.promptHint)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }

                        if !tasks.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Open Tasks")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(Array(tasks.prefix(3)), id: \.taskID) { task in
                                    Text("\(task.status.uppercased()) · \(task.instruction)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }

                        if !findings.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Latest Findings")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(Array(findings.prefix(5)), id: \.findingID) { finding in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(finding.stance.uppercased())
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(finding.stance == "supports" ? .green : (finding.stance == "refutes" ? .red : .orange))
                                            Spacer(minLength: 0)
                                            Button("Save to Journal") {
                                                exportFinanceFindingToJournal(issue: activeIssue, finding: finding)
                                            }
                                            .font(.caption2.weight(.semibold))
                                            .buttonStyle(.plain)
                                        }
                                        Text(finding.summary)
                                            .font(.callout)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }

                        if !sourceItems.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Recent Sources")
                                    .font(.subheadline.weight(.semibold))
                                ForEach(Array(sourceItems.prefix(5)), id: \.sourceItemID) { item in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(item.sourceName)
                                            .font(.caption.weight(.semibold))
                                        Text(item.rawExcerpt.isEmpty ? item.sourceURL : item.rawExcerpt)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(3)
                                    }
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Dialogue")
                                .font(.subheadline.weight(.semibold))
                            if messages.isEmpty {
                                Text("No research thread yet.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(messages, id: \.messageID) { message in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack(alignment: .top, spacing: 8) {
                                            Text(message.role == "user" ? "You" : "Qwen")
                                                .font(.caption2.weight(.semibold))
                                                .foregroundStyle(message.role == "user" ? .blue : .orange)
                                            Spacer(minLength: 0)
                                            if message.role == "assistant" {
                                                Button("Save to Journal") {
                                                    exportFinanceResearchMessageToJournal(issue: activeIssue, message: message)
                                                }
                                                .font(.caption2.weight(.semibold))
                                                .buttonStyle(.plain)
                                            }
                                        }
                                        Text(message.body)
                                            .font(.callout)
                                    }
                                    .padding(10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color(UIColor.secondarySystemBackground))
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                }
                            }
                        }
                    }
                    .padding(12)
                }

                VStack(spacing: 8) {
                    TextField(activeIssue.promptHint, text: $financeDraftMessage, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                    HStack {
                        Button("Queue Research") {
                            sendFinanceResearchMessage(for: activeIssue)
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }
                .padding(12)
                .background(Color(UIColor.systemBackground))
            }
        }
    }

    @ViewBuilder
    private func contentSummaryView(date: Date, isWeekly: Bool) -> some View {
        switch contentMode {
        case .memory:
            EmptyView()
        case .health:
            healthSummaryView(date: date, isWeekly: isWeekly)
        case .quickLog:
            quickLogSummaryView(date: date, isWeekly: isWeekly)
        case .finance:
            financeSummaryView(date: date, isWeekly: isWeekly)
        }
    }

    @ViewBuilder
    private func financeSummaryView(date: Date, isWeekly: Bool) -> some View {
        let key = dateKey(date)
        let events = (financeEventsByDate[key] ?? []).sorted { ($0.timeText, $0.title) < ($1.timeText, $1.title) }
        let brief = financeBriefsByDate[key]

        if isWeekly {
            VStack(alignment: .leading, spacing: 3) {
                if let bias = brief?.bias.trimmingCharacters(in: .whitespacesAndNewlines), !bias.isEmpty {
                    Text(bias)
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
                if !events.isEmpty {
                    ForEach(Array(events.prefix(3)), id: \.eventID) { event in
                        HStack(spacing: 4) {
                            Text(eventTimeLabel(event.timeText))
                            Text(event.title)
                            Spacer(minLength: 0)
                            if !event.impact.isEmpty {
                                Text(event.impact.uppercased())
                            }
                        }
                        .font(.system(size: 9))
                        .lineLimit(1)
                    }
                }
                if let brief {
                    ForEach(financePreviewLines(for: brief).prefix(3), id: \.self) { line in
                        Text(line)
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                } else if events.isEmpty {
                    Text("No finance brief")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            let previewRows = financeMonthPreviewRows(events: events, brief: brief)
            let visibleRows = Array(previewRows.prefix(5))
            let overflowCount = max(0, previewRows.count - visibleRows.count)
            let biasText = brief?.bias.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            VStack(alignment: .leading, spacing: 1) {
                if visibleRows.isEmpty {
                    Text("No macro")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(visibleRows.enumerated()), id: \.offset) { idx, line in
                        Text(line)
                            .font(.system(size: 8, weight: idx == 0 && !biasText.isEmpty ? .semibold : .regular))
                            .foregroundStyle(idx == 0 && !biasText.isEmpty ? .orange : .secondary)
                            .lineLimit(1)
                    }
                }
                if overflowCount > 0 {
                    Text("+\(overflowCount) more")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private func quickLogSummaryView(date: Date, isWeekly: Bool) -> some View {
        let key = dateKey(date)
        let slots = (timeLogsByDate[key] ?? []).sorted { $0.startAtMs < $1.startAtMs }
        let grouped = Dictionary(grouping: slots) { ($0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? prettyTimeCategory($0.category) : $0.title) }
        let rows = grouped.map { (name: $0.key, durationMin: $0.value.reduce(0.0) { $0 + Double(max(0, $1.endAtMs - $1.startAtMs)) / 60000.0 }) }
            .sorted { lhs, rhs in
                if lhs.durationMin == rhs.durationMin { return lhs.name < rhs.name }
                return lhs.durationMin > rhs.durationMin
            }
        let totalMin = rows.reduce(0.0) { $0 + $1.durationMin }

        if isWeekly {
            VStack(alignment: .leading, spacing: 3) {
                if rows.isEmpty {
                    Text("No quick logs")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 4) {
                        Image(systemName: "clock.badge")
                        Text("Total \(fmtNum(totalMin))m")
                    }
                    .font(.system(size: 9))
                    ForEach(Array(rows.prefix(4)), id: \.name) { row in
                        HStack(spacing: 4) {
                            Text(timeLogEmoji(row.name))
                            Text(row.name)
                            Spacer(minLength: 0)
                            Text("\(fmtNum(row.durationMin))m")
                        }
                        .font(.system(size: 9))
                        .lineLimit(1)
                    }
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 1) {
                if rows.isEmpty {
                    Text("No log")
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 3) {
                        Image(systemName: "clock.badge")
                        Text("\(fmtNum(totalMin))m")
                    }
                    .font(.system(size: 8))
                    ForEach(Array(rows.prefix(3)), id: \.name) { row in
                        HStack(spacing: 3) {
                            Text(timeLogEmoji(row.name))
                            Text(row.name)
                            Spacer(minLength: 0)
                            Text("\(fmtNum(row.durationMin))m")
                        }
                        .font(.system(size: 8))
                        .lineLimit(1)
                    }
                }
            }
        }
    }

    private func prettyTimeCategory(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Personal" }
        return trimmed.capitalized
    }

    private func timeLogEmoji(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("reading") { return "📚" }
        if n.contains("play") { return "🧸" }
        if n.contains("piano") || n.contains("canon") || n.contains("rhapsody") { return "🎹" }
        if n.contains("ukulele") { return "🎸" }
        return "⏱️"
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
        let effectiveHeightM = day.avgHeightM ?? latestHeightMForVisibleRange
        let effectiveBMI: Double? = {
            if let bmi = day.avgBMI { return bmi }
            if let w = day.avgWeightKg, let h = effectiveHeightM, h > 0 { return w / (h * h) }
            return nil
        }()

        if isWeekly {
            VStack(alignment: .leading, spacing: 2) {
                if !plans.isEmpty {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(plans.prefix(3), id: \.planID) { p in
                            Button {
                                trainingEditTarget = NJTrainingEditTarget(plan: p)
                            } label: {
                                HStack(spacing: 3) {
                                    Image(systemName: "calendar.badge.plus")
                                    Text(planSummaryText(p))
                                    Spacer(minLength: 0)
                                    Image(systemName: "pencil")
                                        .font(.system(size: 8, weight: .semibold))
                                }
                                .font(.system(size: 9))
                                .foregroundStyle(.orange)
                                .lineLimit(1)
                            }
                            .buttonStyle(.plain)
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
                if let w = day.avgWeightKg {
                    HStack(spacing: 4) {
                        Image(systemName: "scalemass")
                        Text("Wt \(fmtNum(w)) kg")
                        if let bmi = effectiveBMI {
                            Text("BMI \(fmtNum(bmi))")
                        }
                    }
                    .font(.system(size: 9))
                } else if let bmi = effectiveBMI {
                    HStack(spacing: 4) {
                        Image(systemName: "figure")
                        Text("BMI \(fmtNum(bmi))")
                    }
                    .font(.system(size: 9))
                }
                if day.avgBodyFatPercent != nil || day.avgLeanMassKg != nil || day.avgWaistCm != nil {
                    HStack(spacing: 4) {
                        Image(systemName: "figure.arms.open")
                        if let bf = day.avgBodyFatPercent {
                            Text("Fat \(fmtNum(bf))%")
                        }
                        if let fatKg = day.derivedFatMassKg {
                            Text("(\(fmtNum(fatKg))kg)")
                        }
                        if let lean = day.avgLeanMassKg {
                            Text("Lean \(fmtNum(lean))kg")
                        }
                        if let waist = day.avgWaistCm {
                            Text("Waist \(fmtNum(waist))cm")
                        }
                    }
                    .font(.system(size: 9))
                    .lineLimit(1)
                }
            }
        } else {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 1) {
                    if let first = plans.first {
                        Button {
                            trainingEditTarget = NJTrainingEditTarget(plan: first)
                        } label: {
                            HStack(spacing: 3) {
                                Image(systemName: "calendar.badge.plus")
                                Text(planSummaryText(first))
                                Spacer(minLength: 0)
                                Image(systemName: "pencil")
                                    .font(.system(size: 7, weight: .semibold))
                            }
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                            .lineLimit(1)
                        }
                        .buttonStyle(.plain)
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
                    if let w = day.avgWeightKg {
                        HStack(spacing: 3) {
                            Image(systemName: "scalemass")
                            Text("\(fmtNum(w))kg")
                            if let bmi = effectiveBMI {
                                Text("b\(fmtNum(bmi))")
                            }
                        }
                        .font(.system(size: 8))
                    } else if let bmi = effectiveBMI {
                        HStack(spacing: 3) {
                            Image(systemName: "figure")
                            Text("b\(fmtNum(bmi))")
                        }
                        .font(.system(size: 8))
                    }
                    if let bf = day.avgBodyFatPercent {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.arms.open")
                            Text("f\(fmtNum(bf))%")
                            if let lean = day.avgLeanMassKg {
                                Text("l\(fmtNum(lean))")
                            }
                        }
                        .font(.system(size: 8))
                        .lineLimit(1)
                    } else if let lean = day.avgLeanMassKg {
                        HStack(spacing: 3) {
                            Image(systemName: "figure.arms.open")
                            Text("l\(fmtNum(lean))kg")
                        }
                        .font(.system(size: 8))
                    }
                }
            }
        }
    }

    private func planSummaryText(_ plan: NJPlannedExercise) -> String {
        let title = plan.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? plan.sport : plan.title
        let distance = plan.targetDistanceKm > 0 ? "\(fmtNum(plan.targetDistanceKm))km" : nil
        let duration = plan.targetDurationMin > 0 ? "\(fmtNum(plan.targetDurationMin))m" : nil
        let metrics = [distance, duration].compactMap { $0 }.joined(separator: " / ")
        let base = metrics.isEmpty ? title : "\(title) \(metrics)"
        if let matched = matchedTrainingResultByPlanID[plan.planID], matched.status?.lowercased() != "skipped" {
            let actualBits = [
                matched.distanceKm > 0 ? "\(fmtNum(matched.distanceKm))km" : nil,
                matched.durationMin > 0 ? "\(fmtNum(matched.durationMin))m" : nil
            ].compactMap { $0 }.joined(separator: " / ")
            return actualBits.isEmpty ? "\(base) ✓" : "\(base) ✓ \(actualBits)"
        }
        return base
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
        if FileManager.default.fileExists(atPath: url.path) {
            store.notes.backfillCalendarThumbPath(attachmentID: attachmentID, thumbPath: url.path)
            DispatchQueue.main.async {
                guard var item = itemsByDate[dateKey] else { return }
                if item.photoThumbPath.isEmpty || !FileManager.default.fileExists(atPath: item.photoThumbPath) {
                    item.photoThumbPath = url.path
                    itemsByDate[dateKey] = item
                }
            }
            return
        }
        if let att = store.notes.attachmentByID(attachmentID),
           !att.thumbPath.isEmpty,
           FileManager.default.fileExists(atPath: att.thumbPath) {
            store.notes.backfillCalendarThumbPath(attachmentID: attachmentID, thumbPath: att.thumbPath)
            DispatchQueue.main.async {
                guard var item = itemsByDate[dateKey] else { return }
                if item.photoThumbPath.isEmpty || !FileManager.default.fileExists(atPath: item.photoThumbPath) {
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
                if (item.photoThumbPath.isEmpty || !FileManager.default.fileExists(atPath: item.photoThumbPath)),
                   FileManager.default.fileExists(atPath: path) {
                    store.notes.backfillCalendarThumbPath(attachmentID: attachmentID, thumbPath: path)
                    item.photoThumbPath = path
                    itemsByDate[dateKey] = item
                }
            }
        }
    }

    private func weeklyHeaderBlock() -> some View {
        return VStack(alignment: .leading, spacing: 10) {
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
                    Text(weekRangeTitle(for: focusedDate))
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

                        Button {
                            openWeekPlanningClipboardPreview(for: focusedDate)
                        } label: {
                            Image(systemName: "doc.on.clipboard")
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

    private func weekRangeTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "MMM d"
        let interval = calendar.dateInterval(of: .weekOfYear, for: date)
        guard let start = interval?.start,
              let end = interval?.end,
              let endDate = calendar.date(byAdding: .day, value: -1, to: end) else {
            return formatter.string(from: date)
        }
        return "\(formatter.string(from: start))  –  \(formatter.string(from: endDate))"
    }

    private func weeklyPlanningPreviewLines(for date: Date) -> [String] {
        let key = weekPlanningTargetKey(for: date)
        guard let row = store.notes.planningNote(kind: "weekly", targetKey: key) else { return [] }
        let protonLines = summaryLineItems(from: attributedTextFromProtonJSON(row.protonJSON))
        if !protonLines.isEmpty { return protonLines }

        let plainLines = row.note
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(plainLines.prefix(6))
    }

    private func dayPlanningPreviewLines(for date: Date) -> [String] {
        let key = dateKey(date)
        guard let row = store.notes.planningNote(kind: "daily", targetKey: key) else { return [] }
        let protonLines = summaryLineItems(from: attributedTextFromProtonJSON(row.protonJSON))
        if !protonLines.isEmpty { return protonLines }

        let plainLines = row.note
            .split(whereSeparator: \.isNewline)
            .map(String.init)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return Array(plainLines.prefix(6))
    }

    private func weekRange(for date: Date) -> (Date, Date)? {
        guard let iv = calendar.dateInterval(of: .weekOfYear, for: date) else { return nil }
        return (iv.start, iv.end)
    }

    private func loadWeeklyWorkoutEntries() -> [NJWeeklyWorkoutEntry] {
        guard let (start, end) = weekRange(for: focusedDate) else { return [] }
        return loadWorkoutEntries(start: start, endExclusive: end)
    }

    private func deleteWorkoutEntry(_ entry: NJWeeklyWorkoutEntry) -> (ok: Bool, message: String) {
        guard entry.kind == .actual else {
            return (false, "Only actual workouts can be deleted.")
        }
        guard entry.canDeleteFromNotionJournal else {
            return (false, "Only Notion Journal workouts can be deleted here.")
        }
        #if canImport(HealthKit)
        guard let uuid = UUID(uuidString: entry.id) else {
            return (false, "Invalid workout identifier.")
        }
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Bool, String) = (false, "Workout not found in HealthKit.")
        let store = HKHealthStore()
        let predicate = HKQuery.predicateForObject(with: uuid)
        let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: 1, sortDescriptors: nil) { _, samples, error in
            if let error {
                result = (false, error.localizedDescription)
                semaphore.signal()
                return
            }
            guard let workout = samples?.first as? HKWorkout else {
                semaphore.signal()
                return
            }
            store.delete(workout) { ok, err in
                if let err {
                    result = (false, err.localizedDescription)
                } else if ok {
                    self.store.db.exec("DELETE FROM health_samples WHERE sample_id = '\(entry.id.replacingOccurrences(of: "'", with: "''"))';")
                    DispatchQueue.main.async {
                        self.reloadAll()
                    }
                    result = (true, "Workout deleted.")
                } else {
                    result = (false, "Delete failed.")
                }
                semaphore.signal()
            }
        }
        store.execute(query)
        semaphore.wait()
        return result
        #else
        return (false, "HealthKit deletion is unavailable on this platform.")
        #endif
    }

    private func loadWorkoutEntries(start: Date, endExclusive: Date) -> [NJWeeklyWorkoutEntry] {
        let startMs = Int64(start.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000.0)

        let sql = """
        SELECT sample_id, start_ms, end_ms, value_num, value_str, metadata_json, source
        FROM health_samples
        WHERE type = 'workout'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs)
        ORDER BY start_ms DESC;
        """
        let rows = store.db.queryRows(sql)
        var out: [NJWeeklyWorkoutEntry] = []

        for r in rows {
            let sMs = Int64(r["start_ms"] ?? "") ?? 0
            let eMs = Int64(r["end_ms"] ?? "") ?? sMs
            let startDate = Date(timeIntervalSince1970: TimeInterval(sMs) / 1000.0)
            let endDate = Date(timeIntervalSince1970: TimeInterval(eMs) / 1000.0)
            let metadata = parseJSONDict(r["metadata_json"] ?? "")
            let distanceKm = ((metadata["distance_m"] as? NSNumber)?.doubleValue ?? 0) / 1000.0
            let durationMinFromValue = (Double(r["value_num"] ?? "") ?? 0) / 60.0
            let durationMin = durationMinFromValue > 0 ? durationMinFromValue : max(0, endDate.timeIntervalSince(startDate) / 60.0)
            let sport = normalizedActivityName(valueStr: r["value_str"] ?? "", metadata: metadata)
            out.append(
                NJWeeklyWorkoutEntry(
                    id: r["sample_id"] ?? UUID().uuidString.lowercased(),
                    sport: sport,
                    startDate: startDate,
                    endDate: endDate,
                    durationMin: durationMin,
                    distanceKm: distanceKm,
                    source: r["source"] ?? "HealthKit",
                    kind: .actual
                )
            )
        }

        return out.sorted { $0.startDate > $1.startDate }
    }

    private func recomputeMatchedTrainingResults(start: Date, end: Date) {
        let plans = store.notes.listPlannedExercises(startKey: dateKey(start), endKey: dateKey(end))
            .filter { $0.deleted == 0 }
            .sorted { ($0.dateKey, $0.title, $0.planID) < ($1.dateKey, $1.title, $1.planID) }
        let actuals = loadWorkoutEntries(start: start, endExclusive: calendar.date(byAdding: .day, value: 1, to: end) ?? end)
        let manualResults = loadTrainingRuntimeResults(start: start, end: end)
        matchedTrainingResultByPlanID = autoMatchedTrainingResults(plans: plans, actuals: actuals, manualResults: manualResults)
    }

    private func autoMatchedTrainingResults(
        plans: [NJPlannedExercise],
        actuals: [NJWeeklyWorkoutEntry],
        manualResults: [NJCalendarTrainingResult]
    ) -> [String: NJCalendarTrainingResult] {
        var out: [String: NJCalendarTrainingResult] = [:]
        var usedActualIDs = Set<String>()

        for result in manualResults {
            out[result.sessionID] = result
        }

        let dateFormatter = ISO8601DateFormatter()

        for plan in plans {
            if out[plan.planID] != nil { continue }
            let planDate = plan.dateKey
            let planSport = canonicalTrainingSport(plan.sport)

            let candidates = actuals.compactMap { actual -> (NJWeeklyWorkoutEntry, Double)? in
                guard dateKey(actual.startDate) == planDate else { return nil }
                let actualSport = canonicalTrainingSport(actual.sport)
                let sportScore = sportMatchScore(planSport: planSport, actualSport: actualSport)
                guard sportScore > 0 else { return nil }

                var score = sportScore
                if plan.targetDurationMin > 0 {
                    score -= min(20, abs(plan.targetDurationMin - actual.durationMin))
                }
                if plan.targetDistanceKm > 0, actual.distanceKm > 0 {
                    score -= min(20, abs(plan.targetDistanceKm - actual.distanceKm) * 4.0)
                }
                if actual.startDate <= Date() {
                    score += 5
                }
                return score > 0 ? (actual, score) : nil
            }
            .filter { !usedActualIDs.contains($0.0.id) }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
                return lhs.0.startDate < rhs.0.startDate
            }

            guard let best = candidates.first else { continue }
            usedActualIDs.insert(best.0.id)
            out[plan.planID] = NJCalendarTrainingResult(
                resultID: "healthkit_match_\(best.0.id)",
                sessionID: plan.planID,
                dateKey: plan.dateKey,
                title: plan.title.isEmpty ? plan.sport : plan.title,
                sport: plan.sport,
                category: plan.category,
                sessionType: plan.sessionType,
                startedAtMs: Int64(best.0.startDate.timeIntervalSince1970 * 1000.0),
                endedAtMs: Int64(best.0.endDate.timeIntervalSince1970 * 1000.0),
                durationMin: best.0.durationMin,
                distanceKm: best.0.distanceKm,
                avgHeartRateBpm: nil,
                avgPaceMinPerKm: best.0.paceMinPerKm,
                source: "apple_workout_match",
                status: "completed",
                notes: "Matched automatically from Apple Workout at \(dateFormatter.string(from: best.0.startDate))"
            )
        }

        return out
    }

    private func sportMatchScore(planSport: String, actualSport: String) -> Double {
        if planSport == actualSport { return 100 }
        let aliases: [String: Set<String>] = [
            "running": ["jogging", "run", "running"],
            "jogging": ["run", "running", "jogging"],
            "cycling": ["bike", "biking", "cycling"],
            "biking": ["bike", "cycling", "biking"],
            "swimming": ["swim", "swimming"],
            "walking": ["walk", "walking"],
            "hiking": ["hike", "hiking"],
            "tennis": ["tennis"],
            "core": ["core"],
            "strength": ["strength", "functional_strength_training", "traditional_strength_training"]
        ]
        for (_, values) in aliases {
            if values.contains(planSport), values.contains(actualSport) {
                return 80
            }
        }
        if planSport.contains(actualSport) || actualSport.contains(planSport) {
            return 60
        }
        return 0
    }

    private func handleTrainingPlanImport(result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            importTrainingPlan(from: url)
        case .failure(let error):
            showTrainingMessage(error.localizedDescription)
        }
    }

    private func importTrainingPlan(from url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer {
            if scoped { url.stopAccessingSecurityScopedResource() }
        }
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let doc = try decoder.decode(NJTrainingPlanFile.self, from: data)
            try applyTrainingPlan(doc)
        } catch {
            showTrainingMessage("Import failed: \(error.localizedDescription)")
        }
    }

    private func applyTrainingPlan(_ doc: NJTrainingPlanFile) throws {
        guard doc.schema == "nj_training_plan_v1" else {
            throw NSError(domain: "NJTrainingPlan", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Unsupported schema \(doc.schema). Expected nj_training_plan_v1."
            ])
        }
        guard let weekStart = parseDateKey(doc.weekOf) else {
            throw NSError(domain: "NJTrainingPlan", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "week_of must be yyyy-MM-dd."
            ])
        }

        let weekKey = dateKey(weekStart)
        let weekEnd = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        let sourcePlanID = "training:\(weekKey)"
        let existing = store.notes.listPlannedExercises(startKey: weekKey, endKey: dateKey(weekEnd))
        let now = DBNoteRepository.nowMs()
        for row in existing where row.sourcePlanID == sourcePlanID {
            store.notes.deletePlannedExercise(planID: row.planID, nowMs: now)
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        for session in doc.sessions {
            guard let date = parseDateKey(session.date) else { continue }
            let dateKeyValue = dateKey(date)
            let goalsJSON = encodeJSON(session.goals ?? [], encoder: encoder)
            let cueJSON = encodeJSON(session.cueRules ?? [], encoder: encoder)
            let blockJSON = encodeJSON(session.blocks ?? [], encoder: encoder)
            let plan = NJPlannedExercise(
                planID: session.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? UUID().uuidString.lowercased() : session.id,
                dateKey: dateKeyValue,
                weekKey: weekKey,
                title: session.title,
                category: session.category,
                sport: session.sport,
                sessionType: session.sessionType ?? "",
                targetDistanceKm: session.targetDistanceKm ?? 0,
                targetDurationMin: session.durationMin ?? 0,
                notes: session.notes ?? "",
                goalJSON: goalsJSON,
                cueJSON: cueJSON,
                blockJSON: blockJSON,
                sourcePlanID: sourcePlanID,
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
            store.notes.upsertPlannedExercise(plan)
        }

        focusedDate = weekStart
        selectedDate = weekStart
        reloadItemsForVisibleRange()
        store.publishTrainingWeekSnapshotToWidget(referenceDate: weekStart)
        NJTrainingRuntime.shared.reload(referenceDate: weekStart)
        showTrainingMessage("Imported \(doc.sessions.count) training sessions for \(weekRangeTitle(for: weekStart)).")
    }

    private func exportWeeklyTrainingReview() {
        guard let (start, endExclusive) = weekRange(for: focusedDate) else { return }
        let endDate = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? start
        let weekKey = dateKey(start)
        let plans = store.notes.listPlannedExercises(startKey: weekKey, endKey: dateKey(endDate))
            .filter { $0.deleted == 0 }
            .sorted { ($0.dateKey, $0.title, $0.planID) < ($1.dateKey, $1.title, $1.planID) }

        let actuals = loadWeeklyWorkoutEntries()
        let trainingResults = loadTrainingRuntimeResults(start: start, end: endDate)
        var actualByDateSport: [String: (duration: Double, distance: Double)] = [:]
        for entry in actuals {
            let key = "\(dateKey(entry.startDate))|\(canonicalTrainingSport(entry.sport))"
            var row = actualByDateSport[key] ?? (0, 0)
            row.duration += entry.durationMin
            row.distance += entry.distanceKm
            actualByDateSport[key] = row
        }
        let resultBySessionID = autoMatchedTrainingResults(plans: plans, actuals: actuals, manualResults: trainingResults)

        var sleepHours: [Double] = []
        var weightKg: [Double] = []
        var bmiVals: [Double] = []
        var bodyFatVals: [Double] = []
        var sysVals: [Double] = []
        var diaVals: [Double] = []
        let dates = eachDate(start: start, through: endDate)
        for dayDate in dates {
            let day = healthByDate[dateKey(dayDate)] ?? NJCalendarHealthDay()
            if day.sleepHours > 0 { sleepHours.append(day.sleepHours) }
            if let w = day.avgWeightKg { weightKg.append(w) }
            if let bmi = day.avgBMI ?? day.derivedBMIFromWeightHeight { bmiVals.append(bmi) }
            if let bf = day.avgBodyFatPercent { bodyFatVals.append(bf) }
            if let s = day.avgSystolic { sysVals.append(s) }
            if let d = day.avgDiastolic { diaVals.append(d) }
        }

        let review = NJTrainingReviewFile(
            schema: "nj_training_review_v1",
            weekOf: weekKey,
            goalContext: nil,
            recovery: .init(
                avgSleepHours: average(of: sleepHours),
                avgWeightKg: average(of: weightKg),
                avgBMI: average(of: bmiVals),
                avgBodyFatPct: average(of: bodyFatVals),
                avgBpSys: average(of: sysVals),
                avgBpDia: average(of: diaVals)
            ),
            sessions: plans.map { plan in
                let actualKey = "\(plan.dateKey)|\(canonicalTrainingSport(plan.sport))"
                let actual = actualByDateSport[actualKey] ?? (0, 0)
                let result = resultBySessionID[plan.planID]
                let actualDuration = result?.durationMin ?? actual.duration
                let actualDistance = result?.distanceKm ?? actual.distance
                let skipped = (result?.status?.lowercased() == "skipped")
                return NJTrainingReviewFile.SessionReview(
                    sessionID: plan.planID,
                    date: plan.dateKey,
                    title: plan.title.isEmpty ? plan.sport : plan.title,
                    category: plan.category,
                    sport: plan.sport,
                    sessionType: plan.sessionType,
                    plannedDurationMin: plan.targetDurationMin,
                    plannedDistanceKm: plan.targetDistanceKm,
                    actualDurationMin: actualDuration,
                    actualDistanceKm: actualDistance,
                    avgHeartRateBpm: result?.avgHeartRateBpm,
                    avgPaceMinPerKm: result?.avgPaceMinPerKm,
                    completed: !skipped && (actualDuration > 0 || actualDistance > 0),
                    notes: skipped ? "Skipped: \((result?.notes?.isEmpty == false ? result?.notes : "no reason") ?? "no reason")" : plan.notes
                )
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(review)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("nj_training_review_\(weekKey).json")
            try data.write(to: url, options: .atomic)
            trainingExportTarget = NJCalendarExportTarget(url: url)
        } catch {
            showTrainingMessage("Export failed: \(error.localizedDescription)")
        }
    }

    private func encodeJSON<T: Encodable>(_ value: T, encoder: JSONEncoder) -> String {
        guard let data = try? encoder.encode(value),
              let string = String(data: data, encoding: .utf8) else { return "" }
        return string
    }

    private func average(of values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private func canonicalTrainingSport(_ raw: String) -> String {
        raw
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "_")
    }

    private func loadTrainingRuntimeResults(start: Date, end: Date) -> [NJCalendarTrainingResult] {
        guard let data = UserDefaults(suiteName: "group.com.CYC.NotionJournal")?.data(forKey: "nj_training_runtime_results_v1"),
              let decoded = try? JSONDecoder().decode([NJCalendarTrainingResult].self, from: data) else {
            return []
        }
        let startMs = Int64(start.timeIntervalSince1970 * 1000.0)
        let endMs = Int64((calendar.date(byAdding: .day, value: 1, to: end) ?? end).timeIntervalSince1970 * 1000.0)
        return decoded.filter { $0.startedAtMs >= startMs && $0.startedAtMs < endMs }
    }

    private func plansForWeek(start: Date) -> [String: [NJPlannedExercise]] {
        let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
        let plans = store.notes.listPlannedExercises(startKey: dateKey(start), endKey: dateKey(end))
            .filter { $0.deleted == 0 }
        return Dictionary(grouping: plans, by: \.dateKey)
    }

    private func makeBlankTrainingPlan(for date: Date) -> NJPlannedExercise {
        let now = DBNoteRepository.nowMs()
        return NJPlannedExercise(
            planID: UUID().uuidString.lowercased(),
            dateKey: dateKey(date),
            weekKey: DBNoteRepository.sundayWeekStartKey(for: date, calendar: calendar),
            title: "",
            category: "aerobic",
            sport: "Running",
            sessionType: "",
            targetDistanceKm: 0,
            targetDurationMin: 0,
            notes: "",
            goalJSON: "[]",
            cueJSON: "[]",
            blockJSON: "[]",
            sourcePlanID: "",
            createdAtMs: now,
            updatedAtMs: now,
            deleted: 0
        )
    }

    private func eachDate(start: Date, through end: Date) -> [Date] {
        var out: [Date] = []
        var cursor = calendar.startOfDay(for: start)
        let last = calendar.startOfDay(for: end)
        while cursor <= last {
            out.append(cursor)
            guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    private func showTrainingMessage(_ message: String) {
        trainingAlertMessage = message
        showTrainingAlert = true
    }

    private func hasImportedTrainingPlan(in date: Date) -> Bool {
        guard let (start, endExclusive) = weekRange(for: date) else { return false }
        let endDate = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? start
        let plans = store.notes.listPlannedExercises(startKey: dateKey(start), endKey: dateKey(endDate))
        return plans.contains { $0.sourcePlanID.hasPrefix("training:") }
    }

    private func deleteImportedTrainingPlan(in date: Date) {
        guard let (start, endExclusive) = weekRange(for: date) else { return }
        let endDate = calendar.date(byAdding: .day, value: -1, to: endExclusive) ?? start
        let plans = store.notes.listPlannedExercises(startKey: dateKey(start), endKey: dateKey(endDate))
        let now = DBNoteRepository.nowMs()
        let imported = plans.filter { $0.sourcePlanID.hasPrefix("training:") }
        for plan in imported {
            store.notes.deletePlannedExercise(planID: plan.planID, nowMs: now)
        }
        reloadItemsForVisibleRange()
        store.publishTrainingWeekSnapshotToWidget(referenceDate: start)
        NJTrainingRuntime.shared.reload(referenceDate: start)
        showTrainingMessage("Deleted \(imported.count) imported training sessions for \(weekRangeTitle(for: start)).")
    }

    private func parseDateKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private func exportEntryToLLMJournal(_ entry: NJWeeklyWorkoutEntry) -> (ok: Bool, message: String) {
        do {
            let txID = try NJLLMJournalBridge.writeTimeSlot(entry: entry)
            return (true, "Exported to LLM tx_inbox (\(txID.prefix(8))).")
        } catch {
            return (false, error.localizedDescription)
        }
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
        let row = store.notes.planningNote(kind: "daily", targetKey: key)
        let text = row?.note ?? ""
        let protonJSON = row?.protonJSON ?? ""
        planningNoteHandle = makePlanningNoteHandle()
        planningNoteAttr = planningNoteInitialAttr(text: text, protonJSON: protonJSON, handle: planningNoteHandle)
        planningNoteSel = NSRange(location: 0, length: 0)
        planningNoteEditorHeight = 120
        planningNotePickedPhotoItem = nil
        planningNoteTarget = NJPlanningNoteSheetTarget(
            kind: "daily",
            targetKey: key,
            title: "Day Planning Note (\(formattedDate(date)))",
            protonJSON: protonJSON
        )
    }

    private func openWeekPlanningNoteEditor(for date: Date) {
        guard canOpenWeekPlanningNote(for: date) else { return }
        let key = weekPlanningTargetKey(for: date)
        let row = store.notes.planningNote(kind: "weekly", targetKey: key)
        let text = row?.note ?? ""
        let protonJSON = row?.protonJSON ?? ""
        planningNoteHandle = makePlanningNoteHandle()
        planningNoteAttr = planningNoteInitialAttr(text: text, protonJSON: protonJSON, handle: planningNoteHandle)
        planningNoteSel = NSRange(location: 0, length: 0)
        planningNoteEditorHeight = 120
        planningNotePickedPhotoItem = nil
        planningNoteTarget = NJPlanningNoteSheetTarget(
            kind: "weekly",
            targetKey: key,
            title: "Week Planning Note (\(weekRangeTitle(for: date)))",
            protonJSON: protonJSON
        )
    }

    private func openPhotoPicker(for date: Date) {
        activateDate(date)
        photoPickerTarget = NJCalendarDateSheetTarget(date: date)
    }

    private func openPlanExerciseSheet(for date: Date) {
        activateDate(date)
        planExerciseTarget = NJCalendarDateSheetTarget(date: date)
    }

    private func openFinanceEditor(for date: Date) {
        activateDate(date)
        financeEditorTarget = NJFinanceEditorTarget(date: date)
    }

    private func openDaySummary(for date: Date) {
        activateDate(date)
        daySummaryTarget = NJCalendarDaySummaryTarget(date: date)
    }

    private func saveFinanceDay(date: Date, events: [NJFinanceMacroEvent], brief: NJFinanceDailyBrief?) {
        let key = dateKey(date)
        let now = DBNoteRepository.nowMs()
        let normalizedEvents = events.map { row in
            NJFinanceMacroEvent(
                eventID: row.eventID.isEmpty ? UUID().uuidString.lowercased() : row.eventID,
                dateKey: key,
                title: row.title.trimmingCharacters(in: .whitespacesAndNewlines),
                category: row.category.trimmingCharacters(in: .whitespacesAndNewlines),
                region: row.region.trimmingCharacters(in: .whitespacesAndNewlines),
                timeText: row.timeText.trimmingCharacters(in: .whitespacesAndNewlines),
                impact: row.impact.trimmingCharacters(in: .whitespacesAndNewlines),
                source: row.source.trimmingCharacters(in: .whitespacesAndNewlines),
                notes: row.notes.trimmingCharacters(in: .whitespacesAndNewlines),
                createdAtMs: row.createdAtMs == 0 ? now : row.createdAtMs,
                updatedAtMs: now,
                deleted: 0
            )
        }.filter { !$0.title.isEmpty }

        let normalizedBrief: NJFinanceDailyBrief? = {
            guard let brief else { return nil }
            let news = brief.newsSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let expectation = brief.expectationSummary.trimmingCharacters(in: .whitespacesAndNewlines)
            let watch = brief.watchItems.trimmingCharacters(in: .whitespacesAndNewlines)
            let bias = brief.bias.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !news.isEmpty || !expectation.isEmpty || !watch.isEmpty || !bias.isEmpty else { return nil }
            return NJFinanceDailyBrief(
                dateKey: key,
                newsSummary: news,
                expectationSummary: expectation,
                watchItems: watch,
                bias: bias,
                createdAtMs: brief.createdAtMs == 0 ? now : brief.createdAtMs,
                updatedAtMs: now,
                deleted: 0
            )
        }()

        store.notes.saveFinanceDay(dateKey: key, events: normalizedEvents, brief: normalizedBrief, nowMs: now)
        reloadFinanceForVisibleRange(start: gridDates().first ?? date, end: gridDates().last ?? date)
        store.sync.schedulePush(debounceMs: 0)
    }

    private func savePlanningNote(kind: String, targetKey: String, text: String, protonJSON: String) {
        let now = DBNoteRepository.nowMs()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            store.notes.deletePlanningNote(kind: kind, targetKey: targetKey, nowMs: now)
            return
        }
        store.notes.upsertPlanningNote(kind: kind, targetKey: targetKey, note: trimmed, protonJSON: protonJSON, nowMs: now)
    }

    private func makePlanningNoteHandle() -> NJProtonEditorHandle {
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
    }

    private func planningNoteInitialAttr(text: String, protonJSON: String, handle: NJProtonEditorHandle) -> NSAttributedString {
        let trimmedProton = protonJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProton.isEmpty {
            let decoded = handle.attributedStringFromProtonJSONString(trimmedProton)
            let visible = decoded.string
                .replacingOccurrences(of: "\u{FFFC}", with: "")
                .replacingOccurrences(of: "\u{200B}", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !visible.isEmpty {
                return decoded
            }
        }
        return NSAttributedString(string: text)
    }

    private func canOpenWeekPlanningNote(for date: Date) -> Bool {
        let today = calendar.startOfDay(for: Date())
        guard let week = calendar.dateInterval(of: .weekOfYear, for: date) else { return false }
        return week.end > today
    }

    private func generateDaySummary(for date: Date) async -> NJCalendarDaySummaryData {
        let sourceText = buildDaySummarySourceText(for: date)
        let result = await NJAppleIntelligenceSummarizer.summarizeAuto(text: sourceText)
        let title = result.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NJCalendarDaySummaryData(
            title: title.isEmpty ? daySummaryTitle(for: date) : title,
            sourceText: sourceText,
            aiSummary: result.summary?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            aiMode: result.mode,
            aiError: result.error
        )
    }

    private func buildDaySummarySourceText(for date: Date) -> String {
        let key = dateKey(date)
        let sections: [(String, [String])] = [
            ("Reflection Notes", dayReflectionNoteLines(for: date)),
            ("Journal Entries", dayJournalEntryLines(for: date)),
            ("Completed Weekly Items", completedWeeklyTaggedItems(for: date)),
            ("Completed Planning Items", completedPlanningItems(for: date)),
            ("GPS / Movement", dayGPSSummaryLines(for: date)),
            ("Workouts", dayWorkoutSummaryLines(for: date)),
            ("Health", dayHealthSummaryLines(for: date))
        ]

        var out: [String] = [
            "Day: \(formattedDate(date))",
            "Date Key: \(key)",
            "",
            "Please summarize what happened on this day, what got done, where I went, and whether I exercised."
        ]

        for (title, lines) in sections {
            out.append("")
            out.append("## \(title)")
            if lines.isEmpty {
                out.append("None recorded.")
            } else {
                out.append(contentsOf: lines.map { "- \($0)" })
            }
        }

        return out.joined(separator: "\n")
    }

    private func daySummaryTitle(for date: Date) -> String {
        "Day Summary (\(formattedDate(date)))"
    }

    private func completedWeeklyTaggedItems(for date: Date) -> [String] {
        let rows = (try? store.notes.exportBlockRowsByCreatedDate(fromDate: date, toDate: date, tagFilter: "#WEEKLY")) ?? []
        return rows
            .flatMap { row in
                struckLineItems(fromPayloadJSON: row.payloadJSON).map { "[\(row.blockID)] \($0)" }
            }
    }

    private func dayReflectionNoteLines(for date: Date) -> [String] {
        let (startMs, endMs) = dayMsRange(for: date)
        let notes = store.notes.listNotesByDateRange(startMs: startMs, endMs: endMs)
            .filter { note in
                let domain = note.tabDomain.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                return domain.contains("reflection") || domain.contains("marriage") || domain.contains("self.")
            }

        return notes.compactMap { note in
            let blockLines = store.notes.loadAllTextBlocksRTFWithPlacement(noteID: note.id.raw)
                .flatMap { row -> [String] in
                    let payloadLines = summaryLineItems(fromPayloadJSON: row.payloadJSON)
                    if !payloadLines.isEmpty {
                        return payloadLines
                    }
                    let protonText = attributedTextFromProtonJSON(row.protonJSON)
                    let attr = protonText.length > 0 ? protonText : attributedText(fromRTFData: row.rtfData)
                    return summaryLineItems(from: attr)
                }
            let lines = Array(blockLines.prefix(12))
            let title = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty || !lines.isEmpty else { return nil }

            var parts: [String] = []
            if !title.isEmpty { parts.append(title) }
            if !note.tabDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                parts.append(note.tabDomain)
            }

            let header = parts.isEmpty ? "[\(note.id.raw)]" : "[\(note.id.raw)] \(parts.joined(separator: " | "))"
            if lines.isEmpty { return header }
            return "\(header): \(lines.joined(separator: " / "))"
        }
    }

    private func dayJournalEntryLines(for date: Date) -> [String] {
        let rows = (try? store.notes.exportBlockRowsByCreatedDate(fromDate: date, toDate: date, tagFilter: nil)) ?? []
        return rows.compactMap { row in
            let lines = summaryLineItems(fromPayloadJSON: row.payloadJSON)
            guard !lines.isEmpty else { return nil }

            var prefix: [String] = []
            if !row.noteDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                prefix.append(row.noteDomain)
            }
            let tags = row.blockTags
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !tags.isEmpty {
                prefix.append(tags.prefix(4).joined(separator: ", "))
            }

            let header = prefix.isEmpty ? "[\(row.blockID)]" : "[\(row.blockID)] \(prefix.joined(separator: " | "))"
            return "\(header): \(lines.joined(separator: " / "))"
        }
    }

    private func completedPlanningItems(for date: Date) -> [String] {
        let dayKey = dateKey(date)
        let weekKey = weekPlanningTargetKey(for: date)
        let daily = store.notes.planningNote(kind: "daily", targetKey: dayKey)
        let weekly = store.notes.planningNote(kind: "weekly", targetKey: weekKey)

        var out: [String] = []
        if let daily {
            out.append(contentsOf: struckLineItems(fromProtonJSON: daily.protonJSON).map { "Daily plan: \($0)" })
        }
        if let weekly {
            out.append(contentsOf: struckLineItems(fromProtonJSON: weekly.protonJSON).map { "Weekly plan: \($0)" })
        }
        return out
    }

    private func dayWorkoutSummaryLines(for date: Date) -> [String] {
        let start = calendar.startOfDay(for: date)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let entries = loadWorkoutEntries(start: start, endExclusive: end)
        return entries.map { entry in
            var parts: [String] = [entry.sport]
            if entry.distanceKm > 0 { parts.append("\(fmtNum(entry.distanceKm)) km") }
            if entry.durationMin > 0 { parts.append("\(fmtNum(entry.durationMin)) min") }
            parts.append(timeRangeText(start: entry.startDate, end: entry.endDate))
            return parts.joined(separator: " | ")
        }
    }

    private func dayHealthSummaryLines(for date: Date) -> [String] {
        let day = healthByDate[dateKey(date)] ?? NJCalendarHealthDay()
        var out: [String] = []
        if day.sleepHours > 0 { out.append("Sleep: \(fmtNum(day.sleepHours)) h") }
        if day.workoutCount > 0 {
            out.append("Exercise recorded: \(day.workoutCount) workout(s), \(fmtNum(day.workoutDistanceKm)) km, \(fmtNum(day.workoutDurationMin)) min")
        }
        if let weight = day.avgWeightKg { out.append("Weight: \(fmtNum(weight)) kg") }
        if let bmi = day.avgBMI ?? day.derivedBMIFromWeightHeight { out.append("BMI: \(fmtNum(bmi))") }
        if let bodyFat = day.avgBodyFatPercent { out.append("Body fat: \(fmtNum(bodyFat))%") }
        if let sys = day.avgSystolic, let dia = day.avgDiastolic {
            out.append("Blood pressure: \(fmtNum(sys))/\(fmtNum(dia))")
        }
        return out
    }

    private func dayGPSSummaryLines(for date: Date) -> [String] {
        guard let root = NJGPSLogger.shared.docsRootForViewer() else { return [] }
        let transitURL = root.appendingPathComponent("GPS/Transit/\(gpsDayKey(date)).json")
        let rawURL = root.appendingPathComponent("GPS/\(gpsYearMonthPath(date)).ndjson")

        var out: [String] = []

        if let data = try? Data(contentsOf: transitURL),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            let minutes = obj["transit_minutes"] as? Int ?? 0
            let distanceM = obj["distance_m"] as? Int ?? 0
            let segments = obj["segments"] as? Int ?? 0
            let points = obj["points"] as? Int ?? 0
            if minutes > 0 || distanceM > 0 {
                out.append("Transit: \(minutes) min, \(fmtNum(Double(distanceM) / 1000.0)) km, \(segments) segments, \(points) points")
            }
            if let modes = obj["by_mode"] as? [[String: Any]] {
                let topModes = modes.prefix(3).compactMap { row -> String? in
                    guard let mode = row["mode"] as? String else { return nil }
                    let seconds = row["seconds"] as? Int ?? 0
                    guard seconds > 0 else { return nil }
                    return "\(mode): \(Int((Double(seconds) / 60.0).rounded())) min"
                }
                if !topModes.isEmpty {
                    out.append("Movement modes: \(topModes.joined(separator: ", "))")
                }
            }
        }

        if let route = coarseGPSRouteSummary(from: rawURL), !route.isEmpty {
            out.append("Route: \(route)")
        }

        return out
    }

    private func struckLineItems(fromPayloadJSON payloadJSON: String) -> [String] {
        struckLineItems(from: attributedText(fromPayloadJSON: payloadJSON))
    }

    private func summaryLineItems(fromPayloadJSON payloadJSON: String) -> [String] {
        let attrLines = summaryLineItems(from: attributedText(fromPayloadJSON: payloadJSON))
        let rawLines = rawPayloadTextLines(fromPayloadJSON: payloadJSON)
        return Array(uniquedPreservingOrder(attrLines + rawLines).prefix(12))
    }

    private func attributedText(fromPayloadJSON payloadJSON: String) -> NSAttributedString {
        guard let data = payloadJSON.data(using: .utf8),
              let payload = try? JSONDecoder().decode(NJPayloadV1.self, from: data) else {
            return NSAttributedString(string: NJQuickNotePayload.plainText(from: payloadJSON))
        }
        if let proton = try? payload.proton1Data() {
            if !proton.proton_json.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return attributedTextFromProtonJSON(proton.proton_json)
            }
            return DBNoteRepository.decodeAttributedTextFromRTFBase64(proton.rtf_base64)
        }
        return NSAttributedString(string: NJQuickNotePayload.plainText(from: payloadJSON))
    }

    private func struckLineItems(fromProtonJSON protonJSON: String) -> [String] {
        struckLineItems(from: attributedTextFromProtonJSON(protonJSON))
    }

    private func attributedTextFromProtonJSON(_ protonJSON: String) -> NSAttributedString {
        let trimmed = protonJSON.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return NSAttributedString(string: "") }
        let handle = NJProtonEditorHandle()
        return handle.attributedStringFromProtonJSONString(trimmed)
    }

    private func attributedText(fromRTFData data: Data) -> NSAttributedString {
        guard !data.isEmpty else { return NSAttributedString(string: "") }
        if let rtfd = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtfd],
            documentAttributes: nil
        ) { return rtfd }
        if let rtf = try? NSAttributedString(
            data: data,
            options: [.documentType: NSAttributedString.DocumentType.rtf],
            documentAttributes: nil
        ) { return rtf }
        return NSAttributedString(string: "")
    }

    private func struckLineItems(from text: NSAttributedString) -> [String] {
        guard text.length > 0 else { return [] }
        let ns = text.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var out: [String] = []
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, _ in
            let line = ns.substring(with: lineRange).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            if lineRepresentsCompletedItem(line, attributed: text.attributedSubstring(from: lineRange)) {
                out.append(line)
            }
        }
        return out
    }

    private func summaryLineItems(from text: NSAttributedString) -> [String] {
        guard text.length > 0 else { return [] }
        let ns = text.string as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        var out: [String] = []
        ns.enumerateSubstrings(in: fullRange, options: [.byLines, .substringNotRequired]) { _, lineRange, _, stop in
            let line = ns.substring(with: lineRange)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\u{2022}", with: "")
                .replacingOccurrences(of: "- [ ]", with: "")
                .replacingOccurrences(of: "- [x]", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return }
            out.append(line)
            if out.count >= 6 {
                stop.pointee = true
            }
        }
        if out.count < 12 {
            let attachmentLines = attachmentSummaryLineItems(from: text, limit: 12 - out.count)
            out.append(contentsOf: attachmentLines)
        }
        return out
    }

    private func attachmentSummaryLineItems(from text: NSAttributedString, limit: Int) -> [String] {
        guard text.length > 0, limit > 0 else { return [] }
        var out: [String] = []
        text.enumerateAttribute(.attachment, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
            guard let attachment = value as? Attachment else { return }

            if let collapsible = attachment.contentView as? NJCollapsibleAttachmentView {
                let titleLines = summaryLineItems(from: collapsible.titleAttributedText)
                let bodyLines = summaryLineItems(from: collapsible.bodyAttributedText)
                out.append(contentsOf: titleLines)
                out.append(contentsOf: bodyLines)
            } else if let table = attachment.contentView as? NJTableAttachmentView {
                for cell in table.gridView.cells {
                    let cellLines = summaryLineItems(from: cell.editor.attributedText)
                    out.append(contentsOf: cellLines)
                    if out.count >= limit { break }
                }
            }

            out = Array(out.prefix(limit))
            if out.count >= limit {
                stop.pointee = true
            }
        }
        return out
    }

    private func rawPayloadTextLines(fromPayloadJSON payloadJSON: String) -> [String] {
        guard let data = payloadJSON.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) else { return [] }

        var chunks: [String] = []

        func walk(_ value: Any) {
            if let dict = value as? [String: Any] {
                for (key, raw) in dict {
                    let lowered = key.lowercased()
                    if lowered.contains("rtf_base64"), let b64 = raw as? String, !b64.isEmpty {
                        let text = DBNoteRepository.decodeAttributedTextFromRTFBase64(b64).string
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                        if !text.isEmpty { chunks.append(text) }
                        continue
                    }
                    if ["title", "summary", "body", "notes", "transcript_txt", "text"].contains(lowered),
                       let s = raw as? String {
                        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty { chunks.append(trimmed) }
                    }
                    if let s = raw as? String,
                       (s.hasPrefix("{") || s.hasPrefix("[")),
                       let nestedData = s.data(using: .utf8),
                       let nested = try? JSONSerialization.jsonObject(with: nestedData) {
                        walk(nested)
                        continue
                    }
                    walk(raw)
                }
            } else if let arr = value as? [Any] {
                for item in arr { walk(item) }
            }
        }

        walk(obj)

        let lines = chunks
            .flatMap { chunk in
                chunk
                    .split(whereSeparator: \.isNewline)
                    .map(String.init)
            }
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "\u{2022}", with: "")
                    .replacingOccurrences(of: "- [ ]", with: "")
                    .replacingOccurrences(of: "- [x]", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
            .filter { !$0.isEmpty }

        return Array(uniquedPreservingOrder(lines).prefix(12))
    }

    private func attributedStringHasStrikethrough(_ text: NSAttributedString) -> Bool {
        guard text.length > 0 else { return false }
        var found = false
        text.enumerateAttribute(.strikethroughStyle, in: NSRange(location: 0, length: text.length), options: []) { value, _, stop in
            let intValue: Int
            if let n = value as? NSNumber {
                intValue = n.intValue
            } else if let i = value as? Int {
                intValue = i
            } else {
                intValue = 0
            }
            if intValue != 0 {
                found = true
                stop.pointee = true
            }
        }
        return found
    }

    private func lineRepresentsCompletedItem(_ line: String, attributed: NSAttributedString) -> Bool {
        if attributedStringHasStrikethrough(attributed) {
            return true
        }

        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let completedPrefixes = [
            "- [x]",
            "* [x]",
            "[x]",
            "☑",
            "✅",
            "done:",
            "completed:"
        ]
        return completedPrefixes.contains { trimmed.hasPrefix($0) }
    }

    private func timeRangeText(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.timeStyle = .short
        return "\(f.string(from: start))-\(f.string(from: end))"
    }

    private func dayMsRange(for date: Date) -> (Int64, Int64) {
        let start = calendar.startOfDay(for: date)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let startMs = Int64(start.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(endExclusive.timeIntervalSince1970 * 1000.0) - 1
        return (startMs, endMs)
    }

    private func gpsDayKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func gpsYearMonthPath(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        f.dateFormat = "yyyy/MM/yyyy-MM-dd"
        return f.string(from: date)
    }

    private func coarseGPSRouteSummary(from url: URL) -> String? {
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }

        var regions: [String] = []
        for line in text.split(separator: "\n") {
            guard let d = String(line).data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                  let lat = obj["lat"] as? Double,
                  let lon = obj["lon"] as? Double else { continue }
            let region = coarseRegionName(lat: lat, lon: lon)
            if regions.last != region {
                regions.append(region)
            }
        }

        guard !regions.isEmpty else { return nil }
        return regions.joined(separator: " -> ")
    }

    private func coarseRegionName(lat: Double, lon: Double) -> String {
        if lat >= 22.15, lat <= 22.42, lon >= 113.80, lon <= 114.45 { return "Hong Kong" }
        if lat >= 22.45, lat <= 22.90, lon >= 113.75, lon <= 114.70 { return "Shenzhen" }
        return String(format: "lat %.3f, lon %.3f", lat, lon)
    }

    private func openWeekPlanningClipboardPreview(for date: Date) {
        planningClipboardDrafts = buildWeekPlanningClipboardDrafts(for: date)
        showPlanningClipboardPreviewSheet = true
    }

    private func submitWeekPlanningPreviewToClipboard() {
        for draft in planningClipboardDrafts {
            store.createQuickNoteToClipboard(
                payloadJSON: draft.payloadJSON,
                createdAtMs: draft.createdAtMs,
                tags: draft.tags
            )
        }
        showPlanningClipboardPreviewSheet = false
    }

    private func buildWeekPlanningClipboardDrafts(for date: Date) -> [NJPlanningClipboardDraft] {
        guard let sunday = sundayDate(for: date) else { return [] }
        let weekKey = dateKey(sunday)
        let weekKeyCompact = compactDateKey(from: weekKey)
        var drafts: [NJPlanningClipboardDraft] = []

        let weeklyPlanning = store.notes.planningNote(kind: "weekly", targetKey: weekKey)
        let weeklyNote = weeklyPlanning?.note ?? ""
        let weeklyProtonJSON = weeklyPlanning?.protonJSON ?? ""
        let weeklyTitle = "(\(weekKeyCompact)) Weekly Focus"
        var weeklySummaryLines: [String] = []
        var weeklyPlanLines: [String] = []
        for dayOffset in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: sunday) else { continue }
            let key = dateKey(day)
            let plans = plannedByDate[key] ?? []
            for p in plans {
                let weekdayShort = shortWeekdayName(day)
                let notes = p.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                weeklyPlanLines.append(
                    "\(weekdayShort): \(p.sport) \(fmtNum(p.targetDistanceKm))km / \(fmtNum(p.targetDurationMin))m\(notes.isEmpty ? "" : " - \(notes)")"
                )
            }
        }
        weeklySummaryLines.append("Weekly Block")
        if !weeklyPlanLines.isEmpty {
            weeklySummaryLines.append("Planned Activities")
            weeklySummaryLines.append(contentsOf: weeklyPlanLines)
        }
        let weeklySummaryBody = joinedLines(weeklySummaryLines)
        let weeklyPreviewBody = joinedLines([weeklySummaryBody, weeklyNote])
        let weeklyPayloadBody = weeklyProtonJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? weeklyPreviewBody
            : weeklySummaryBody
        drafts.append(
            NJPlanningClipboardDraft(
                title: weeklyTitle,
                body: weeklyPreviewBody,
                createdAtMs: msAtNoon(for: sunday),
                tags: ["#WEEKLY"],
                payloadJSON: makePlanningClipboardPayload(
                    title: weeklyTitle,
                    body: weeklyPayloadBody,
                    protonJSONBody: weeklyProtonJSON
                )
            )
        )

        for dayOffset in 1...6 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: sunday) else { continue }
            let dayKey = dateKey(day)
            let dayCompact = compactDateKey(from: dayKey)
            let weekdayShort = shortWeekdayName(day)
            let dayPlanningRow = store.notes.planningNote(kind: "daily", targetKey: dayKey)
            let dayPlanning = dayPlanningRow?.note ?? ""
            let dayPlanningProtonJSON = dayPlanningRow?.protonJSON ?? ""
            let calendarItem = store.notes.calendarItem(dateKey: dayKey)?.title ?? ""
            let eventTitles = (eventsByDate[dayKey] ?? [])
                .map { $0.title.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let renewalLines = (renewalItemsByDate[dayKey] ?? []).map { renewalCalendarLine(for: $0) }
            var mergedEventLines: [String] = []
            if !calendarItem.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                mergedEventLines.append(calendarItem.trimmingCharacters(in: .whitespacesAndNewlines))
            }
            for line in renewalLines where !mergedEventLines.contains(line) {
                mergedEventLines.append(line)
            }
            for t in eventTitles where !mergedEventLines.contains(t) {
                mergedEventLines.append(t)
            }

            let plans = plannedByDate[dayKey] ?? []
            let planLines: [String] = plans.map {
                "Planned: \($0.sport) \(fmtNum($0.targetDistanceKm))km / \(fmtNum($0.targetDurationMin))m\($0.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "" : " - \($0.notes)")"
            }

            let health = healthByDate[dayKey] ?? NJCalendarHealthDay()
            var healthLines: [String] = []
            if health.sleepHours > 0 { healthLines.append("Sleep: \(fmtNum(health.sleepHours)) h") }
            if health.workoutCount > 0 { healthLines.append("Workout done: \(fmtNum(health.workoutDistanceKm)) km / \(fmtNum(health.workoutDurationMin)) min") }
            if let s = health.avgSystolic, let d = health.avgDiastolic { healthLines.append("BP: \(Int(s))/\(Int(d))") }
            if health.medDoseCount > 0 { healthLines.append("Medication: logged") }

            let dailyTitle = "(\(dayCompact)) \(weekdayShort) - Daily Focus"
            let dailySummaryLines: [String] = [
                joinedLines(mergedEventLines),
                joinedLines(healthLines),
                joinedLines(planLines)
            ]
            let dailySummaryBody = joinedLines(dailySummaryLines)
            let dailyPreviewBody = joinedLines([dailySummaryBody, dayPlanning])
            let dailyPayloadBody = dayPlanningProtonJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? dailyPreviewBody
                : dailySummaryBody
            drafts.append(
                NJPlanningClipboardDraft(
                    title: dailyTitle,
                    body: dailyPreviewBody,
                    createdAtMs: msAtNoon(for: day),
                    tags: ["#WEEKLY"],
                    payloadJSON: makePlanningClipboardPayload(
                        title: dailyTitle,
                        body: dailyPayloadBody,
                        protonJSONBody: dayPlanningProtonJSON
                    )
                )
            )
        }
        return drafts
    }

    private func sundayDate(for date: Date) -> Date? {
        let key = DBNoteRepository.sundayWeekStartKey(for: date, calendar: calendar)
        return dateFromKey(key)
    }

    private func dateFromKey(_ key: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = calendar.timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }

    private func compactDateKey(from key: String) -> String {
        key.replacingOccurrences(of: "-", with: "")
    }

    private func shortWeekdayName(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE"
        return f.string(from: date)
    }

    private func joinedLines(_ lines: [String]) -> String {
        lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
    }

    private func uniquedPreservingOrder(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for value in values {
            if seen.insert(value).inserted {
                out.append(value)
            }
        }
        return out
    }

    private func makePlanningClipboardPayload(title: String, body: String, protonJSONBody: String = "") -> String {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return NJQuickNotePayload.makePayloadJSON(from: cleanBody) }

        let titleAttr = NSAttributedString(
            string: cleanTitle,
            attributes: [.font: UIFont.systemFont(ofSize: 18, weight: .semibold)]
        )

        let full = NSMutableAttributedString(attributedString: titleAttr)
        if !cleanBody.isEmpty {
            let bodyAttr = NSAttributedString(
                string: "\n\(cleanBody)",
                attributes: [.font: UIFont.systemFont(ofSize: 17, weight: .regular)]
            )
            full.append(bodyAttr)
        }

        let trimmedProton = protonJSONBody.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedProton.isEmpty {
            let protonHandle = NJProtonEditorHandle()
            let protonAttr = protonHandle.attributedStringFromProtonJSONString(trimmedProton)
            if protonAttr.length > 0 {
                full.append(NSAttributedString(string: "\n\n"))
                full.append(protonAttr)
            }
        }

        let rtfBase64 = DBNoteRepository.encodeRTFBase64FromAttributedText(full)
        let protonJSON = NJProtonEditorHandle().exportProtonJSONString(from: full)
        return NJQuickNotePayload.makePayloadJSON(protonJSON: protonJSON, rtfBase64: rtfBase64)
    }

    private func msAtNoon(for date: Date) -> Int64 {
        let start = calendar.startOfDay(for: date)
        let noon = calendar.date(byAdding: .hour, value: 12, to: start) ?? start
        return Int64(noon.timeIntervalSince1970 * 1000.0)
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

private struct NJFinanceDaySheet: View {
    let date: Date
    let initialEvents: [NJFinanceMacroEvent]
    let initialBrief: NJFinanceDailyBrief?
    let onSave: ([NJFinanceMacroEvent], NJFinanceDailyBrief?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var events: [NJFinanceMacroEvent] = []
    @State private var newsSummary = ""
    @State private var expectationSummary = ""
    @State private var watchItems = ""
    @State private var bias = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Macro Calendar") {
                    if events.isEmpty {
                        Text("No macro events yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach($events) { $event in
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Event", text: $event.title)
                            HStack {
                                TextField("Time", text: $event.timeText)
                                TextField("Impact", text: $event.impact)
                            }
                            HStack {
                                TextField("Category", text: $event.category)
                                TextField("Region", text: $event.region)
                            }
                            TextField("Source", text: $event.source)
                            TextField("Notes", text: $event.notes, axis: .vertical)
                        }
                        .padding(.vertical, 4)
                    }
                    .onDelete { offsets in
                        events.remove(atOffsets: offsets)
                    }

                    Button {
                        events.append(
                            NJFinanceMacroEvent(
                                eventID: UUID().uuidString.lowercased(),
                                dateKey: "",
                                title: "",
                                category: "",
                                region: "",
                                timeText: "",
                                impact: "",
                                source: "",
                                notes: "",
                                createdAtMs: 0,
                                updatedAtMs: 0,
                                deleted: 0
                            )
                        )
                    } label: {
                        Label("Add Event", systemImage: "plus")
                    }
                }

                Section("Daily Summary") {
                    TextField("Bias / posture", text: $bias)
                    TextField("News summary", text: $newsSummary, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Expectation summary", text: $expectationSummary, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Watch items", text: $watchItems, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle(formattedDate(date))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let now = DBNoteRepository.nowMs()
                        let brief = NJFinanceDailyBrief(
                            dateKey: "",
                            newsSummary: newsSummary,
                            expectationSummary: expectationSummary,
                            watchItems: watchItems,
                            bias: bias,
                            createdAtMs: initialBrief?.createdAtMs ?? now,
                            updatedAtMs: now,
                            deleted: 0
                        )
                        onSave(events, brief)
                        dismiss()
                    }
                }
            }
            .onAppear {
                events = initialEvents
                newsSummary = initialBrief?.newsSummary ?? ""
                expectationSummary = initialBrief?.expectationSummary ?? ""
                watchItems = initialBrief?.watchItems ?? ""
                bias = initialBrief?.bias ?? ""
            }
        }
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .medium
        return formatter.string(from: date)
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

private struct NJPlanningClipboardDraft: Identifiable {
    let id = UUID()
    let title: String
    let body: String
    let createdAtMs: Int64
    let tags: [String]
    let payloadJSON: String

    var fullText: String {
        if body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return "\(title)\n\(body)"
    }
}

private struct NJPlanningClipboardPreviewSheet: View {
    let drafts: [NJPlanningClipboardDraft]
    let onSubmit: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(Array(drafts.enumerated()), id: \.element.id) { idx, draft in
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(idx + 1). \(draft.title)")
                            .font(.headline)
                        Text(draft.body.isEmpty ? "(empty)" : draft.body)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("Clipboard Preview")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Submit") {
                        onSubmit()
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(drafts.isEmpty)
                }
            }
        }
    }
}

private struct NJCalendarDaySummarySheet: View {
    let date: Date
    let loadSummary: () async -> NJCalendarDaySummaryData

    @Environment(\.dismiss) private var dismiss
    @State private var data: NJCalendarDaySummaryData? = nil
    @State private var isLoading = true
    @State private var showShare = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Building day summary...")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let data {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(data.title)
                                    .font(.headline)
                                if !data.aiSummary.isEmpty {
                                    Text(data.aiSummary)
                                        .textSelection(.enabled)
                                } else {
                                    Text(data.aiError ?? "Apple Intelligence could not produce a summary.")
                                        .foregroundStyle(.secondary)
                                }
                                Text("Mode: \(data.aiMode)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            VStack(alignment: .leading, spacing: 8) {
                                Text("Source")
                                    .font(.headline)
                                Text(data.sourceText)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .padding(16)
                    }
                } else {
                    ContentUnavailableView("No Summary", systemImage: "text.quote")
                }
            }
            .navigationTitle(formattedDate(date))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button("Copy") {
                        UIPasteboard.general.string = shareText
                    }
                    .disabled(shareText.isEmpty)

                    Button("Share") {
                        showShare = true
                    }
                    .disabled(shareText.isEmpty)
                }
            }
            .task {
                guard data == nil else { return }
                isLoading = true
                data = await loadSummary()
                isLoading = false
            }
            .sheet(isPresented: $showShare) {
                NJShareSheet(items: [shareText])
            }
        }
    }

    private var shareText: String {
        guard let data else { return "" }
        let summary = data.aiSummary.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = data.sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
        if summary.isEmpty { return source }
        return "\(data.title)\n\n\(summary)\n\n\(source)"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }
}

private struct NJPlanningNoteSheet: View {
    let title: String
    let handle: NJProtonEditorHandle
    let initialAttributedText: NSAttributedString
    let initialSelectedRange: NSRange
    let initialProtonJSON: String
    @Binding var snapshotAttributedText: NSAttributedString
    @Binding var snapshotSelectedRange: NSRange
    @Binding var measuredHeight: CGFloat
    @Binding var pickedPhotoItem: PhotosPickerItem?
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                NJProtonEditorView(
                    initialAttributedText: initialAttributedText,
                    initialSelectedRange: initialSelectedRange,
                    snapshotAttributedText: $snapshotAttributedText,
                    snapshotSelectedRange: $snapshotSelectedRange,
                    measuredHeight: $measuredHeight,
                    handle: handle
                )
                .frame(minHeight: measuredHeight)
                .padding(10)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
                Spacer()
            }
            .padding(16)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                NJProtonFloatingFormatBar(handle: handle, pickedPhotoItem: $pickedPhotoItem)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
            .onAppear {
                if !initialProtonJSON.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    handle.hydrateFromProtonJSONString(initialProtonJSON)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        handle.snapshot()
                        let attr = handle.editor?.attributedText ?? snapshotAttributedText
                        let plain = attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
                        let exported = handle.exportProtonJSONString()
                        let proton = exported.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? handle.exportProtonJSONString(from: attr)
                            : exported
                        onSave(plain, proton)
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
                        Text("Hiking").tag("Hiking")
                        Text("Tennis").tag("Tennis")
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

private struct NJTrainingManageSheet: View {
    let date: Date
    let plans: [NJPlannedExercise]
    let onEdit: (NJPlannedExercise) -> Void
    let onDelete: (NJPlannedExercise) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(plans, id: \.planID) { plan in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(plan.title.isEmpty ? plan.sport : plan.title)
                            .font(.headline)
                        Text([plan.category, plan.sessionType, plan.sport]
                            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                            .filter { !$0.isEmpty }
                            .joined(separator: " • "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(summary(plan))
                            .font(.caption)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            onDelete(plan)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            dismiss()
                            onEdit(plan)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
            }
            .navigationTitle(title())
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func summary(_ plan: NJPlannedExercise) -> String {
        var parts: [String] = []
        if plan.targetDistanceKm > 0 { parts.append("\(fmt(plan.targetDistanceKm)) km") }
        if plan.targetDurationMin > 0 { parts.append("\(fmt(plan.targetDurationMin)) min") }
        if !plan.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(plan.notes.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return parts.joined(separator: " • ")
    }

    private func fmt(_ v: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }

    private func title() -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        return "Training \(f.string(from: date))"
    }
}

private struct NJTrainingWeekPlannerSheet: View {
    let weekStart: Date
    let loadPlansByDate: () -> [String: [NJPlannedExercise]]
    let onImportJSON: () -> Void
    let onAdd: (Date) -> Void
    let onEdit: (NJPlannedExercise) -> Void
    let onDelete: (NJPlannedExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    private let calendar = Calendar.current

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onImportJSON()
                    } label: {
                        Label("Import JSON Plan", systemImage: "square.and.arrow.down")
                    }
                }

                ForEach(0..<7, id: \.self) { offset in
                    let day = calendar.date(byAdding: .day, value: offset, to: weekStart) ?? weekStart
                    let key = dateKey(day)
                    Section(dayTitle(day)) {
                        let plans = (loadPlansByDate()[key] ?? []).sorted { ($0.title, $0.updatedAtMs) < ($1.title, $1.updatedAtMs) }
                        if plans.isEmpty {
                            Text("No planned session")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(plans, id: \.planID) { plan in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(plan.title.isEmpty ? plan.sport : plan.title)
                                        .font(.subheadline)
                                    Text([plan.category, plan.sessionType, summary(plan)]
                                        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                                        .joined(separator: " • "))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button(role: .destructive) { onDelete(plan) } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                    Button {
                                        onEdit(plan)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    .tint(.blue)
                                }
                            }
                        }
                        Button {
                            onAdd(day)
                        } label: {
                            Label("Add Session", systemImage: "plus")
                        }
                    }
                }
            }
            .navigationTitle(weekTitle)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var weekTitle: String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "MMM d"
        let end = calendar.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "Plan \(f.string(from: weekStart))-\(f.string(from: end))"
    }

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func dayTitle(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEEE, MMM d"
        return f.string(from: date)
    }

    private func summary(_ plan: NJPlannedExercise) -> String {
        var parts: [String] = []
        if plan.targetDistanceKm > 0 { parts.append("\(fmt(plan.targetDistanceKm)) km") }
        if plan.targetDurationMin > 0 { parts.append("\(fmt(plan.targetDurationMin)) min") }
        return parts.joined(separator: " • ")
    }

    private func fmt(_ value: Double) -> String {
        let f = NumberFormatter()
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        return f.string(from: NSNumber(value: value)) ?? String(format: "%.1f", value)
    }
}

private struct NJTrainingSessionEditorSheet: View {
    let date: Date
    let plan: NJPlannedExercise
    let onSave: (NJPlannedExercise) -> Void
    let onDelete: (NJPlannedExercise) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var category: String
    @State private var sport: String
    @State private var sessionType: String
    @State private var distance: String
    @State private var duration: String
    @State private var notes: String
    @State private var goalsJSON: String
    @State private var cuesJSON: String
    @State private var blocksJSON: String
    @State private var errorText: String = ""

    init(date: Date, plan: NJPlannedExercise, onSave: @escaping (NJPlannedExercise) -> Void, onDelete: @escaping (NJPlannedExercise) -> Void) {
        self.date = date
        self.plan = plan
        self.onSave = onSave
        self.onDelete = onDelete
        _title = State(initialValue: plan.title)
        _category = State(initialValue: plan.category.isEmpty ? "aerobic" : plan.category)
        _sport = State(initialValue: plan.sport)
        _sessionType = State(initialValue: plan.sessionType)
        _distance = State(initialValue: plan.targetDistanceKm > 0 ? String(plan.targetDistanceKm) : "")
        _duration = State(initialValue: plan.targetDurationMin > 0 ? String(plan.targetDurationMin) : "")
        _notes = State(initialValue: plan.notes)
        _goalsJSON = State(initialValue: Self.prettyJSONArray(plan.goalJSON))
        _cuesJSON = State(initialValue: Self.prettyJSONArray(plan.cueJSON))
        _blocksJSON = State(initialValue: Self.prettyJSONArray(plan.blockJSON))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Session") {
                    TextField("Title", text: $title)
                    Picker("Category", selection: $category) {
                        Text("Aerobic").tag("aerobic")
                        Text("Core").tag("core")
                        Text("Strength").tag("strength")
                    }
                    TextField("Sport", text: $sport)
                    TextField("Session Type", text: $sessionType)
                    TextField("Distance (km)", text: $distance)
                        .keyboardType(.decimalPad)
                    TextField("Duration (min)", text: $duration)
                        .keyboardType(.decimalPad)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3, reservesSpace: true)
                }
                Section("Goals JSON") {
                    TextEditor(text: $goalsJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                }
                Section("Cue Rules JSON") {
                    TextEditor(text: $cuesJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 120)
                }
                Section("Blocks JSON") {
                    TextEditor(text: $blocksJSON)
                        .font(.system(.caption, design: .monospaced))
                        .frame(minHeight: 160)
                }
                if !errorText.isEmpty {
                    Section {
                        Text(errorText)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Section {
                    Button("Delete Session", role: .destructive) {
                        onDelete(plan)
                        dismiss()
                    }
                }
            }
            .navigationTitle("Edit Training")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            var updated = plan
                            updated.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.category = category
                            updated.sport = sport.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.sessionType = sessionType.trimmingCharacters(in: .whitespacesAndNewlines)
                            updated.targetDistanceKm = Double(distance) ?? 0
                            updated.targetDurationMin = Double(duration) ?? 0
                            updated.notes = notes
                            updated.goalJSON = try normalizeJSONArray(goalsJSON)
                            updated.cueJSON = try normalizeJSONArray(cuesJSON)
                            updated.blockJSON = try normalizeJSONArray(blocksJSON)
                            updated.dateKey = dateKey(date)
                            updated.weekKey = DBNoteRepository.sundayWeekStartKey(for: date, calendar: Calendar.current)
                            updated.updatedAtMs = DBNoteRepository.nowMs()
                            onSave(updated)
                            dismiss()
                        } catch {
                            errorText = error.localizedDescription
                        }
                    }
                }
            }
        }
    }

    private func dateKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private func normalizeJSONArray(_ raw: String) throws -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "[]" }
        guard let data = trimmed.data(using: .utf8) else {
            throw NSError(domain: "NJTrainingEditor", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid JSON text."])
        }
        let obj = try JSONSerialization.jsonObject(with: data)
        guard JSONSerialization.isValidJSONObject(obj), obj is [Any] else {
            throw NSError(domain: "NJTrainingEditor", code: 2, userInfo: [NSLocalizedDescriptionKey: "Training JSON sections must be arrays."])
        }
        let pretty = try JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        return String(data: pretty, encoding: .utf8) ?? "[]"
    }

    private static func prettyJSONArray(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let data = trimmed.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(obj),
              let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: pretty, encoding: .utf8) else {
            return trimmed.isEmpty ? "[]" : trimmed
        }
        return string
    }
}

private struct NJWeeklyWorkoutEntry: Identifiable {
    enum Kind { case actual, planned }

    let id: String
    let sport: String
    let startDate: Date
    let endDate: Date
    let durationMin: Double
    let distanceKm: Double
    let source: String
    let kind: Kind

    var paceMinPerKm: Double? {
        guard distanceKm > 0, durationMin > 0 else { return nil }
        return durationMin / distanceKm
    }

    var canDeleteFromNotionJournal: Bool {
        kind == .actual && source.lowercased().contains("notion journal")
    }

    var timeSlotExportJSON: String {
        let iso = ISO8601DateFormatter()
        let payload: [String: Any] = [
            "schema": "nj_timeslot_v1",
            "title": sport,
            "kind": (kind == .planned ? "planned" : "actual"),
            "start_iso": iso.string(from: startDate),
            "end_iso": iso.string(from: endDate),
            "duration_min": durationMin,
            "distance_km": distanceKm,
            "source": source
        ]
        guard let d = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted]),
              let s = String(data: d, encoding: .utf8) else { return "{}" }
        return s
    }
}

private struct NJCalendarTrainingResult: Codable {
    let resultID: String
    let sessionID: String
    let dateKey: String
    let title: String
    let sport: String
    let category: String
    let sessionType: String?
    let startedAtMs: Int64
    let endedAtMs: Int64
    let durationMin: Double
    let distanceKm: Double
    let avgHeartRateBpm: Double?
    let avgPaceMinPerKm: Double?
    let source: String
    let status: String?
    let notes: String?
}

private struct NJWeeklyWorkoutListSheet: View {
    let entries: [NJWeeklyWorkoutEntry]
    let title: String
    let onExportToLLM: (NJWeeklyWorkoutEntry) -> (ok: Bool, message: String)
    let onDeleteWorkout: (NJWeeklyWorkoutEntry) -> (ok: Bool, message: String)

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(entries) { entry in
                NavigationLink {
                    NJWeeklyWorkoutDetailView(entry: entry, onExportToLLM: onExportToLLM, onDeleteWorkout: onDeleteWorkout)
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(entry.sport)
                            .font(.subheadline)
                        Text(line(entry))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Weekly Workouts")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") { dismiss() }
                }
            }
            .overlay {
                if entries.isEmpty {
                    Text("No workout/sport entries this week.")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func line(_ e: NJWeeklyWorkoutEntry) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateFormat = "EEE MMM d, HH:mm"
        var out = f.string(from: e.startDate)
        out += " · \(fmt(e.durationMin))m"
        if e.distanceKm > 0 { out += " · \(fmt(e.distanceKm))km" }
        out += " · \(e.source)"
        return out
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.minimumFractionDigits = 0
        n.maximumFractionDigits = 1
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }
}

private struct NJWeeklyWorkoutDetailView: View {
    let entry: NJWeeklyWorkoutEntry
    let onExportToLLM: (NJWeeklyWorkoutEntry) -> (ok: Bool, message: String)
    let onDeleteWorkout: (NJWeeklyWorkoutEntry) -> (ok: Bool, message: String)
    @State private var exportStatus: String = ""
    @State private var deleteStatus: String = ""

    var body: some View {
        List {
            row("Sport", entry.sport)
            row("Start", dateTime(entry.startDate))
            row("End", dateTime(entry.endDate))
            row("Duration", "\(fmt(entry.durationMin)) min")
            row("Distance", entry.distanceKm > 0 ? "\(fmt(entry.distanceKm)) km" : "-")
            row("Source", entry.source)
            if entry.canDeleteFromNotionJournal {
                Section("Manage") {
                    Button(role: .destructive) {
                        let r = onDeleteWorkout(entry)
                        deleteStatus = r.ok ? r.message : "Delete failed: \(r.message)"
                    } label: {
                        Label("Delete Notion Journal Workout", systemImage: "trash")
                    }
                    if !deleteStatus.isEmpty {
                        Text(deleteStatus)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Export") {
                Button {
                    let r = onExportToLLM(entry)
                    exportStatus = r.ok ? r.message : "Export failed: \(r.message)"
                } label: {
                    Label("Send to LLM Journal", systemImage: "square.and.arrow.up.on.square")
                }
                if !exportStatus.isEmpty {
                    Text(exportStatus)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Workout Detail")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
            Spacer(minLength: 0)
            Text(v).foregroundStyle(.secondary)
        }
    }

    private func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: d)
    }

    private func fmt(_ v: Double) -> String {
        let n = NumberFormatter()
        n.minimumFractionDigits = 0
        n.maximumFractionDigits = 1
        return n.string(from: NSNumber(value: v)) ?? String(format: "%.1f", v)
    }
}

private enum NJLLMJournalBridge {
    private static let llmContainerID = "iCloud.com.CYC.LLMJournal"

    private struct TxEnvelope: Codable {
        let tx_id: String
        let tx_type: String
        let created_at: String
        let payload: TxPayload
    }

    private struct TxPayload: Codable {
        let device_id: String
        let device_label: String
        let device_kind: String
        let doc_id: String
        let doc_type: String
        let date: String
        let start: String
        let end: String
        let duration: Int
        let domain: String
        let doc_kind: Int
        let path: String
        let comment: String
        let Processed_JSON: String
    }

    static func writeTimeSlot(entry: NJWeeklyWorkoutEntry) throws -> String {
        guard entry.kind == .actual else {
            throw NSError(
                domain: "NJLLMJournalBridge",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Planned workout entries cannot be posted to LLM Journal. Only actual workouts can be exported."]
            )
        }
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: llmContainerID)?
            .appendingPathComponent("Documents", isDirectory: true) else {
            throw NSError(domain: "NJLLMJournalBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "LLMJournal iCloud container unavailable"])
        }

        let txID = UUID().uuidString.lowercased()
        let docID = UUID().uuidString.lowercased()
        let iso = ISO8601DateFormatter()
        let dateKey = ymd(entry.startDate)
        let docType = mapDocType(entry.sport)
        let domain = mapDomain(entry.sport)
        let durationSec = max(0, Int(entry.durationMin * 60.0))

        let year = String(dateKey.prefix(4))
        let month = String(dateKey.dropFirst(5).prefix(2))
        let safeDocType = docType.replacingOccurrences(of: " ", with: "_")
        let filename = "\(dateKey.replacingOccurrences(of: "-", with: ""))_\(safeDocType)_\(docID.prefix(8)).json"
        let relPath = "\(year)/\(month)/\(filename)"
        let docURL = base.appendingPathComponent(relPath)
        try FileManager.default.createDirectory(at: docURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let docBody: [String: Any] = [
            "schema": "notion_workout_timeslot_v1",
            "sport": entry.sport,
            "start_iso": iso.string(from: entry.startDate),
            "end_iso": iso.string(from: entry.endDate),
            "duration_min": entry.durationMin,
            "distance_km": entry.distanceKm,
            "kind": (entry.kind == .planned ? "planned" : "actual"),
            "source": entry.source
        ]
        let docData = try JSONSerialization.data(withJSONObject: docBody, options: [.prettyPrinted, .sortedKeys])
        try docData.write(to: docURL, options: [.atomic])

        let processed: [String: Any] = [
            "NOTION_WORKOUT": [
                "body": docBody
            ]
        ]
        let processedData = try JSONSerialization.data(withJSONObject: processed, options: [])
        let processedJSON = String(data: processedData, encoding: .utf8) ?? "{}"

        let payload = TxPayload(
            device_id: UIDevice.current.identifierForVendor?.uuidString ?? "notion-journal",
            device_label: UIDevice.current.name,
            device_kind: UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone",
            doc_id: docID,
            doc_type: docType,
            date: dateKey,
            start: iso.string(from: entry.startDate),
            end: iso.string(from: entry.endDate),
            duration: durationSec,
            domain: domain,
            doc_kind: 3,
            path: relPath,
            comment: "Imported from Notion Journal: \(entry.sport)",
            Processed_JSON: processedJSON
        )

        let env = TxEnvelope(
            tx_id: txID,
            tx_type: "doc_upsert",
            created_at: iso.string(from: Date()),
            payload: payload
        )

        let inbox = base.appendingPathComponent("Sync/tx_inbox", isDirectory: true)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let txURL = inbox.appendingPathComponent("\(txID).json")

        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        let txData = try enc.encode(env)
        try txData.write(to: txURL, options: [.atomic])

        return txID
    }

    private static func ymd(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private static func mapDocType(_ sport: String) -> String {
        let s = sport.lowercased()
        if s.contains("tennis") { return "Tennis_Practice" }
        if s.contains("cycl") || s.contains("bike") { return "Cycling" }
        if s.contains("hik") { return "Hiking" }
        if s.contains("run") || s.contains("jog") { return "Running" }
        if s.contains("walk") { return "Walking" }
        if s.contains("swim") { return "Swimming" }
        if s.contains("gym") || s.contains("strength") { return "Gym" }
        return "Workout"
    }

    private static func mapDomain(_ sport: String) -> String {
        let s = sport.lowercased()
        if s.contains("tennis") { return "zz.sport.tennis" }
        if s.contains("cycl") || s.contains("bike") { return "zz.sport.cycling" }
        if s.contains("hik") { return "zz.sport.hiking" }
        if s.contains("run") || s.contains("jog") { return "zz.sport.running" }
        if s.contains("walk") { return "zz.sport.walking" }
        if s.contains("swim") { return "zz.sport.swimming" }
        return "zz.sport.training"
    }
}

private struct NJFinanceImportResult {
    let rows: [NJFinanceTransaction]
    let summaryText: String
}

private struct NJFinanceTransactionEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let row: NJFinanceTransaction
    let onSave: (NJFinanceTransaction) -> Void

    @State private var analysisNature: String
    @State private var category: String
    @State private var tagText: String

    init(row: NJFinanceTransaction, onSave: @escaping (NJFinanceTransaction) -> Void) {
        self.row = row
        self.onSave = onSave
        _analysisNature = State(initialValue: row.analysisNature.isEmpty ? row.direction : row.analysisNature)
        _category = State(initialValue: row.category.isEmpty ? "shopping" : row.category)
        _tagText = State(initialValue: row.tagText)
    }

    private let natures = ["expense", "income", "refund", "transfer"]
    private let categories = ["dining", "groceries", "transport", "shopping", "health", "top_up", "transfer", "fees", "other"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Transaction") {
                    Text(row.merchantName.isEmpty ? row.counterparty : row.merchantName)
                    Text(row.sourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                        .foregroundStyle(.secondary)
                    Text("\(row.currencyCode) \(Decimal(row.amountMinor) / Decimal(100))")
                        .foregroundStyle(.secondary)
                }

                Section("Analysis") {
                    Picker("Nature", selection: $analysisNature) {
                        ForEach(natures, id: \.self) { value in
                            Text(value.capitalized).tag(value)
                        }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { value in
                            Text(value.replacingOccurrences(of: "_", with: " ").capitalized).tag(value)
                        }
                    }
                    TextField("Tags", text: $tagText, prompt: Text("zhou zhou, family"))
                    Text("Use commas to separate tags.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("RMB") {
                    Text("Converted for analysis using FX \(String(format: "%.4f", row.fxRateToCNY))")
                    Text("CNY \(Decimal(row.amountCNYMinor) / Decimal(100))")
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit Transaction")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            NJFinanceTransaction(
                                transactionID: row.transactionID,
                                fingerprint: row.fingerprint,
                                sourceType: row.sourceType,
                                accountID: row.accountID,
                                accountLabel: row.accountLabel,
                                externalRef: row.externalRef,
                                occurredAtMs: row.occurredAtMs,
                                dateKey: row.dateKey,
                                merchantName: row.merchantName,
                                amountMinor: row.amountMinor,
                                currencyCode: row.currencyCode,
                                direction: row.direction,
                                analysisNature: analysisNature,
                                category: category,
                                tagText: tagText,
                                fxRateToCNY: row.fxRateToCNY,
                                amountCNYMinor: row.amountCNYMinor,
                                status: row.status,
                                counterparty: row.counterparty,
                                itemName: row.itemName,
                                details: row.details,
                                note: row.note,
                                importBatchID: row.importBatchID,
                                sourceFileName: row.sourceFileName,
                                rawPayloadJSON: row.rawPayloadJSON,
                                createdAtMs: row.createdAtMs,
                                updatedAtMs: DBNoteRepository.nowMs(),
                                deleted: row.deleted
                            )
                        )
                        dismiss()
                    }
                }
            }
        }
    }
}

private enum NJFinanceImportService {
    static func importFile(data: Data, filename: String, nowMs: Int64) throws -> NJFinanceImportResult {
        let lower = filename.lowercased()
        if lower.hasSuffix(".zip") {
            throw NSError(domain: "NJFinanceImport", code: 10, userInfo: [NSLocalizedDescriptionKey: "This WeChat export is still password-protected. Please unzip it first, then import the extracted file."])
        }
        if lower.hasSuffix(".xlsx") {
            throw NSError(domain: "NJFinanceImport", code: 11, userInfo: [NSLocalizedDescriptionKey: "The extracted WeChat file is `.xlsx`. I haven’t wired spreadsheet parsing into the app yet, so for now please convert it to CSV first."])
        }

        let text = try decodeText(data)
        if text.contains("支付宝交易记录明细查询") || (text.contains("交易号") && text.contains("收/支")) {
            return try importAlipayCSV(text: text, filename: filename, nowMs: nowMs)
        }
        if text.contains("微信支付") || (text.contains("交易时间") && text.contains("交易类型")) {
            return try importWeChatCSV(text: text, filename: filename, nowMs: nowMs)
        }

        throw NSError(domain: "NJFinanceImport", code: 12, userInfo: [NSLocalizedDescriptionKey: "I couldn’t recognize this file format yet."])
    }

    static func importOctopusScreenshots(urls: [URL], nowMs: Int64) async throws -> NJFinanceImportResult {
        let batchID = UUID().uuidString.lowercased()
        var allRows: [NJFinanceTransaction] = []
        var seenFingerprints: Set<String> = []

        for url in urls.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer {
                if scoped { url.stopAccessingSecurityScopedResource() }
            }
            guard let image = UIImage(contentsOfFile: url.path),
                  let cgImage = image.cgImage else { continue }
            let lines = try await recognizeLines(cgImage: cgImage)
            let parsed = parseOctopusLines(lines, sourceFileName: url.lastPathComponent, importBatchID: batchID, nowMs: nowMs)
            for row in parsed where seenFingerprints.insert(row.fingerprint).inserted {
                allRows.append(row)
            }
        }

        return NJFinanceImportResult(rows: allRows.sorted { $0.occurredAtMs > $1.occurredAtMs }, summaryText: "Imported \(allRows.count) Octopus transaction(s). Duplicates were skipped.")
    }

    private static func importAlipayCSV(text: String, filename: String, nowMs: Int64) throws -> NJFinanceImportResult {
        let lines = text.components(separatedBy: .newlines)
        let accountLine = lines.first { $0.contains("账号:[") } ?? ""
        let accountID = bracketValue(from: accountLine)
        guard let headerIndex = lines.firstIndex(where: { $0.contains("交易号") && $0.contains("交易状态") }) else {
            throw NSError(domain: "NJFinanceImport", code: 20, userInfo: [NSLocalizedDescriptionKey: "Could not find the Alipay header row."])
        }

        let indexes = keyedIndexes(csvFields(from: lines[headerIndex]))
        let batchID = UUID().uuidString.lowercased()
        var rows: [NJFinanceTransaction] = []

        for rawLine in lines.dropFirst(headerIndex + 1) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            let fields = csvFields(from: rawLine)
            if fields.count < 10 { continue }

            let externalRef = field(named: ["交易号"], indexes: indexes, fields: fields)
            if externalRef.isEmpty { continue }

            let occurredText = field(named: ["付款时间", "交易创建时间", "最近修改时间"], indexes: indexes, fields: fields)
            let occurredAtMs = parseDateTimeMs(occurredText) ?? nowMs
            let merchant = firstNonEmpty([field(named: ["交易对方"], indexes: indexes, fields: fields), field(named: ["商品名称"], indexes: indexes, fields: fields)])
            let amountMinor = decimalMinor(from: field(named: ["金额（元）", "金额(元)"], indexes: indexes, fields: fields))
            let inOut = field(named: ["收/支"], indexes: indexes, fields: fields)
            let fundStatus = field(named: ["资金状态"], indexes: indexes, fields: fields)
            let status = field(named: ["交易状态"], indexes: indexes, fields: fields)
            let direction = mapAlipayDirection(inOut: inOut, fundStatus: fundStatus, status: status)
            if direction == "ignore" { continue }

            let fingerprint = transactionFingerprint(sourceType: "alipay", accountID: accountID, externalRef: externalRef, occurredAtMs: occurredAtMs, merchantName: merchant, amountMinor: amountMinor, currencyCode: "CNY")
            let payload = [
                "trade_no": externalRef,
                "merchant_order_no": field(named: ["商家订单号"], indexes: indexes, fields: fields),
                "type": field(named: ["类型"], indexes: indexes, fields: fields),
                "counterparty": field(named: ["交易对方"], indexes: indexes, fields: fields),
                "item_name": field(named: ["商品名称"], indexes: indexes, fields: fields),
                "note": field(named: ["备注"], indexes: indexes, fields: fields)
            ]

            let category = suggestedCategory(sourceType: "alipay", merchantName: merchant, itemName: field(named: ["商品名称"], indexes: indexes, fields: fields))
            let fxRate = defaultFXRateToCNY(currencyCode: "CNY")
            rows.append(NJFinanceTransaction(transactionID: "alipay.\(fingerprint)", fingerprint: fingerprint, sourceType: "alipay", accountID: accountID, accountLabel: accountID.isEmpty ? "Alipay" : "Alipay \(accountID)", externalRef: externalRef, occurredAtMs: occurredAtMs, dateKey: dateKey(fromMs: occurredAtMs), merchantName: merchant, amountMinor: amountMinor, currencyCode: "CNY", direction: direction, analysisNature: direction, category: category, tagText: "", fxRateToCNY: fxRate, amountCNYMinor: convertedToCNYMinor(amountMinor: amountMinor, fxRateToCNY: fxRate), status: status.isEmpty ? fundStatus : status, counterparty: field(named: ["交易对方"], indexes: indexes, fields: fields), itemName: field(named: ["商品名称"], indexes: indexes, fields: fields), details: "", note: field(named: ["备注"], indexes: indexes, fields: fields), importBatchID: batchID, sourceFileName: filename, rawPayloadJSON: encodeJSON(payload), createdAtMs: nowMs, updatedAtMs: nowMs, deleted: 0))
        }

        let deduped = dedupe(rows)
        return NJFinanceImportResult(rows: deduped, summaryText: "Imported \(deduped.count) Alipay transaction(s). Duplicates were skipped.")
    }

    private static func importWeChatCSV(text: String, filename: String, nowMs: Int64) throws -> NJFinanceImportResult {
        let lines = text.components(separatedBy: .newlines).filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard let headerIndex = lines.firstIndex(where: { $0.contains("交易时间") && $0.contains("交易类型") }) else {
            throw NSError(domain: "NJFinanceImport", code: 30, userInfo: [NSLocalizedDescriptionKey: "Could not find the WeChat bill header row."])
        }
        let indexes = keyedIndexes(csvFields(from: lines[headerIndex]))
        let batchID = UUID().uuidString.lowercased()
        var rows: [NJFinanceTransaction] = []

        for rawLine in lines.dropFirst(headerIndex + 1) {
            let fields = csvFields(from: rawLine)
            if fields.count < 6 { continue }
            let occurredText = field(named: ["交易时间"], indexes: indexes, fields: fields)
            guard let occurredAtMs = parseDateTimeMs(occurredText) else { continue }
            let merchant = firstNonEmpty([field(named: ["交易对方"], indexes: indexes, fields: fields), field(named: ["商品"], indexes: indexes, fields: fields)])
            let amountMinor = decimalMinor(from: field(named: ["金额(元)", "金额(人民币)", "金额"], indexes: indexes, fields: fields))
            let inOut = field(named: ["收/支"], indexes: indexes, fields: fields)
            let status = field(named: ["当前状态", "支付状态"], indexes: indexes, fields: fields)
            let externalRef = firstNonEmpty([field(named: ["交易单号"], indexes: indexes, fields: fields), field(named: ["商户单号"], indexes: indexes, fields: fields)])
            let direction = mapWeChatDirection(inOut: inOut, status: status)
            if direction == "ignore" { continue }

            let fingerprint = transactionFingerprint(sourceType: "wechat_pay", accountID: "wechat_pay", externalRef: externalRef, occurredAtMs: occurredAtMs, merchantName: merchant, amountMinor: amountMinor, currencyCode: "CNY")
            let payload = [
                "trade_type": field(named: ["交易类型"], indexes: indexes, fields: fields),
                "counterparty": field(named: ["交易对方"], indexes: indexes, fields: fields),
                "item_name": field(named: ["商品"], indexes: indexes, fields: fields),
                "payment_method": field(named: ["支付方式"], indexes: indexes, fields: fields),
                "note": field(named: ["备注"], indexes: indexes, fields: fields)
            ]

            let category = suggestedCategory(sourceType: "wechat_pay", merchantName: merchant, itemName: field(named: ["商品"], indexes: indexes, fields: fields))
            let fxRate = defaultFXRateToCNY(currencyCode: "CNY")
            rows.append(NJFinanceTransaction(transactionID: "wechat.\(fingerprint)", fingerprint: fingerprint, sourceType: "wechat_pay", accountID: "wechat_pay", accountLabel: "WeChat Pay", externalRef: externalRef, occurredAtMs: occurredAtMs, dateKey: dateKey(fromMs: occurredAtMs), merchantName: merchant, amountMinor: amountMinor, currencyCode: "CNY", direction: direction, analysisNature: direction, category: category, tagText: "", fxRateToCNY: fxRate, amountCNYMinor: convertedToCNYMinor(amountMinor: amountMinor, fxRateToCNY: fxRate), status: status, counterparty: field(named: ["交易对方"], indexes: indexes, fields: fields), itemName: field(named: ["商品"], indexes: indexes, fields: fields), details: "", note: field(named: ["备注"], indexes: indexes, fields: fields), importBatchID: batchID, sourceFileName: filename, rawPayloadJSON: encodeJSON(payload), createdAtMs: nowMs, updatedAtMs: nowMs, deleted: 0))
        }

        let deduped = dedupe(rows)
        return NJFinanceImportResult(rows: deduped, summaryText: "Imported \(deduped.count) WeChat transaction(s). Duplicates were skipped.")
    }

    private static func parseOctopusLines(_ lines: [String], sourceFileName: String, importBatchID: String, nowMs: Int64) -> [NJFinanceTransaction] {
        let accountLabel = lines.first(where: { $0.lowercased().contains("octopus") }) ?? "Octopus"
        let accountID = lines.first(where: { $0.range(of: #"\d{6,}"#, options: .regularExpression) != nil }) ?? accountLabel
        var rows: [NJFinanceTransaction] = []

        for index in lines.indices {
            guard let occurredAtMs = parseDateTimeMs(lines[index]) else { continue }
            let merchantLine = index > 0 ? lines[index - 1] : ""
            var signedMinor = amountMinorAtEnd(of: merchantLine)
            if signedMinor == nil, index + 1 < lines.count {
                signedMinor = amountMinorAtEnd(of: lines[index + 1])
            }
            let merchant = stripAmountSuffix(from: merchantLine)
            guard let signedMinor else { continue }
            guard !merchant.isEmpty,
                  !merchant.lowercased().contains("remaining value"),
                  !merchant.lowercased().contains("transaction history"),
                  !merchant.lowercased().contains("update transaction history"),
                  !merchant.lowercased().contains("spending summary") else { continue }

            let direction = signedMinor >= 0 ? "income" : "expense"
            let fingerprint = transactionFingerprint(sourceType: "octopus", accountID: accountID, externalRef: "", occurredAtMs: occurredAtMs, merchantName: merchant, amountMinor: abs(signedMinor), currencyCode: "HKD")
            let payload = ["ocr_source": sourceFileName, "merchant_line": merchantLine, "date_line": lines[index]]

            let amountMinor = abs(signedMinor)
            let fxRate = defaultFXRateToCNY(currencyCode: "HKD")
            rows.append(NJFinanceTransaction(transactionID: "octopus.\(fingerprint)", fingerprint: fingerprint, sourceType: "octopus", accountID: accountID, accountLabel: accountLabel, externalRef: "", occurredAtMs: occurredAtMs, dateKey: dateKey(fromMs: occurredAtMs), merchantName: merchant, amountMinor: amountMinor, currencyCode: "HKD", direction: direction, analysisNature: direction, category: suggestedCategory(sourceType: "octopus", merchantName: merchant, itemName: ""), tagText: "", fxRateToCNY: fxRate, amountCNYMinor: convertedToCNYMinor(amountMinor: amountMinor, fxRateToCNY: fxRate), status: "posted", counterparty: merchant, itemName: "", details: "", note: "", importBatchID: importBatchID, sourceFileName: sourceFileName, rawPayloadJSON: encodeJSON(payload), createdAtMs: nowMs, updatedAtMs: nowMs, deleted: 0))
        }

        return dedupe(rows)
    }

    private static func recognizeLines(cgImage: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = (request.results as? [VNRecognizedTextObservation]) ?? []
                let items = observations.compactMap { obs -> (String, CGRect)? in
                    guard let candidate = obs.topCandidates(1).first else { return nil }
                    return (candidate.string, obs.boundingBox)
                }
                continuation.resume(returning: mergeRecognizedRows(items))
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

            DispatchQueue.global(qos: .userInitiated).async {
                let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
                do {
                    try handler.perform([request])
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private static func mergeRecognizedRows(_ items: [(String, CGRect)]) -> [String] {
        let sorted = items.sorted {
            let dy = $0.1.midY - $1.1.midY
            if abs(dy) > 0.012 { return $0.1.midY > $1.1.midY }
            return $0.1.minX < $1.1.minX
        }
        var rows: [[(String, CGRect)]] = []
        for item in sorted {
            if let lastIndex = rows.indices.last,
               let sample = rows[lastIndex].first,
               abs(sample.1.midY - item.1.midY) < 0.012 {
                rows[lastIndex].append(item)
            } else {
                rows.append([item])
            }
        }
        return rows.map { row in
            row.sorted { $0.1.minX < $1.1.minX }
                .map { $0.0.replacingOccurrences(of: "\n", with: " ") }
                .joined(separator: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty }
    }

    private static func decodeText(_ data: Data) throws -> String {
        if let text = String(data: data, encoding: .utf8), !text.isEmpty { return text }
        if let text = String(data: data, encoding: .unicode), !text.isEmpty { return text }
        for encoding in [CFStringEncodings.GB_18030_2000, .GBK_95] {
            let nsEncoding = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(encoding.rawValue))
            if let text = String(data: data, encoding: String.Encoding(rawValue: nsEncoding)), !text.isEmpty {
                return text
            }
        }
        throw NSError(domain: "NJFinanceImport", code: 40, userInfo: [NSLocalizedDescriptionKey: "Unable to decode the file text encoding."])
    }

    private static func csvFields(from line: String) -> [String] {
        var out: [String] = []
        var current = ""
        var inQuotes = false
        for ch in line {
            if ch == "\"" {
                inQuotes.toggle()
                continue
            }
            if ch == "," && !inQuotes {
                out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
                current.removeAll(keepingCapacity: true)
            } else {
                current.append(ch)
            }
        }
        out.append(current.trimmingCharacters(in: .whitespacesAndNewlines))
        return out
    }

    private static func keyedIndexes(_ headers: [String]) -> [String: Int] {
        var out: [String: Int] = [:]
        for (idx, raw) in headers.enumerated() {
            out[normalizeHeader(raw)] = idx
        }
        return out
    }

    private static func field(named candidates: [String], indexes: [String: Int], fields: [String]) -> String {
        for candidate in candidates {
            if let index = indexes[normalizeHeader(candidate)], fields.indices.contains(index) {
                return fields[index].trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private static func normalizeHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "（", with: "(")
            .replacingOccurrences(of: "）", with: ")")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\t", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func bracketValue(from line: String) -> String {
        guard let start = line.firstIndex(of: "["), let end = line.firstIndex(of: "]"), start < end else { return "" }
        return String(line[line.index(after: start)..<end]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseDateTimeMs(_ value: String) -> Int64? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd HH:mm"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return Int64(date.timeIntervalSince1970 * 1000.0)
            }
        }
        return nil
    }

    private static func decimalMinor(from value: String) -> Int64 {
        let cleaned = value.replacingOccurrences(of: ",", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard let decimal = Decimal(string: cleaned) else { return 0 }
        return NSDecimalNumber(decimal: decimal * Decimal(100)).int64Value
    }

    private static func amountMinorAtEnd(of line: String) -> Int64? {
        guard let range = line.range(of: #"[-+]?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) else { return nil }
        return decimalMinor(from: String(line[range]))
    }

    private static func stripAmountSuffix(from line: String) -> String {
        guard let range = line.range(of: #"[-+]?\d+(?:\.\d{1,2})?$"#, options: .regularExpression) else { return line }
        var copy = line
        copy.removeSubrange(range)
        return copy.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func mapAlipayDirection(inOut: String, fundStatus: String, status: String) -> String {
        let combined = "\(inOut)|\(fundStatus)|\(status)"
        if combined.contains("退款") || combined.contains("已收入") { return "refund" }
        if inOut.contains("不计收支") { return "ignore" }
        if status.contains("关闭") || status.contains("等待付款") || status.contains("待付款") || status.contains("未付款") || status.contains("支付中") {
            return "ignore"
        }
        if fundStatus.contains("待支出") || fundStatus.contains("未支出") {
            return "ignore"
        }
        if inOut.contains("收入") { return "income" }
        if inOut.contains("支出") { return "expense" }
        return "expense"
    }

    private static func mapWeChatDirection(inOut: String, status: String) -> String {
        if status.contains("退款") || inOut.contains("收入") { return "refund" }
        if inOut.contains("支出") { return "expense" }
        if status.contains("关闭") || status.contains("撤销") { return "ignore" }
        return "expense"
    }

    private static func defaultFXRateToCNY(currencyCode: String) -> Double {
        switch currencyCode.uppercased() {
        case "HKD":
            return 0.93
        default:
            return 1.0
        }
    }

    private static func convertedToCNYMinor(amountMinor: Int64, fxRateToCNY: Double) -> Int64 {
        Int64((Double(amountMinor) * fxRateToCNY).rounded())
    }

    private static func suggestedCategory(sourceType: String, merchantName: String, itemName: String) -> String {
        let text = "\(merchantName) \(itemName)".lowercased()
        if sourceType == "octopus" {
            if text.contains("mtr") || text.contains("bus") || text.contains("minibus") || text.contains("trans-island") {
                return "transport"
            }
            if text.contains("octopus cards limited") {
                return "top_up"
            }
        }
        if text.contains("cafe") || text.contains("starbucks") || text.contains("burger") || text.contains("shake shack") || text.contains("mcdonald") || text.contains("fairwood") || text.contains("mos") || text.contains("yoshinoya") || text.contains("hana-musubi") || text.contains("saint honore") || text.contains("satay king") || text.contains("pepper lunch") || text.contains("food republic") {
            return "dining"
        }
        if text.contains("美团") || text.contains("美团外卖") || text.contains("饿了么") || text.contains("餐饮") || text.contains("餐厅") || text.contains("饭店") || text.contains("饭堂") || text.contains("食堂") || text.contains("快餐") || text.contains("外卖") || text.contains("奶茶") || text.contains("咖啡") || text.contains("烧味") || text.contains("烧腊") || text.contains("粥") || text.contains("粉") || text.contains("面") || text.contains("米线") || text.contains("米粉") || text.contains("肠粉") || text.contains("腸粉") || text.contains("云吞") || text.contains("餛飩") || text.contains("包子") || text.contains("饺子") || text.contains("餃子") || text.contains("茶餐厅") || text.contains("茶餐廳") || text.contains("小吃") || text.contains("麻辣烫") || text.contains("麻辣燙") || text.contains("火锅") || text.contains("火鍋") || text.contains("烤肉") || text.contains("汉堡") || text.contains("漢堡") || text.contains("pizza") || text.contains("pasta") {
            return "dining"
        }
        if text.contains("manning") || text.contains("7-eleven") || text.contains("dai sang") || text.contains("grocer") || text.contains("hema") || text.contains("盒马") {
            return "groceries"
        }
        if text.contains("超市") || text.contains("便利店") || text.contains("百货") || text.contains("百貨") || text.contains("生鲜") || text.contains("生鮮") || text.contains("菜市场") || text.contains("菜市場") || text.contains("果蔬") || text.contains("水果") || text.contains("杂货") || text.contains("雜貨") {
            return "groceries"
        }
        if text.contains("mtr") || text.contains("bus") || text.contains("深圳通") || text.contains("地铁") {
            return "transport"
        }
        if text.contains("打车") || text.contains("打車") || text.contains("出租车") || text.contains("出租車") || text.contains("滴滴") || text.contains("代驾") || text.contains("代駕") || text.contains("停车") || text.contains("停車") || text.contains("停车场") || text.contains("停車場") || text.contains("过路") || text.contains("過路") || text.contains("充电站") || text.contains("充電站") || text.contains("充电桩") || text.contains("充電樁") || text.contains("特来电") || text.contains("特來電") || text.contains("星星充电") || text.contains("星星充電") || text.contains("小桔充电") || text.contains("小桔充電") || text.contains("蔚来能源") || text.contains("蔚來能源") {
            return "transport"
        }
        if text.contains("coca-cola") || text.contains("milk") {
            return "groceries"
        }
        if text.contains("rehabilitation") || text.contains("psychiatric") || text.contains("hospital") || text.contains("clinic") || text.contains("药") {
            return "health"
        }
        if text.contains("top up") || text.contains("充值") {
            return "top_up"
        }
        return "shopping"
    }

    private static func transactionFingerprint(sourceType: String, accountID: String, externalRef: String, occurredAtMs: Int64, merchantName: String, amountMinor: Int64, currencyCode: String) -> String {
        let parts = [sourceType.lowercased(), accountID.lowercased(), externalRef.lowercased(), String(occurredAtMs), merchantName.lowercased().trimmingCharacters(in: .whitespacesAndNewlines), String(amountMinor), currencyCode.uppercased()]
        let data = Data(parts.joined(separator: "|").utf8)
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }

    private static func dateKey(fromMs value: Int64) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 8)
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date(timeIntervalSince1970: TimeInterval(value) / 1000.0))
    }

    private static func encodeJSON(_ value: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let text = String(data: data, encoding: .utf8) else { return "{}" }
        return text
    }

    private static func dedupe(_ rows: [NJFinanceTransaction]) -> [NJFinanceTransaction] {
        var out: [NJFinanceTransaction] = []
        var seen: Set<String> = []
        for row in rows where seen.insert(row.fingerprint).inserted {
            out.append(row)
        }
        return out
    }

    private static func firstNonEmpty(_ values: [String]) -> String {
        values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) ?? ""
    }
}
