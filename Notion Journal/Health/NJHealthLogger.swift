import Foundation
import Combine
import UIKit

#if canImport(HealthKit)
import HealthKit
import SQLite3
#endif

enum NJHealthAuthStatus: String {
    case notAvailable
    case notDetermined
    case authorized
    case denied
    case error
}

final class NJHealthLogger: NSObject, ObservableObject {
    static let shared = NJHealthLogger()

    @Published private(set) var enabled: Bool
    @Published private(set) var auth: NJHealthAuthStatus = .notDetermined
    @Published private(set) var isWriter: Bool = false
    @Published private(set) var writerLabel: String = ""
    @Published private(set) var lastSyncTsMs: Int64 = 0
    @Published private(set) var lastError: String = ""
    @Published private(set) var lastSyncSummary: String = ""
    @Published private(set) var medicationDoseEnabled: Bool
    @Published private(set) var medicationDoseCount7d: Int = 0

    private let defaultsKey = "NJHealthLogger.enabled.v1"
    private let lastSyncKey = "NJHealthLogger.lastSyncMs.v1"
    private let medDoseEnabledKey = "NJHealthLogger.medicationDoseEnabled.v1"

    private let containerID = "iCloud.com.CYC.NotionJournal"
    private let lockRel = "Health/health_logger_lock.json"
    private let lockTTLms: Int64 = 36 * 60 * 60 * 1000

    private var db: SQLiteDB?

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    private override init() {
        self.enabled = UserDefaults.standard.bool(forKey: defaultsKey)
        self.lastSyncTsMs = Int64(UserDefaults.standard.double(forKey: lastSyncKey))
        self.medicationDoseEnabled = UserDefaults.standard.bool(forKey: medDoseEnabledKey)
        super.init()

        Task { @MainActor in
            await refreshAuthority()
            if enabled { await syncIfPossible(force: false, reason: "app_start") }
        }
    }

    func configure(db: SQLiteDB) {
        if self.db != nil { return }
        self.db = db
    }

