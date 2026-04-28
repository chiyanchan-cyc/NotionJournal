//
//  DBNoteRepositoryCloud.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/6.
//


import Foundation

@MainActor
extension DBNoteRepository {
    private var cloudDeviceID: String {
        ProcessInfo.processInfo.hostName
    }

    private func int64Any(_ value: Any?) -> Int64 {
        if let value = value as? Int64 { return value }
        if let value = value as? Int { return Int64(value) }
        if let value = value as? NSNumber { return value.int64Value }
        if let value = value as? String { return Int64(value) ?? 0 }
        return 0
    }

    private func shouldIgnoreSelfEcho(entity: String, entityID: String, fields: [String: Any]) -> Bool {
        let pulledDeviceID = (fields["device_id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !pulledDeviceID.isEmpty, pulledDeviceID == cloudDeviceID else { return false }

        guard let existing = loadRecord(entity: entity, id: entityID), !existing.isEmpty else {
            return false
        }

        let localUpdatedAtMs = int64Any(existing["updated_at_ms"])
        let pulledUpdatedAtMs = int64Any(fields["updated_at_ms"])

        guard localUpdatedAtMs > 0, pulledUpdatedAtMs > 0 else { return false }
        guard localUpdatedAtMs >= pulledUpdatedAtMs else { return false }

        print("NJ_CK_IGNORE_SELF_ECHO entity=\(entity) id=\(entityID) device_id=\(pulledDeviceID) local_updated_at_ms=\(localUpdatedAtMs) pulled_updated_at_ms=\(pulledUpdatedAtMs)")
        return true
    }

    func applyPulled(entity: String, rows: [(String, [String: Any])]) {
        switch entity {
        case "notebook":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "notebook", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "notebook", fields: f)
            }

        case "tab":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "tab", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "tab", fields: f)
            }

        case "note":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "note", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "note", fields: f)
            }

        case "goal":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "goal", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "goal", fields: f)
            }

        case "card_schema":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "card_schema", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "card_schema", fields: f)
            }

        case "card":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "card", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "card", fields: f)
            }

        case "block":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "block", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "block", fields: f)
            }

        case "table":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "table", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "table", fields: f)
            }

        case "attachment":
            for (id, f) in rows where !shouldIgnoreSelfEcho(entity: "attachment", entityID: id, fields: f) {
                applyRemoteUpsert(entity: "attachment", fields: f)
            }

        case "note_block":
            func noteID(_ f: [String: Any]) -> String { (f["note_id"] as? String) ?? (f["noteID"] as? String) ?? "" }

            var pending: [(String, [String: Any])] = rows.filter { !shouldIgnoreSelfEcho(entity: "note_block", entityID: $0.0, fields: $0.1) }
            var passes = 0
            while !pending.isEmpty && passes < 5 {
                passes += 1
                var next: [(String, [String: Any])] = []
                next.reserveCapacity(pending.count)

                for (id, f) in pending {
                    let n = noteID(f)
                    if n.isEmpty { continue }
                    if getNote(NJNoteID(n)) == nil { next.append((id, f)); continue }
                    applyRemoteUpsert(entity: "note_block", fields: f)
                }

                if next.count == pending.count { break }
                pending = next
            }

        default:
            break
        }
    }

    func cloudFields(entity: String, id: String) -> [String: Any] {
        if entity == "notebook" { return notebookTable.loadNJNotebook(notebookID: id) ?? [:] }
        if entity == "tab" { return tabTable.loadNJTab(tabID: id) ?? [:] }
        return loadRecord(entity: entity, id: id) ?? [:]
    }

    func loadRecord(entity: String, id: String) -> [String: Any]? {
        if entity == "notebook" { return notebookTable.loadNJNotebook(notebookID: id) }
        if entity == "tab" { return tabTable.loadNJTab(tabID: id) }
        return cloudBridge.loadRecord(entity: entity, id: id)
    }

    func applyRemoteUpsert(entity: String, fields: [String: Any]) {
        if entity == "notebook" { notebookTable.applyNJNotebook(fields); return }
        if entity == "tab" { tabTable.applyNJTab(fields); return }
        cloudBridge.applyRemoteUpsert(entity: entity, fields: fields)
    }
}
