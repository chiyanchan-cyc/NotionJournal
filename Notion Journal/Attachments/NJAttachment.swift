import Foundation
import UIKit

enum NJAttachmentKind: String, Codable {
    case photo
    case table
}

struct NJAttachmentRecord: Codable, Equatable {
    var attachmentID: String
    var blockID: String
    var noteID: String?
    var kind: NJAttachmentKind
    var thumbPath: String
    var fullPhotoRef: String
    var displayW: Int
    var displayH: Int
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int
}

enum NJAttachmentCache {
    private static let dirName = "nj_attachment_cache"
    static let thumbWidth: CGFloat = 400

    static func cacheDir() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent(dirName, isDirectory: true)
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir
    }

    static func fileURL(for attachmentID: String) -> URL? {
        guard let dir = cacheDir() else { return nil }
        return dir.appendingPathComponent("\(attachmentID).jpg", isDirectory: false)
    }

    static func imageFromPath(_ path: String) -> UIImage? {
        if path.isEmpty { return nil }
        if FileManager.default.fileExists(atPath: path) {
            return UIImage(contentsOfFile: path)
        }
        return nil
    }

    static func saveThumbnail(
        image: UIImage,
        attachmentID: String,
        width: CGFloat = 400,
        jpegQuality: CGFloat = 0.85
    ) -> (url: URL, size: CGSize)? {
        guard let url = fileURL(for: attachmentID) else { return nil }
        let w = max(1, width)
        let ratio = image.size.height / max(1, image.size.width)
        let h = max(1, w * ratio)
        let size = CGSize(width: w, height: h)
        let renderer = UIGraphicsImageRenderer(size: size)
        let thumb = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let data = thumb.jpegData(compressionQuality: jpegQuality) else { return nil }
        do {
            try data.write(to: url, options: [.atomic])
            return (url, size)
        } catch {
            return nil
        }
    }

    static func cleanupOlderThan(days: Int, onDelete: (String) -> Void) {
        guard let dir = cacheDir() else { return }
        let fm = FileManager.default
        let ttl: TimeInterval = Double(days) * 24.0 * 60.0 * 60.0
        let cutoff = Date().addingTimeInterval(-ttl)

        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: []) else {
            return
        }

        for url in items where url.pathExtension.lowercased() == "jpg" {
            let attrs = try? fm.attributesOfItem(atPath: url.path)
            let mod = (attrs?[.modificationDate] as? Date) ?? Date.distantPast
            if mod < cutoff {
                let id = url.deletingPathExtension().lastPathComponent
                try? fm.removeItem(at: url)
                onDelete(id)
            }
        }
    }
}