    func setEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: defaultsKey)
        enabled = on
        lastError = ""
        Task { @MainActor in
            await refreshAuthority()
            if on { await syncIfPossible(force: true, reason: "toggle_on") }
        }
    }

    func refreshAuthorityUI() {
        Task { @MainActor in
            await refreshAuthority()
        }
    }

    func setMedicationDoseEnabled(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: medDoseEnabledKey)
        medicationDoseEnabled = on
    }

    func requestAuthorization() {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            auth = .notAvailable
            lastError = "Health data not available"
            return
        }

        Task { [weak self] in
            guard let self else { return }
            let types = self.requestedReadTypes()
            DispatchQueue.main.async {
                self.store.requestAuthorization(toShare: [], read: types) { ok, err in
                    DispatchQueue.main.async {
                        if let err { self.lastError = err.localizedDescription }
                        self.auth = ok ? .authorized : .denied
                        Task { @MainActor in
                            await self.refreshAuthority()
                            if self.enabled { await self.syncIfPossible(force: true, reason: "auth_granted") }
                        }
                    }
                }
            }
        }
        #else
        auth = .notAvailable
        lastError = "HealthKit not available on this platform"
        #endif
    }

    func requestMedicationDoseAuthorization() {
        #if canImport(HealthKit)
        guard supportsMedicationDose() else {
            lastError = "Medication dose authorization disabled for this build"
            return
        }
        guard medicationDoseEnabled else {
            lastError = "Turn on Medication Dose Sync first"
            return
        }
        if #available(iOS 26.0, *) {
            let medType = HKObjectType.userAnnotatedMedicationType()
            store.requestPerObjectReadAuthorization(for: medType, predicate: nil) { ok, err in
                DispatchQueue.main.async {
                    if let err {
                        self.lastError = err.localizedDescription
                    } else if !ok {
                        self.lastError = "Medication authorization canceled or denied"
                    } else {
                        self.lastError = ""
                        Task { @MainActor in
                            await self.backfillMedicationDoseHistory(days: 365)
                            await self.syncIfPossible(force: true, reason: "med_auth_granted")
                        }
                    }
                }
            }
        }
        #else
        lastError = "HealthKit not available on this platform"
        #endif
    }

    func syncNow() {
        Task { @MainActor in
            await syncIfPossible(force: true, reason: "manual")
        }
    }

    func resetHealthSamplesAndResync() {
        guard let db else { return }
        db.exec("DELETE FROM health_samples;")
        lastSyncTsMs = 0
        UserDefaults.standard.set(Double(lastSyncTsMs), forKey: lastSyncKey)
        lastSyncSummary = "Cleared health samples"
        Task { @MainActor in
            await syncIfPossible(force: true, reason: "reset_and_resync")
        }
    }

    func appDidBecomeActive() {
        Task { @MainActor in
            await syncIfPossible(force: false, reason: "app_active")
        }
    }

    @MainActor
    private func refreshAuthority() async {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            auth = .notAvailable
            isWriter = false
            writerLabel = ""
            return
        }

        let types = baseReadTypes()
        if types.isEmpty {
            auth = .notAvailable
            isWriter = false
            writerLabel = ""
            return
        }

        // authorizationStatus(for:) is for *write* permissions; use request status for read access.
        if #available(iOS 12.0, *) {
            let status = await requestStatusForAuthorization(read: types)
            switch status {
            case .unnecessary: auth = .authorized
            case .shouldRequest: auth = .notDetermined
            case .unknown: auth = .error
            @unknown default: auth = .error
            }
        } else {
            auth = .notDetermined
        }

        await refreshWriterLock()
        #else
        auth = .notAvailable
        isWriter = false
        writerLabel = ""
        #endif
    }

    @MainActor
    private func syncIfPossible(force: Bool, reason: String) async {
        guard enabled else { return }
        guard auth == .authorized else { return }
        guard db != nil else { return }

        let now = nowMs()
        let minIntervalMs: Int64 = 5 * 60 * 1000
        if !force, lastSyncTsMs > 0, (now - lastSyncTsMs) < minIntervalMs {
            return
        }

        await performSync()
    }

    @MainActor
    private func performSync() async {
        #if canImport(HealthKit)
        guard let db else { return }

        lastError = ""
        lastSyncSummary = "Syncing…"

        let now = Date()
        let start = initialSyncStartDate()

        let samplesTable = DBHealthSamplesTable(db: db)
        var inserted = 0

        let qtyTypes = quantityTypes()
        for qt in qtyTypes {
            let rows = await fetchQuantitySamples(type: qt, start: start, end: now)
            inserted += samplesTable.insert(quantitySamples: rows)
        }

        let catTypes = categoryTypes()
        for ct in catTypes {
            let rows = await fetchCategorySamples(type: ct, start: start, end: now)
            inserted += samplesTable.insert(categorySamples: rows)
        }

        let workouts = await fetchWorkouts(start: start, end: now)
        inserted += samplesTable.insert(workoutSamples: workouts)

        if medicationDoseEnabled, supportsMedicationDose() {
            if #available(iOS 26.0, *) {
                let doseEvents = await fetchMedicationDoseEvents(start: start, end: now)
                inserted += samplesTable.insert(medicationDoseEvents: doseEvents)
            }
        }

        lastSyncTsMs = nowMs()
        UserDefaults.standard.set(Double(lastSyncTsMs), forKey: lastSyncKey)
        lastSyncSummary = "Inserted \(inserted) samples"
        medicationDoseCount7d = countMedicationDoseSamplesRecent(days: 7)
        bumpHeartbeat()
        #else
        lastError = "HealthKit not available on this platform"
        lastSyncSummary = ""
        #endif
    }

    private func initialSyncStartDate() -> Date {
        let now = Date()
        if lastSyncTsMs > 0 {
            let last = Date(timeIntervalSince1970: TimeInterval(lastSyncTsMs) / 1000.0)
            return last.addingTimeInterval(-12 * 60 * 60)
        }
        return Calendar.current.date(byAdding: .day, value: -90, to: now) ?? now
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
    private func refreshWriterLock() async {
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
        let lf = LockFile(v: 1, device_id: ex.device_id, device_label: ex.device_label, issued_ts_ms: ex.issued_ts_ms, heartbeat_ts_ms: now, ttl_ms: ex.ttl_ms)
        if let nd = try? JSONEncoder().encode(lf) {
            try? nd.write(to: lu, options: .atomic)
        }
    }

    #if canImport(HealthKit)
    private func baseReadTypes() -> Set<HKObjectType> {
        var types: Set<HKObjectType> = []

        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        if let bpS = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) {
            types.insert(bpS)
        }
        if let bpD = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(bpD)
        }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) {
            types.insert(weight)
        }

        types.insert(HKObjectType.workoutType())

        return types
    }

    private func requestedReadTypes() -> Set<HKObjectType> {
        baseReadTypes()
    }

    private func supportsMedicationDose() -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard #available(iOS 26.0, *) else { return false }
        // Hard gate: medication-dose auth currently throws runtime exceptions on
        // builds that are missing the required signing entitlement shape.
        // Enable only when explicitly opted in via Info.plist after signing is verified.
        let flag = Bundle.main.object(forInfoDictionaryKey: "NJEnableMedicationDoseAuth")
        return (flag as? Bool) == true
    }

    private func countMedicationDoseSamplesRecent(days: Int) -> Int {
        guard let db else { return 0 }
        let now = nowMs()
        let startMs = now - Int64(days) * 24 * 60 * 60 * 1000
        let sql = """
        SELECT COUNT(*) AS c
        FROM health_samples
        WHERE type = 'medication_dose'
          AND start_ms >= \(startMs);
        """
        let rows = db.queryRows(sql)
        return Int(rows.first?["c"] ?? "0") ?? 0
    }

    @MainActor
    private func backfillMedicationDoseHistory(days: Int) async {
        guard medicationDoseEnabled else { return }
        guard let db else { return }
        guard supportsMedicationDose() else { return }
        guard #available(iOS 26.0, *) else { return }

        let end = Date()
        let start = Calendar.current.date(byAdding: .day, value: -max(1, days), to: end) ?? end
        let rows = await fetchMedicationDoseEvents(start: start, end: end)
        let inserted = DBHealthSamplesTable(db: db).insert(medicationDoseEvents: rows)
        medicationDoseCount7d = countMedicationDoseSamplesRecent(days: 7)
        lastSyncSummary = "Medication backfill inserted \(inserted) samples"
    }

    private func quantityTypes() -> [HKQuantityType] {
        var out: [HKQuantityType] = []
        if let bpS = HKObjectType.quantityType(forIdentifier: .bloodPressureSystolic) { out.append(bpS) }
        if let bpD = HKObjectType.quantityType(forIdentifier: .bloodPressureDiastolic) { out.append(bpD) }
        if let weight = HKObjectType.quantityType(forIdentifier: .bodyMass) { out.append(weight) }
        return out
    }

    private func categoryTypes() -> [HKCategoryType] {
        var out: [HKCategoryType] = []
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) { out.append(sleep) }
        return out
    }

    private func fetchQuantitySamples(type: HKQuantityType, start: Date, end: Date) async -> [HKQuantitySample] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: (res as? [HKQuantitySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func fetchCategorySamples(type: HKCategoryType, start: Date, end: Date) async -> [HKCategorySample] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: type, predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: (res as? [HKCategorySample]) ?? [])
            }
            store.execute(q)
        }
    }

    private func fetchWorkouts(start: Date, end: Date) async -> [HKWorkout] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: (res as? [HKWorkout]) ?? [])
            }
            store.execute(q)
        }
    }

    @available(iOS 26.0, *)
    private func fetchMedicationDoseEvents(start: Date, end: Date) async -> [HKSample] {
        await withCheckedContinuation { cont in
            let pred = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
            let q = HKSampleQuery(sampleType: HKSampleType.medicationDoseEventType(), predicate: pred, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, res, _ in
                cont.resume(returning: res ?? [])
            }
            store.execute(q)
        }
    }

    @available(iOS 12.0, *)
    private func requestStatusForAuthorization(read types: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { cont in
            store.getRequestStatusForAuthorization(toShare: [], read: types) { status, _ in
                cont.resume(returning: status)
            }
        }
    }

    #endif
}

