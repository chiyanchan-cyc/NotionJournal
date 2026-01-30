import Foundation
import Combine
import CoreLocation
import UIKit
import MapKit

final class NJGPSLogger: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = NJGPSLogger()

    @Published private(set) var enabled: Bool
    @Published private(set) var isWriter: Bool = false
    @Published private(set) var auth: CLAuthorizationStatus = .notDetermined
    @Published private(set) var writerLabel: String = ""
    @Published private(set) var lastWriteTsMs: Int64 = 0
    @Published private(set) var lastError: String = ""

    private let mgr = CLLocationManager()
    private let defaultsKey = "NJGPSLogger.enabled.v1"
    private let powerKey = "NJGPSLogger.power.v1"

    enum NJGPSPower: String, CaseIterable, Identifiable {
        case minimal
        case low10m
        case med5m
        case high
        case crazy
        var id: String { rawValue }

        var title: String {
            switch self {
            case .minimal: return "Minimal"
            case .low10m: return "Low (10m)"
            case .med5m: return "Med (5m)"
            case .high: return "High"
            case .crazy: return "Crazy"
            }
        }
    }

    @Published private(set) var power: NJGPSPower

    private struct PowerConfig {
        let continuous: Bool
        let desiredAccuracy: CLLocationAccuracy
        let distanceFilter: CLLocationDistance
        let pauses: Bool
        let activityType: CLActivityType
        let deferUntilTraveledM: CLLocationDistance?
        let deferTimeoutS: TimeInterval?
        let minWriteIntervalMs: Int64
    }

    private var minWriteIntervalMs: Int64 = 0

    private let containerID = "iCloud.com.CYC.NotionJournal"
    private let lockRel = "GPS/gps_logger_lock.json"
    private let lockTTLms: Int64 = 36 * 60 * 60 * 1000

    private var didStartContinuous = false

    private override init() {
        self.enabled = UserDefaults.standard.bool(forKey: defaultsKey)
        if let raw = UserDefaults.standard.string(forKey: powerKey),
           let p = NJGPSPower(rawValue: raw) {
            self.power = p
        } else {
            self.power = .low10m
        }
        super.init()
        mgr.delegate = self
        mgr.showsBackgroundLocationIndicator = false
        auth = mgr.authorizationStatus
        Task { @MainActor in
            await refreshAuthority()
            if enabled { startIfPossible() }
        }
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
        enabled = on
        lastError = ""
        if on { startIfPossible() } else { stopAll() }
    }
    
    func setPower(_ p: NJGPSPower) {
        UserDefaults.standard.set(p.rawValue, forKey: powerKey)
        power = p
        if enabled { startIfPossible() }
    }

    func requestAlways() {
        mgr.requestAlwaysAuthorization()
    }

    func requestWhenInUse() {
        mgr.requestWhenInUseAuthorization()
    }

    func refreshAuthorityUI() {
        Task { @MainActor in
            await refreshAuthority()
            if enabled { startIfPossible() }
        }
    }

    private func startIfPossible() {
        auth = mgr.authorizationStatus
        guard enabled else { return }
        guard auth == .authorizedAlways || auth == .authorizedWhenInUse else { return }
        Task { @MainActor in
            await refreshAuthority()
            if isWriter {
                startMonitors()
            } else {
                stopMonitors()
            }
        }
    }

    private func startMonitors() {
        stopMonitors()

        if mgr.authorizationStatus == .authorizedAlways {
            mgr.allowsBackgroundLocationUpdates = true
        } else {
            mgr.allowsBackgroundLocationUpdates = false
        }

        mgr.startMonitoringSignificantLocationChanges()
        mgr.startMonitoringVisits()

        let cfg = powerConfig(power)
        mgr.desiredAccuracy = cfg.desiredAccuracy
        mgr.distanceFilter = cfg.distanceFilter
        mgr.activityType = cfg.activityType
        mgr.pausesLocationUpdatesAutomatically = cfg.pauses
        minWriteIntervalMs = cfg.minWriteIntervalMs

        if cfg.continuous {
            mgr.startUpdatingLocation()
            didStartContinuous = true

            if CLLocationManager.deferredLocationUpdatesAvailable(),
               let ut = cfg.deferUntilTraveledM,
               let to = cfg.deferTimeoutS {
                mgr.allowDeferredLocationUpdates(untilTraveled: ut, timeout: to)
            }
        } else {
            didStartContinuous = false
        }
    }

    private func powerConfig(_ p: NJGPSPower) -> PowerConfig {
        switch p {
        case .minimal:
            return PowerConfig(
                continuous: false,
                desiredAccuracy: kCLLocationAccuracyThreeKilometers,
                distanceFilter: 1000,
                pauses: true,
                activityType: .other,
                deferUntilTraveledM: nil,
                deferTimeoutS: nil,
                minWriteIntervalMs: 0
            )

        case .low10m:
            return PowerConfig(
                continuous: true,
                desiredAccuracy: kCLLocationAccuracyKilometer,
                distanceFilter: 500,
                pauses: true,
                activityType: .other,
                deferUntilTraveledM: 8000,
                deferTimeoutS: 600,
                minWriteIntervalMs: 10 * 60 * 1000
            )

        case .med5m:
            return PowerConfig(
                continuous: true,
                desiredAccuracy: kCLLocationAccuracyKilometer,
                distanceFilter: 250,
                pauses: true,
                activityType: .other,
                deferUntilTraveledM: 5000,
                deferTimeoutS: 300,
                minWriteIntervalMs: 5 * 60 * 1000
            )

        case .high:
            return PowerConfig(
                continuous: true,
                desiredAccuracy: kCLLocationAccuracyHundredMeters,
                distanceFilter: 50,
                pauses: true,
                activityType: .fitness,
                deferUntilTraveledM: 1500,
                deferTimeoutS: 180,
                minWriteIntervalMs: 30 * 1000
            )

        case .crazy:
            return PowerConfig(
                continuous: true,
                desiredAccuracy: kCLLocationAccuracyBest,
                distanceFilter: 10,
                pauses: false,
                activityType: .fitness,
                deferUntilTraveledM: 500,
                deferTimeoutS: 60,
                minWriteIntervalMs: 5 * 1000
            )
        }
    }


    private func stopMonitors() {
        mgr.stopMonitoringSignificantLocationChanges()
        mgr.stopMonitoringVisits()

        if didStartContinuous {
            mgr.disallowDeferredLocationUpdates()
            mgr.stopUpdatingLocation()
            didStartContinuous = false
        }
    }

    private func stopAll() {
        stopMonitors()
        isWriter = false
        writerLabel = ""
    }

    private func nowMs() -> Int64 {
        Int64(Date().timeIntervalSince1970 * 1000.0)
    }

    private func deviceID() -> String {
        UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
    }

    private func deviceLabel() -> String {
        UIDevice.current.name
    }

    private func docsRoot() -> URL? {
        if let u = FileManager.default.url(forUbiquityContainerIdentifier: containerID) {
            return u.appendingPathComponent("Documents", isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    private func ensureDir(_ u: URL) {
        try? FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
    }

    private func lockURL() -> URL? {
        guard let root = docsRoot() else { return nil }
        let u = root.appendingPathComponent(lockRel)
        ensureDir(u.deletingLastPathComponent())
        return u
    }

    private struct LockFile: Codable {
        let v: Int
        let device_id: String
        let device_label: String
        let issued_ts_ms: Int64
        let heartbeat_ts_ms: Int64
        let ttl_ms: Int64
    }

    @MainActor
    private func refreshAuthority() async {
        let now = nowMs()
        let myID = deviceID()
        let myLabel = deviceLabel()

        guard let lu = lockURL() else {
            isWriter = false
            writerLabel = ""
            lastError = "no_docs_root"
            return
        }

        let existing: LockFile? = {
            guard let d = try? Data(contentsOf: lu) else { return nil }
            return try? JSONDecoder().decode(LockFile.self, from: d)
        }()

        let expired: Bool = {
            guard let ex = existing else { return true }
            return (now - ex.heartbeat_ts_ms) > ex.ttl_ms
        }()

        if existing == nil || expired {
            let lf = LockFile(v: 1, device_id: myID, device_label: myLabel, issued_ts_ms: now, heartbeat_ts_ms: now, ttl_ms: lockTTLms)
            if let d = try? JSONEncoder().encode(lf) {
                try? d.write(to: lu, options: .atomic)
            }
            isWriter = true
            writerLabel = myLabel
            return
        }

        guard let ex = existing else { return }

        if ex.device_id == myID {
            let lf = LockFile(v: 1, device_id: myID, device_label: myLabel, issued_ts_ms: ex.issued_ts_ms, heartbeat_ts_ms: now, ttl_ms: lockTTLms)
            if let d = try? JSONEncoder().encode(lf) {
                try? d.write(to: lu, options: .atomic)
            }
            isWriter = true
            writerLabel = myLabel
            return
        }

        isWriter = false
        writerLabel = ex.device_label
    }

    private func bumpHeartbeat() {
        let now = nowMs()
        guard let lu = lockURL() else { return }
        guard let d = try? Data(contentsOf: lu) else { return }
        guard let ex = try? JSONDecoder().decode(LockFile.self, from: d) else { return }
        guard ex.device_id == deviceID() else { return }
        let lf = LockFile(v: 1, device_id: ex.device_id, device_label: ex.device_label, issued_ts_ms: ex.issued_ts_ms, heartbeat_ts_ms: now, ttl_ms: lockTTLms)
        if let nd = try? JSONEncoder().encode(lf) {
            try? nd.write(to: lu, options: .atomic)
        }
    }

    private func todayPath() -> URL? {
        guard let root = docsRoot() else { return nil }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "Asia/Hong_Kong") ?? .current
        f.dateFormat = "yyyy/MM/yyyy-MM-dd"
        let rel = "GPS/\(f.string(from: Date())).ndjson"
        let u = root.appendingPathComponent(rel)
        ensureDir(u.deletingLastPathComponent())
        return u
    }

    private func appendLine(_ line: String) {
        guard let u = todayPath() else { return }
        let data = (line + "\n").data(using: .utf8) ?? Data()
        if FileManager.default.fileExists(atPath: u.path) {
            if let h = try? FileHandle(forWritingTo: u) {
                try? h.seekToEnd()
                try? h.write(contentsOf: data)
                try? h.close()
            }
        } else {
            try? data.write(to: u, options: .atomic)
        }
        lastWriteTsMs = nowMs()
        bumpHeartbeat()
    }

    private func encode(tsMs: Int64, lat: Double, lon: Double, hacc: Double, src: String) -> String {
        let id = deviceID()
        return #"{"ts_ms":\#(tsMs),"lat":\#(lat),"lon":\#(lon),"hacc_m":\#(hacc),"src":"\#(src)","device_id":"\#(id)"}"#
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        auth = mgr.authorizationStatus
        if enabled { startIfPossible() }
    }

    // Add this function to NJGPSLogger class (put it near other public functions)
    func forceClearLock() {
        guard let lu = lockURL() else { return }
        
        do {
            try FileManager.default.removeItem(at: lu)
            print("✅ Lock file deleted at: \(lu.path)")
            lastError = "Lock cleared"
        } catch {
            print("❌ Failed to delete lock: \(error)")
            lastError = "Failed to clear lock: \(error.localizedDescription)"
        }
        
        // Force refresh to become writer
        Task { @MainActor in
            await refreshAuthority()
            if enabled { startIfPossible() }
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard enabled, isWriter else { return }
        guard let loc = locations.last else { return }
        let acc = loc.horizontalAccuracy
        if acc < 0 { return }
        if acc > 300 { return }

        let tsMs = Int64(loc.timestamp.timeIntervalSince1970 * 1000.0)
        if minWriteIntervalMs > 0, lastWriteTsMs > 0, (tsMs - lastWriteTsMs) < minWriteIntervalMs {
            return
        }

        appendLine(
            encode(
                tsMs: tsMs,
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                hacc: acc,
                src: "loc"
            )
        )

        if CLLocationManager.deferredLocationUpdatesAvailable() {
            let cfg = powerConfig(power)
            if let ut = cfg.deferUntilTraveledM, let to = cfg.deferTimeoutS {
                mgr.allowDeferredLocationUpdates(untilTraveled: ut, timeout: to)
            }
        }

    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        guard enabled, isWriter else { return }
        guard visit.coordinate.latitude != 0 || visit.coordinate.longitude != 0 else { return }
        let ts = (visit.arrivalDate == Date.distantPast) ? visit.departureDate : visit.arrivalDate
        appendLine(
            encode(
                tsMs: Int64(ts.timeIntervalSince1970 * 1000.0),
                lat: visit.coordinate.latitude,
                lon: visit.coordinate.longitude,
                hacc: 200,
                src: "visit"
            )
        )
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        lastError = String(describing: error)
    }
}

extension NJGPSLogger {
    func docsRootForViewer() -> URL? {
        if let u = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") {
            return u.appendingPathComponent("Documents", isDirectory: true)
        }
        return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }
}
