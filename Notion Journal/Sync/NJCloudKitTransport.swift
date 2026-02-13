import Foundation
import CloudKit
import Network

final class NJCloudKitTransport {

    let recordDirtyError: (
        _ entity: String,
        _ entityID: String,
        _ code: Int,
        _ domain: String,
        _ message: String,
        _ retryAfterSec: Double?
    ) -> Void

    private let db: CKDatabase
    private let deviceID: String

    init(
        container: CKContainer,
        recordDirtyError: @escaping (
            String, String, Int, String, String, Double?
        ) -> Void
    ) {
        self.db = container.privateCloudDatabase
        self.deviceID = ProcessInfo.processInfo.hostName
        self.recordDirtyError = recordDirtyError
    }



    private func toMs(_ v: Any?) -> Int64 {
        guard let v else { return 0 }
        if let n = v as? NSNumber { return n.int64Value }
        if let i = v as? Int { return Int64(i) }
        if let i = v as? Int64 { return i }
        if let d = v as? Double { return Int64(d) }
        if let f = v as? Float { return Int64(f) }
        if let s = v as? String {
            if let i = Int64(s) { return i }
            if let d = Double(s) { return Int64(d) }
        }
        if let dt = v as? Date { return Int64(dt.timeIntervalSince1970 * 1000.0) }
        return 0
    }

    func updatedMs(for entity: String, record: CKRecord) -> Int64 {
        let fieldMs = toMs(record["updated_at_ms"])
        if fieldMs == 0 {
            print("NJ_CK_MISSING_UPDATED_AT entity=\(entity) id=\(record.recordID.recordName)")
            return 0
        }
        return fieldMs
    }

    private func recordToFields(entity: String, record: CKRecord) -> [String: Any] {
        var f: [String: Any] = [:]

        func ingestDefault(_ key: String, _ val: Any) {
            if val is CKRecord.Reference { return }
            if let a = val as? CKAsset {
                if let u = a.fileURL { f[key] = u }
                return
            }
            if let s = val as? String { f[key] = s; return }
            if let n = val as? NSNumber { f[key] = n; return }
            if let d = val as? Date { f[key] = d; return }
        }

        for key in record.allKeys() {
            guard let val = record[key] else { continue }

            if entity == NJBlockCloudMapper.entity {
                if NJBlockCloudMapper.ingestPulledField(key: key, val: val, f: &f, toMs: { self.toMs($0) }) { continue }
            }

            if entity == NJNoteBlockCloudMapper.entity {
                if NJNoteBlockCloudMapper.ingestPulledField(key: key, val: val, f: &f, toMs: { self.toMs($0) }) { continue }
            }

            if entity == NJAttachmentCloudMapper.entity {
                if NJAttachmentCloudMapper.ingestPulledField(key: key, val: val, f: &f, toMs: { self.toMs($0) }) { continue }
            }

            ingestDefault(key, val)
        }

        if f["created_at_ms"] == nil, let v = record["created_at_ms"] {
            let ms = toMs(v)
            if ms > 0 { f["created_at_ms"] = ms }
        }

        if f["updated_at_ms"] == nil, let v = record["updated_at_ms"] {
            let ms = toMs(v)
            if ms > 0 { f["updated_at_ms"] = ms }
        }

        if f["updated_at_ms"] == nil {
            let ms = updatedMs(for: entity, record: record)
            if ms > 0 { f["updated_at_ms"] = ms }
        }

        if f["device_id"] == nil { f["device_id"] = deviceID }
        if f["id"] == nil { f["id"] = record.recordID.recordName }

        return f
    }

