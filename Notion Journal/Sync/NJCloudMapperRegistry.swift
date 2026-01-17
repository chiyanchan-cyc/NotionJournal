import Foundation
import CloudKit

enum NJCloudMapperRegistry {
    static func ingestPulledField(entity: String, key: String, val: Any, f: inout [String: Any], toMs: (Any) -> Int64) -> Bool {
        if entity == NJBlockCloudMapper.entity {
            if NJBlockCloudMapper.ingestPulledField(key: key, val: val, f: &f, toMs: toMs) { return true }
        }

        if entity == NJNoteBlockCloudMapper.entity {
            if NJNoteBlockCloudMapper.ingestPulledField(key: key, val: val, f: &f, toMs: toMs) { return true }
        }

        if let s = val as? String { f[key] = s; return true }
        if let n = val as? NSNumber { f[key] = n; return true }
        if let d = val as? Data { f[key] = d; return true }
        if let a = val as? [String] { f[key] = a; return true }

        return false
    }
}
