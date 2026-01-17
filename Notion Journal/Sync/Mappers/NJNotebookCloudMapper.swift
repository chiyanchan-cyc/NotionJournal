//
//  NJNotebookCloudMapper.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/4.
//


import Foundation
import CloudKit

enum NJNotebookCloudMapper {
    static let entity = "notebook"
    static let recordType = "NJNotebook"

    static func toFields(_ r: CKRecord) -> [String: Any] {
        [
            "notebook_id": (r["notebook_id"] as? String) ?? "",
            "title": (r["title"] as? String) ?? "",
            "color_hex": (r["color_hex"] as? String) ?? "",
            "created_at_ms": (r["created_at_ms"] as? Int64) ?? Int64((r["created_at_ms"] as? Int) ?? 0),
            "updated_at_ms": (r["updated_at_ms"] as? Int64) ?? Int64((r["updated_at_ms"] as? Int) ?? 0),
            "is_archived": (r["is_archived"] as? Int64) ?? Int64((r["is_archived"] as? Int) ?? 0)
        ]
    }

    static func applyFields(_ f: [String: Any], to r: CKRecord) {
        r["notebook_id"] = (f["notebook_id"] as? String) as CKRecordValue?
        r["title"] = (f["title"] as? String) as CKRecordValue?
        r["color_hex"] = (f["color_hex"] as? String) as CKRecordValue?
        r["created_at_ms"] = NSNumber(value: (f["created_at_ms"] as? Int64) ?? Int64((f["created_at_ms"] as? Int) ?? 0))
        r["updated_at_ms"] = NSNumber(value: (f["updated_at_ms"] as? Int64) ?? Int64((f["updated_at_ms"] as? Int) ?? 0))
        r["is_archived"] = NSNumber(value: (f["is_archived"] as? Int64) ?? Int64((f["is_archived"] as? Int) ?? 0))
    }

    static func recordID(_ f: [String: Any]) -> CKRecord.ID? {
        guard let id = f["notebook_id"] as? String, !id.isEmpty else { return nil }
        return CKRecord.ID(recordName: id)
    }
}