    func pullEntityAll(entity: String, recordType: String, sinceMs: Int64) async -> ([[String: Any]], Int64) {
        var rows: [[String: Any]] = []
        var newMax: Int64 = sinceMs

        var cursor: CKQueryOperation.Cursor? = nil
        var useFallbackQuery = false
        var didRetryFallback = false


        while true {
            let op: CKQueryOperation
            if let c = cursor {
                op = CKQueryOperation(cursor: c)
            } else {
                let pred: NSPredicate
                if sinceMs > 0, !useFallbackQuery {
                    pred = NSPredicate(format: "updated_at_ms > %@", NSNumber(value: sinceMs))
                } else {
                    pred = NSPredicate(value: true)
                }

                let q = CKQuery(recordType: recordType, predicate: pred)
                if !useFallbackQuery {
                    q.sortDescriptors = [NSSortDescriptor(key: "updated_at_ms", ascending: true)]
                }
                op = CKQueryOperation(query: q)
            }

            op.resultsLimit = 200

            var batch: [CKRecord] = []
            op.recordFetchedBlock = { r in
                batch.append(r)
            }

            let (nextCursor, err) = await withCheckedContinuation { (cont: CheckedContinuation<(CKQueryOperation.Cursor?, Error?), Never>) in
                op.queryResultBlock = { result in
                    switch result {
                    case .success(let c):
                        cont.resume(returning: (c, nil))
                    case .failure(let e):
                        cont.resume(returning: (nil, e))
                    }
                }
                self.db.add(op)
            }

            if let err {
                let nse = err as NSError
                let shouldFallback =
                    !didRetryFallback &&
                    !useFallbackQuery &&
                    nse.domain == CKError.errorDomain &&
                    nse.code == CKError.Code.invalidArguments.rawValue &&
                    nse.localizedDescription.localizedCaseInsensitiveContains("recordname")

                if shouldFallback {
                    didRetryFallback = true
                    useFallbackQuery = true
                    cursor = nil
                    continue
                }

                print("NJ_CK_QUERY_ERR entity=\(entity) err=\(err)")
                break
            }

            for r in batch {
                var u = updatedMs(for: entity, record: r)
                if u == 0 { continue }
                if u <= sinceMs { continue }

                let f = recordToFields(entity: entity, record: r)

                if let fm = f["updated_at_ms"] as? NSNumber { u = fm.int64Value }
                if let fm = f["updated_at_ms"] as? Int64 { u = fm }
                if let fm = f["updated_at_ms"] as? Int { u = Int64(fm) }

                if u > newMax { newMax = u }
                rows.append(f)
            }

            if nextCursor == nil { break }
            cursor = nextCursor
        }

        return (rows, newMax)
    }


    func pushEntity(entity: String, recordType: String, rows: [(String, [String: Any])]) async -> [String] {
        let lock = NSLock()
        var savedSet = Set<String>()
        savedSet.reserveCapacity(rows.count)

        var toSave: [CKRecord] = []
        toSave.reserveCapacity(rows.count)

        let now = Int64(Date().timeIntervalSince1970 * 1000.0)

        for (id, f) in rows {
            let rid = CKRecord.ID(recordName: id)
            let rec = CKRecord(recordType: recordType, recordID: rid)

            for (k, v) in f {
                if let u = v as? URL {
                    rec[k] = CKAsset(fileURL: u)
                    continue
                }
                if let s = v as? String, s.hasPrefix("file://"), let u = URL(string: s) {
                    rec[k] = CKAsset(fileURL: u)
                    continue
                }

                if k == "id" { continue }
                if k == "created_at" || k == "updated_at" { continue }

                if k == "updated_at_ms" {
                                    let ms = toMs(v)
                                    rec[k] = NSNumber(value: ms > 0 ? ms : now)
                                    continue
                                }

                if k == "created_at_ms" {
                    let ms = toMs(v)
                    rec[k] = NSNumber(value: ms > 0 ? ms : now)
                    continue
                }

                if let s = v as? String { rec[k] = s as CKRecordValue; continue }
                if let n = v as? NSNumber { rec[k] = n; continue }
                if let i = v as? Int { rec[k] = NSNumber(value: i); continue }
                if let i = v as? Int64 { rec[k] = NSNumber(value: i); continue }
                if let d = v as? Double { rec[k] = NSNumber(value: d); continue }
                if let b = v as? Bool { rec[k] = NSNumber(value: b ? 1 : 0); continue }
                if let dt = v as? Date { rec[k] = dt as CKRecordValue; continue }
            }
            
            if entity == "block" {
                let payload = (f["payload_json"] as? String) ?? ""
                rec["payload_json"] = payload as CKRecordValue
                let tagJSON = (f["tag_json"] as? String) ?? ""
                rec["tag_json"] = tagJSON as CKRecordValue
                if let domainTag = f["domain_tag"] as? String {
                    rec["domain_tag"] = domainTag as CKRecordValue
                }

                let protonLen: Int = {
                    if let d = payload.data(using: .utf8),
                       let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any],
                       let sections = o["sections"] as? [String: Any],
                       let proton1 = sections["proton1"] as? [String: Any],
                       let data = proton1["data"] as? [String: Any],
                       let pj = data["proton_json"] as? String {
                        return pj.utf8.count
                    }
                    return 0
                }()

                let rowUpdated = toMs(f["updated_at_ms"])
                        }
            
            if rec["device_id"] == nil { rec["device_id"] = deviceID as CKRecordValue }
            if rec["updated_at_ms"] == nil { rec["updated_at_ms"] = NSNumber(value: now) }
            if rec["created_at_ms"] == nil { rec["created_at_ms"] = NSNumber(value: now) }

            toSave.append(rec)
        }

        if toSave.isEmpty { return [] }

        let tryIDs = rows.map { $0.0 }

        let op = CKModifyRecordsOperation(recordsToSave: toSave, recordIDsToDelete: nil)
        op.savePolicy = .changedKeys
        op.isAtomic = false

