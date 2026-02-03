import Foundation

enum NJCalendarItemCloudMapper {
    static let entity = "calendar_item"
    static let recordType = "NJCalendarItem"

    static func isEntity(_ s: String) -> Bool { s == entity }

    static func validateFields(_ f: [String: Any]) -> Bool {
        f["date_key"] != nil || f["dateKey"] != nil
    }
}
