import Foundation
import CloudKit

enum NJBlockCloudMapper {
    static let entity = "block"
    static let recordType = "NJBlock"

    static func isEntity(_ s: String) -> Bool { s == entity }

    static func validateFields(_ f: [String: Any]) -> Bool {
        f["block_id"] != nil || f["blockID"] != nil
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

        if key == "parent_block_id" {
            if let s = val as? String { f[key] = s; return true }
            if let ref = val as? CKRecord.Reference {
                f[key] = ref.recordID.recordName
                return true
            }
            return true
        }

        return false
    }
}