        let _ = await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            op.perRecordSaveBlock = { rid, result in
                switch result {
                case .success:
                    lock.lock()
                    savedSet.insert(rid.recordName)
                    lock.unlock()
                    print("NJ_CK_PUSH_REC_OK entity=\(entity) id=\(rid.recordName)")
                case .failure(let e):
                    if let ck = e as? CKError {
                        let retryAfterAny = ck.userInfo[CKErrorRetryAfterKey]
                        let retryAfterSec: Double? = {
                            if let n = retryAfterAny as? NSNumber { return n.doubleValue }
                            if let d = retryAfterAny as? Double { return d }
                            return nil
                        }()
                        let msg = "\(ck.code) \(ck.localizedDescription)"
                        print("NJ_CK_PUSH_REC_ERR entity=\(entity) id=\(rid.recordName) code=\(ck.code.rawValue) \(ck.code) retryAfter=\(retryAfterAny ?? "nil")")
                        self.recordDirtyError(
                            entity,
                            rid.recordName,
                            ck.code.rawValue,
                            "CKError",
                            msg,
                            retryAfterSec
                        )
                    } else {
                        let msg = "\(type(of: e)) \(e.localizedDescription)"
                        print("NJ_CK_PUSH_REC_ERR entity=\(entity) id=\(rid.recordName) nonCK=\(type(of: e)) err=\(e)")
                        self.recordDirtyError(
                            entity,
                            rid.recordName,
                            -1,
                            "Error",
                            msg,
                            nil
                        )
                    }
                }
            }

            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume()
                case .failure(let e):
                    if let ck = e as? CKError {
                        let retryAfter = ck.userInfo[CKErrorRetryAfterKey] ?? "nil"
                        let partial = ck.userInfo[CKPartialErrorsByItemIDKey] ?? "nil"
                        let underlying = ck.userInfo[NSUnderlyingErrorKey] ?? "nil"
                        print("NJ_CK_PUSH_OP_ERR entity=\(entity) code=\(ck.code.rawValue) \(ck.code) retryAfter=\(retryAfter) userInfoKeys=\(Array(ck.userInfo.keys)) underlying=\(underlying) partial=\(partial)")
                    } else {
                        print("NJ_CK_PUSH_OP_ERR entity=\(entity) nonCK=\(type(of: e)) err=\(e)")
                    }
                    cont.resume()
                }
            }

            self.db.add(op)
        }

        lock.lock()
        let saved = Array(savedSet)
        lock.unlock()

        let missing = Set(tryIDs).subtracting(savedSet)
        if !missing.isEmpty {
            print("NJ_CK_PUSH_RETURN_MISSING entity=\(entity) try=\(tryIDs.count) saved=\(saved.count) missing=\(missing.count) missingHead=\(Array(missing.prefix(20)))")
        }

        return saved
    }

    func deleteEntity(entity: String, recordType: String, ids: [String]) async -> [String] {
        if ids.isEmpty { return [] }

        let tryIDs = Set(ids)
        let recordIDs = ids.map { CKRecord.ID(recordName: $0) }
        let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
        op.savePolicy = .ifServerRecordUnchanged
        op.isAtomic = false

        let deleted: [String] = await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:
                    cont.resume(returning: Array(tryIDs))
                case .failure(let err):
                    var deletedSet = Set<String>()

                    if let ckErr = err as? CKError {
                        if let partial = ckErr.userInfo[CKPartialErrorsByItemIDKey] as? [CKRecord.ID: Error] {
                            var failedIDs = Set<String>()
                            for (rid, perErr) in partial {
                                failedIDs.insert(rid.recordName)
                                if let perCK = perErr as? CKError, perCK.code == .unknownItem {
                                    deletedSet.insert(rid.recordName)
                                    continue
                                }
                                let perCK = perErr as? CKError
                                let retryAfter = perCK?.retryAfterSeconds
                                let perDomain = (perCK as NSError?)?.domain ?? "ck"
                                self.recordDirtyError(
                                    entity,
                                    rid.recordName,
                                    (perCK?.code.rawValue) ?? -1,
                                    perDomain,
                                    perErr.localizedDescription,
                                    retryAfter
                                )
                            }
                            let ok = tryIDs.subtracting(failedIDs)
                            deletedSet.formUnion(ok)
                        } else if ckErr.code == .unknownItem {
                            deletedSet = tryIDs
                        } else {
                            let retryAfter = ckErr.retryAfterSeconds
                            for id in ids {
                                let ckDomain = (ckErr as NSError).domain
                                self.recordDirtyError(
                                    entity,
                                    id,
                                    ckErr.code.rawValue,
                                    ckDomain,
                                    ckErr.localizedDescription,
                                    retryAfter
                                )
                            }
                        }
                    } else {
                        for id in ids {
                            self.recordDirtyError(
                                entity,
                                id,
                                -1,
                                "Error",
                                err.localizedDescription,
                                nil
                            )
                        }
                    }

                    cont.resume(returning: Array(deletedSet))
                }
            }
            self.db.add(op)
        }

        return deleted
    }

}
