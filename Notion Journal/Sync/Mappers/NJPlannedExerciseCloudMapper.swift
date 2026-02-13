import Foundation

enum NJPlannedExerciseCloudMapper {
    static let entity = "planned_exercise"
    static let recordType = "NJPlannedExercise"

    static func isEntity(_ s: String) -> Bool { s == entity }

    static func validateFields(_ f: [String: Any]) -> Bool {
        f["plan_id"] != nil || f["planID"] != nil
    }
}
