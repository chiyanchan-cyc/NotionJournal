import Foundation
import UIKit

final class NJShareItem: NSObject, UIActivityItemSource {
    private let data: Data
    private let filename: String
    private let fileURL: URL

    init(data: Data, filename: String) {
        self.data = data
        self.filename = filename

        let dir = FileManager.default.temporaryDirectory
        self.fileURL = dir.appendingPathComponent(filename)

        try? FileManager.default.removeItem(at: fileURL)
        try? data.write(to: fileURL, options: [.atomic])

        super.init()
    }

    func activityViewControllerPlaceholderItem(_ activityViewController: UIActivityViewController) -> Any {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, itemForActivityType activityType: UIActivity.ActivityType?) -> Any? {
        fileURL
    }

    func activityViewController(_ activityViewController: UIActivityViewController, subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        filename
    }
}
