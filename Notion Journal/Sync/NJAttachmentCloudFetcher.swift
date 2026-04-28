import Foundation
import CloudKit
import UIKit

enum NJAttachmentCloudFetcher {

    static func fetchThumbIfNeeded(attachmentID: String, completion: @escaping (UIImage?) -> Void) {
        if let url = NJAttachmentCache.fileURL(for: attachmentID),
           FileManager.default.fileExists(atPath: url.path),
           let img = UIImage(contentsOfFile: url.path) {
            completion(img)
            return
        }

        Task {
            let container = CKContainer(identifier: NJCloudConfig.containerID)
            let db = container.privateCloudDatabase
            let recordID = CKRecord.ID(recordName: attachmentID)
            do {
                let record = try await db.record(for: recordID)
                guard let asset = record["thumb_asset"] as? CKAsset,
                      let src = asset.fileURL else {
                    await MainActor.run { completion(nil) }
                    return
                }

                guard let dst = NJAttachmentCache.fileURL(for: attachmentID) else {
                    await MainActor.run { completion(nil) }
                    return
                }

                do {
                    if FileManager.default.fileExists(atPath: dst.path) {
                        try FileManager.default.removeItem(at: dst)
                    }
                    try FileManager.default.copyItem(at: src, to: dst)
                } catch {
                    await MainActor.run { completion(nil) }
                    return
                }

                let img = UIImage(contentsOfFile: dst.path)
                await MainActor.run { completion(img) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }
}

enum NJTableCloudFetcher {
    private static func int64(_ value: Any?) -> Int64 {
        guard let value else { return 0 }
        if let n = value as? NSNumber { return n.int64Value }
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        if let d = value as? Double { return Int64(d) }
        if let s = value as? String { return Int64(s) ?? 0 }
        if let dt = value as? Date { return Int64(dt.timeIntervalSince1970 * 1000.0) }
        return 0
    }

    static func fetchTable(tableID: String) async -> [String: Any]? {
        let trimmedID = tableID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty else { return nil }

        let container = CKContainer(identifier: NJCloudConfig.containerID)
        let db = container.privateCloudDatabase
        let recordID = CKRecord.ID(recordName: trimmedID)

        do {
            let record = try await db.record(for: recordID)
            var fields: [String: Any] = [:]

            for key in record.allKeys() {
                guard let value = record[key] else { continue }
                if let s = value as? String {
                    fields[key] = s
                } else if let n = value as? NSNumber {
                    fields[key] = n
                } else if let d = value as? Date {
                    fields[key] = d
                }
            }

            fields["id"] = record.recordID.recordName
            fields["table_id"] = (fields["table_id"] as? String) ?? record.recordID.recordName

            if fields["created_at_ms"] == nil {
                let created = int64(record["created_at_ms"])
                if created > 0 { fields["created_at_ms"] = created }
            }
            if fields["updated_at_ms"] == nil {
                let updated = int64(record["updated_at_ms"])
                if updated > 0 { fields["updated_at_ms"] = updated }
            }

            print("NJ_TABLE_DIRECT_FETCH_OK table_id=\(trimmedID) updated_at_ms=\(int64(fields["updated_at_ms"])) bytes=\((fields["canonical_json"] as? String)?.utf8.count ?? 0)")
            return fields
        } catch {
            print("NJ_TABLE_DIRECT_FETCH_ERR table_id=\(trimmedID) err=\(error)")
            return nil
        }
    }
}
