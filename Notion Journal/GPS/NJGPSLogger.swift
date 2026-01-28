//
//  NJGPSLogger.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/28.
//


import Foundation
import CoreLocation
import UIKit

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

    private let containerID = "iCloud.com.CYC.HomeLLMJournal"
    private let lockRel = "GPS/gps_logger_lock.json"
    private let lockTTLms: Int64 = 36 * 60 * 60 * 1000

    private override init() {
        self.enabled = UserDefaults.standard.bool(forKey: defaultsKey)
        super.init()
        mgr.delegate = self
        mgr.desiredAccuracy = kCLLocationAccuracyHundredMeters
        mgr.distanceFilter = kCLDistanceFilterNone
        mgr.pausesLocationUpdatesAutomatically = true
        mgr.allowsBackgroundLocationUpdates = true
        auth = CLLocationManager.authorizationStatus()
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

    func requestAlways() {
        mgr.requestAlwaysAuthorization()
    }

    func refreshAuthorityUI() {
        Task { @MainActor in
            await refreshAuthority()
            if enabled { startIfPossible() }
        }
    }

    private func startIfPossible() {
        auth = CLLocationManager.authorizationStatus()
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
        mgr.startMonitoringSignificantLocationChanges()
        mgr.startMonitoringVisits()
    }

    private func stopMonitors() {
        mgr.stopMonitoringSignificantLocationChanges()
        mgr.stopMonitoringVisits()
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
        auth = CLLocationManager.authorizationStatus()
        if enabled { startIfPossible() }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard enabled, isWriter else { return }
        guard let loc = locations.last else { return }
        appendLine(
            encode(
                tsMs: Int64(loc.timestamp.timeIntervalSince1970 * 1000.0),
                lat: loc.coordinate.latitude,
                lon: loc.coordinate.longitude,
                hacc: loc.horizontalAccuracy,
                src: "sig_change"
            )
        )
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
