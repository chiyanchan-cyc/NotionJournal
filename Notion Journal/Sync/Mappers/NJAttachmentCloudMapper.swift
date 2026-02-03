import Foundation
import CloudKit

enum NJAttachmentCloudMapper {
    static let entity = "attachment"
    static let recordType = "NJAttachment"

    static func isEntity(_ s: String) -> Bool { s == entity }

    static func validateFields(_ f: [String: Any]) -> Bool {
        f["attachment_id"] != nil || f["attachmentID"] != nil
    }

    static func ingestPulledField(
        key: String,
        val: Any,
        f: inout [String: Any],
        toMs: (Any) -> Int64
    ) -> Bool {
        if key == "created_at_ms" {
            let ms = toMs(val)
            if ms > 0 { f["created_at_ms"] = ms }
            return true
        }

        if key == "updated_at_ms" {
            let ms = toMs(val)
            if ms > 0 { f["updated_at_ms"] = ms }
            return true
        }

        if key == "thumb_asset" {
            if let a = val as? CKAsset, let u = a.fileURL {
                f["thumb_asset"] = u
            }
            return true
        }

        return false
    }
}

