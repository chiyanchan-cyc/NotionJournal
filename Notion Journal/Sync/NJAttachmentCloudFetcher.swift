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