#if canImport(HealthKit)
final class DBHealthSamplesTable {
    private let db: SQLiteDB

    init(db: SQLiteDB) {
        self.db = db
    }

    func insert(quantitySamples: [HKQuantitySample]) -> Int {
        if quantitySamples.isEmpty { return 0 }
        return db.withDB { dbp in
            var inserted = 0
            db.exec("BEGIN;")
            var stmt: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO health_samples(
                sample_id, type, start_ms, end_ms, value_num, value_str, unit, source, metadata_json, device_id, inserted_at_ms
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK {
                db.dbgErr(dbp, "health.insert.prepare", sqlite3_errcode(dbp))
                db.exec("ROLLBACK;")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            for s in quantitySamples {
                sqlite3_reset(stmt)
                let type = mapQuantityType(s.quantityType)
                let unit = preferredUnit(for: s.quantityType)
                let val = s.quantity.doubleValue(for: unit)
                let meta = metadataJSON(s.metadata)

                bindText(stmt, 1, s.uuid.uuidString.lowercased())
                bindText(stmt, 2, type)
                sqlite3_bind_int64(stmt, 3, Int64(s.startDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_int64(stmt, 4, Int64(s.endDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_double(stmt, 5, val)
                bindText(stmt, 6, "")
                bindText(stmt, 7, unit.unitString)
                bindText(stmt, 8, s.sourceRevision.source.name)
                bindText(stmt, 9, meta)
                bindText(stmt, 10, UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
                sqlite3_bind_int64(stmt, 11, Int64(Date().timeIntervalSince1970 * 1000.0))

                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { inserted += Int(sqlite3_changes(dbp)) }
            }

            db.exec("COMMIT;")
            return inserted
        }
    }

    func insert(categorySamples: [HKCategorySample]) -> Int {
        if categorySamples.isEmpty { return 0 }
        return db.withDB { dbp in
            var inserted = 0
            db.exec("BEGIN;")
            var stmt: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO health_samples(
                sample_id, type, start_ms, end_ms, value_num, value_str, unit, source, metadata_json, device_id, inserted_at_ms
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK {
                db.dbgErr(dbp, "health.insert.prepare", sqlite3_errcode(dbp))
                db.exec("ROLLBACK;")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            for s in categorySamples {
                sqlite3_reset(stmt)
                let type = mapCategoryType(s.categoryType)
                let valueStr = mapCategoryValue(s)
                let meta = metadataJSON(s.metadata)

                bindText(stmt, 1, s.uuid.uuidString.lowercased())
                bindText(stmt, 2, type)
                sqlite3_bind_int64(stmt, 3, Int64(s.startDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_int64(stmt, 4, Int64(s.endDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_double(stmt, 5, Double(s.value))
                bindText(stmt, 6, valueStr)
                bindText(stmt, 7, "")
                bindText(stmt, 8, s.sourceRevision.source.name)
                bindText(stmt, 9, meta)
                bindText(stmt, 10, UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
                sqlite3_bind_int64(stmt, 11, Int64(Date().timeIntervalSince1970 * 1000.0))

                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { inserted += Int(sqlite3_changes(dbp)) }
            }

            db.exec("COMMIT;")
            return inserted
        }
    }

    func insert(workoutSamples: [HKWorkout]) -> Int {
        if workoutSamples.isEmpty { return 0 }
        return db.withDB { dbp in
            var inserted = 0
            db.exec("BEGIN;")
            var stmt: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO health_samples(
                sample_id, type, start_ms, end_ms, value_num, value_str, unit, source, metadata_json, device_id, inserted_at_ms
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK {
                db.dbgErr(dbp, "health.insert.prepare", sqlite3_errcode(dbp))
                db.exec("ROLLBACK;")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            for w in workoutSamples {
                sqlite3_reset(stmt)
                let meta = workoutMetadataJSON(w)
                let duration = w.duration

                bindText(stmt, 1, w.uuid.uuidString.lowercased())
                bindText(stmt, 2, "workout")
                sqlite3_bind_int64(stmt, 3, Int64(w.startDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_int64(stmt, 4, Int64(w.endDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_double(stmt, 5, duration)
                bindText(stmt, 6, workoutActivityName(w.workoutActivityType))
                bindText(stmt, 7, "s")
                bindText(stmt, 8, w.sourceRevision.source.name)
                bindText(stmt, 9, meta)
                bindText(stmt, 10, UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
                sqlite3_bind_int64(stmt, 11, Int64(Date().timeIntervalSince1970 * 1000.0))

                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { inserted += Int(sqlite3_changes(dbp)) }
            }

            db.exec("COMMIT;")
            return inserted
        }
    }

    @available(iOS 12.0, *)
    func insert(medicationRecords: [HKClinicalRecord]) -> Int {
        if medicationRecords.isEmpty { return 0 }
        return db.withDB { dbp in
            var inserted = 0
            db.exec("BEGIN;")
            var stmt: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO health_samples(
                sample_id, type, start_ms, end_ms, value_num, value_str, unit, source, metadata_json, device_id, inserted_at_ms
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK {
                db.dbgErr(dbp, "health.insert.prepare", sqlite3_errcode(dbp))
                db.exec("ROLLBACK;")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            for r in medicationRecords {
                sqlite3_reset(stmt)
                let meta = clinicalMetadataJSON(r)

                bindText(stmt, 1, r.uuid.uuidString.lowercased())
                bindText(stmt, 2, "medication_record")
                sqlite3_bind_int64(stmt, 3, Int64(r.startDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_int64(stmt, 4, Int64(r.endDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_double(stmt, 5, 0)
                bindText(stmt, 6, r.displayName ?? "")
                bindText(stmt, 7, "")
                bindText(stmt, 8, r.sourceRevision.source.name)
                bindText(stmt, 9, meta)
                bindText(stmt, 10, UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
                sqlite3_bind_int64(stmt, 11, Int64(Date().timeIntervalSince1970 * 1000.0))

                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { inserted += Int(sqlite3_changes(dbp)) }
            }

            db.exec("COMMIT;")
            return inserted
        }
    }

    @available(iOS 26.0, *)
    func insert(medicationDoseEvents: [HKSample]) -> Int {
        if medicationDoseEvents.isEmpty { return 0 }
        return db.withDB { dbp in
            var inserted = 0
            db.exec("BEGIN;")
            var stmt: OpaquePointer?
            let sql = """
            INSERT OR IGNORE INTO health_samples(
                sample_id, type, start_ms, end_ms, value_num, value_str, unit, source, metadata_json, device_id, inserted_at_ms
            ) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK {
                db.dbgErr(dbp, "health.insert.prepare", sqlite3_errcode(dbp))
                db.exec("ROLLBACK;")
                return 0
            }
            defer { sqlite3_finalize(stmt) }

            for s in medicationDoseEvents {
                sqlite3_reset(stmt)
                let meta = metadataJSON(s.metadata)

                bindText(stmt, 1, s.uuid.uuidString.lowercased())
                bindText(stmt, 2, "medication_dose")
                sqlite3_bind_int64(stmt, 3, Int64(s.startDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_int64(stmt, 4, Int64(s.endDate.timeIntervalSince1970 * 1000.0))
                sqlite3_bind_double(stmt, 5, 1)
                bindText(stmt, 6, "")
                bindText(stmt, 7, "")
                bindText(stmt, 8, s.sourceRevision.source.name)
                bindText(stmt, 9, meta)
                bindText(stmt, 10, UIDevice.current.identifierForVendor?.uuidString ?? "unknown")
                sqlite3_bind_int64(stmt, 11, Int64(Date().timeIntervalSince1970 * 1000.0))

                let rc = sqlite3_step(stmt)
                if rc == SQLITE_DONE { inserted += Int(sqlite3_changes(dbp)) }
            }

            db.exec("COMMIT;")
            return inserted
        }
    }


    private func preferredUnit(for type: HKQuantityType) -> HKUnit {
        switch type.identifier {
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue,
             HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue:
            return HKUnit.millimeterOfMercury()
        case HKQuantityTypeIdentifier.bodyMass.rawValue:
            return HKUnit.gramUnit(with: .kilo)
        default:
            return HKUnit.count()
        }
    }

    private func mapQuantityType(_ type: HKQuantityType) -> String {
        switch type.identifier {
        case HKQuantityTypeIdentifier.bloodPressureSystolic.rawValue: return "blood_pressure_systolic"
        case HKQuantityTypeIdentifier.bloodPressureDiastolic.rawValue: return "blood_pressure_diastolic"
        case HKQuantityTypeIdentifier.bodyMass.rawValue: return "weight"
        default: return type.identifier
        }
    }

    private func mapCategoryType(_ type: HKCategoryType) -> String {
        switch type.identifier {
        case HKCategoryTypeIdentifier.sleepAnalysis.rawValue: return "sleep"
        default: return type.identifier
        }
    }

    private func mapCategoryValue(_ sample: HKCategorySample) -> String {
        if sample.categoryType.identifier == HKCategoryTypeIdentifier.sleepAnalysis.rawValue {
            switch HKCategoryValueSleepAnalysis(rawValue: sample.value) {
            case .some(.asleep),
                 .some(.asleepCore),
                 .some(.asleepDeep),
                 .some(.asleepREM),
                 .some(.asleepUnspecified):
                return "asleep"
            case .some(.inBed):
                return "in_bed"
            case .some(.awake):
                return "awake"
            case .none:
                return "unknown"
            @unknown default:
                return "unknown"
            }
        }
        return String(sample.value)
    }

    private func workoutActivityName(_ type: HKWorkoutActivityType) -> String {
        return String(describing: type)
    }

    private func metadataJSON(_ meta: [String: Any]?) -> String {
        guard let meta, !meta.isEmpty else { return "" }
        let safe = jsonSafeDictionary(meta)
        if let d = try? JSONSerialization.data(withJSONObject: safe, options: []),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return ""
    }

    private func workoutMetadataJSON(_ w: HKWorkout) -> String {
        var obj: [String: Any] = [:]
        obj["activity_type"] = w.workoutActivityType.rawValue
        if let energy = w.totalEnergyBurned {
            obj["energy_kcal"] = energy.doubleValue(for: HKUnit.kilocalorie())
        }
        if let dist = w.totalDistance {
            obj["distance_m"] = dist.doubleValue(for: HKUnit.meter())
        }
        if let md = w.metadata, !md.isEmpty {
            obj["metadata"] = jsonSafeDictionary(md)
        }
        let safe = jsonSafeDictionary(obj)
        if let d = try? JSONSerialization.data(withJSONObject: safe, options: []),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return ""
    }

    @available(iOS 12.0, *)
    private func clinicalMetadataJSON(_ r: HKClinicalRecord) -> String {
        var obj: [String: Any] = [:]
        if let fhir = r.fhirResource {
            obj["fhir_resource_type"] = fhir.resourceType
            obj["fhir_data_b64"] = fhir.data.base64EncodedString()
            if let url = fhir.sourceURL {
                obj["fhir_source_url"] = url.absoluteString
            }
        }
        let safe = jsonSafeDictionary(obj)
        if let d = try? JSONSerialization.data(withJSONObject: safe, options: []),
           let s = String(data: d, encoding: .utf8) {
            return s
        }
        return ""
    }

    private func jsonSafeDictionary(_ dict: [String: Any]) -> [String: Any] {
        var out: [String: Any] = [:]
        out.reserveCapacity(dict.count)
        for (k, v) in dict {
            out[k] = jsonSafeValue(v)
        }
        return out
    }

    private func jsonSafeValue(_ value: Any) -> Any {
        switch value {
        case let v as String:
            return v
        case let v as Int:
            return v
        case let v as Double:
            return v
        case let v as Float:
            return Double(v)
        case let v as Bool:
            return v
        case let v as NSNumber:
            return v
        case let v as Date:
            return ISO8601DateFormatter().string(from: v)
        case let v as URL:
            return v.absoluteString
        case let v as Data:
            return v.base64EncodedString()
        case let v as [String: Any]:
            return jsonSafeDictionary(v)
        case let v as [Any]:
            return v.map { jsonSafeValue($0) }
        case let v as HKDevice:
            return [
                "name": v.name ?? "",
                "manufacturer": v.manufacturer ?? "",
                "model": v.model ?? "",
                "hardwareVersion": v.hardwareVersion ?? "",
                "firmwareVersion": v.firmwareVersion ?? "",
                "softwareVersion": v.softwareVersion ?? "",
                "localIdentifier": v.localIdentifier ?? "",
                "udiDeviceIdentifier": v.udiDeviceIdentifier ?? ""
            ]
        case let v as HKQuantity:
            return v.description
        default:
            return String(describing: value)
        }
    }


    private func bindText(_ stmt: OpaquePointer?, _ idx: Int32, _ text: String) {
        let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(stmt, idx, text, -1, SQLITE_TRANSIENT)
    }
}
#endif
