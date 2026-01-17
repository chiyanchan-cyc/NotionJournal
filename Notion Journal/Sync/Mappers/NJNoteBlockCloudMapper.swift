import Foundation
import CloudKit

enum NJNoteBlockCloudMapper {
    static let entity = "note_block"
    static let recordType = "NJNoteBlock"

    static func isEntity(_ s: String) -> Bool { s == entity }

    static func validateFields(_ f: [String: Any]) -> Bool {
        f["instance_id"] != nil
    }

    static func ingestPulledField(
        key: String,
        val: Any,
        f: inout [String: Any],
        toMs: (Any) -> Int64
    ) -> Bool {

        switch key {
        case "note_id", "block_id":
            if let s = val as? String { f[key] = s; return true }
            if let ref = val as? CKRecord.Reference {
                f[key] = ref.recordID.recordName
                return true
            }
            return true

        case "created_at_ms":
            let ms = toMs(val)
            if ms > 0 { f[key] = ms }
            return true

        case "updated_at_ms":
            let ms = toMs(val)
            if ms > 0 { f[key] = ms }
            return true

        case "order_key", "deleted":
            f[key] = val
            return true

        default:
            return false
        }
    }
}
