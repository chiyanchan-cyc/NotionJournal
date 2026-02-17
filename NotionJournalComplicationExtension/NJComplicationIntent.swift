import Foundation
import AppIntents
import WidgetKit
import CloudKit

@available(watchOS 10.0, *)
enum NJComplicationCategory: String, AppEnum {
    case piano
    case exercise
    case personal

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Category"
    static var caseDisplayRepresentations: [NJComplicationCategory: DisplayRepresentation] = [
        .piano: "Piano",
        .exercise: "Exercise",
        .personal: "Personal"
    ]

    var uiText: String {
        switch self {
        case .piano: return "Piano"
        case .exercise: return "Exercise"
        case .personal: return "Personal"
        }
    }
}

private struct NJWidgetTimeSlot: Codable {
    let id: String
    let title: String
    let category: String
    let startDate: Date
    let endDate: Date
    let notes: String
}

@available(watchOS 10.0, *)
struct NJComplicationQuickLogIntent: AppIntent {
    static var title: LocalizedStringResource = "Quick Log Time Slot"
    static var description = IntentDescription("Create a time slot entry in Time module.")

    @Parameter(title: "Category")
    var category: NJComplicationCategory

    @Parameter(title: "Duration (Minutes)", default: 45)
    var durationMinutes: Int

    @Parameter(title: "Title", default: "")
    var title: String

    @Parameter(title: "Comment", default: "")
    var comment: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log \(\.$category) for \(\.$durationMinutes) minutes") {
            \.$title
            \.$comment
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        let okLocal = persistSlot(now: now)
        let okCloud = await persistToCloudKit(now: now)
        WidgetCenter.shared.reloadAllTimelines()
        if okCloud {
            return .result(dialog: "Time slot added.")
        }
        if okLocal {
            return .result(dialog: "Saved locally. Open app to sync.")
        }
        return .result(dialog: "Could not add time slot.")
    }

    private func persistSlot(now: Date) -> Bool {
        guard let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal") else { return false }

        let end = now.addingTimeInterval(TimeInterval(max(15, durationMinutes) * 60))
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? category.uiText : cleanTitle

        var slots: [NJWidgetTimeSlot] = []
        if let data = defaults.data(forKey: "nj_time_module_slots_v1"),
           let decoded = try? JSONDecoder().decode([NJWidgetTimeSlot].self, from: data) {
            slots = decoded
        }

        let slot = NJWidgetTimeSlot(
            id: UUID().uuidString.lowercased(),
            title: finalTitle,
            category: category.uiText,
            startDate: now,
            endDate: end,
            notes: comment.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        slots.append(slot)

        guard let out = try? JSONEncoder().encode(slots) else { return false }
        defaults.set(out, forKey: "nj_time_module_slots_v1")
        return true
    }

    private func persistToCloudKit(now: Date) async -> Bool {
        let end = now.addingTimeInterval(TimeInterval(max(15, durationMinutes) * 60))
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? category.uiText : cleanTitle
        let id = UUID().uuidString.lowercased()
        let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(end.timeIntervalSince1970 * 1000.0)

        let record = CKRecord(recordType: "NJTimeSlot", recordID: CKRecord.ID(recordName: id))
        record["time_slot_id"] = id as CKRecordValue
        record["owner_scope"] = "ME" as CKRecordValue
        record["title"] = finalTitle as CKRecordValue
        record["category"] = category.uiText.lowercased() as CKRecordValue
        record["start_at_ms"] = NSNumber(value: nowMs)
        record["end_at_ms"] = NSNumber(value: endMs)
        record["notes"] = comment.trimmingCharacters(in: .whitespacesAndNewlines) as CKRecordValue
        record["created_at_ms"] = NSNumber(value: nowMs)
        record["updated_at_ms"] = NSNumber(value: nowMs)
        record["deleted"] = NSNumber(value: 0)

        do {
            let db = CKContainer(identifier: "iCloud.com.CYC.NotionJournal").privateCloudDatabase
            _ = try await db.save(record)
            return true
        } catch {
            return false
        }
    }
}
