//
//  DBNoteRepositoryCloud.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/6.
//


import Foundation

@MainActor
extension DBNoteRepository {

    func applyPulled(entity: String, rows: [(String, [String: Any])]) {
        switch entity {
        case "notebook":
            for (_, f) in rows { applyRemoteUpsert(entity: "notebook", fields: f) }

        case "tab":
            for (_, f) in rows { applyRemoteUpsert(entity: "tab", fields: f) }

        case "note":
            for (_, f) in rows { applyRemoteUpsert(entity: "note", fields: f) }

        case "goal":
            for (_, f) in rows { applyRemoteUpsert(entity: "goal", fields: f) }

        case "block":
            for (_, f) in rows { applyRemoteUpsert(entity: "block", fields: f) }

        case "attachment":
            for (_, f) in rows { applyRemoteUpsert(entity: "attachment", fields: f) }

        case "note_block":
            func noteID(_ f: [String: Any]) -> String { (f["note_id"] as? String) ?? (f["noteID"] as? String) ?? "" }
            func blockID(_ f: [String: Any]) -> String { (f["block_id"] as? String) ?? (f["blockID"] as? String) ?? "" }

            var pending: [[String: Any]] = rows.map { $0.1 }
            var passes = 0
            while !pending.isEmpty && passes < 5 {
                passes += 1
                var next: [[String: Any]] = []
                next.reserveCapacity(pending.count)

                for f in pending {
                    let n = noteID(f)
                    let b = blockID(f)
                    if n.isEmpty || b.isEmpty { continue }
                    if getNote(NJNoteID(n)) == nil { next.append(f); continue }
                    if hasBlock(blockID: b) == false { next.append(f); continue }
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
