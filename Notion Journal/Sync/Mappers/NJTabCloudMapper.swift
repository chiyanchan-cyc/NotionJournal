//
//  NJTabCloudMapper.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/4.
//


import Foundation
import CloudKit

enum NJTabCloudMapper {
    static let entity = "tab"
    static let recordType = "NJTab"

    static func toFields(_ r: CKRecord) -> [String: Any] {
        [
            "tab_id": (r["tab_id"] as? String) ?? "",
            "notebook_id": (r["notebook_id"] as? String) ?? "",
            "domain_key": (r["domain_key"] as? String) ?? "",
            "title": (r["title"] as? String) ?? "",
            "color_hex": (r["color_hex"] as? String) ?? "",
            "order": (r["order"] as? Int64) ?? Int64((r["order"] as? Int) ?? 0),
            "created_at_ms": (r["created_at_ms"] as? Int64) ?? Int64((r["created_at_ms"] as? Int) ?? 0),
            "updated_at_ms": (r["updated_at_ms"] as? Int64) ?? Int64((r["updated_at_ms"] as? Int) ?? 0),
            "is_hidden": (r["is_hidden"] as? Int64) ?? Int64((r["is_hidden"] as? Int) ?? 0)
        ]
    }

    static func applyFields(_ f: [String: Any], to r: CKRecord) {
        r["tab_id"] = (f["tab_id"] as? String) as CKRecordValue?
        r["notebook_id"] = (f["notebook_id"] as? String) as CKRecordValue?
        r["domain_key"] = (f["domain_key"] as? String) as CKRecordValue?
        r["title"] = (f["title"] as? String) as CKRecordValue?
        r["color_hex"] = (f["color_hex"] as? String) as CKRecordValue?
        r["order"] = NSNumber(value: (f["order"] as? Int64) ?? Int64((f["order"] as? Int) ?? 0))
        r["created_at_ms"] = NSNumber(value: (f["created_at_ms"] as? Int64) ?? Int64((f["created_at_ms"] as? Int) ?? 0))
        r["updated_at_ms"] = NSNumber(value: (f["updated_at_ms"] as? Int64) ?? Int64((f["updated_at_ms"] as? Int) ?? 0))
        r["is_hidden"] = NSNumber(value: (f["is_hidden"] as? Int64) ?? Int64((f["is_hidden"] as? Int) ?? 0))
    }

    static func recordID(_ f: [String: Any]) -> CKRecord.ID? {
        guard let id = f["tab_id"] as? String, !id.isEmpty else { return nil }
        return CKRecord.ID(recordName: id)
    }
}
