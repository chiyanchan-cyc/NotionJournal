import Foundation

#if canImport(AppIntents)
import AppIntents

@available(iOS 16.0, watchOS 10.0, *)
enum NJTimeSlotCategoryIntent: String, AppEnum {
    case piano
    case exercise
    case personal

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Time Slot Category"
    static var caseDisplayRepresentations: [NJTimeSlotCategoryIntent: DisplayRepresentation] = [
        .piano: "Piano",
        .exercise: "Exercise",
        .personal: "Personal"
    ]

    var toDomain: NJTimeSlotCategory {
        switch self {
        case .piano: return .piano
        case .exercise: return .exercise
        case .personal: return .personal
        }
    }
}

@available(iOS 16.0, watchOS 10.0, *)
struct NJLogTimeSlotIntent: AppIntent {
    static var title: LocalizedStringResource = "Log Time Slot"
    static var description = IntentDescription("Create a personal time slot quickly for piano, exercise, or personal focus.")

    @Parameter(title: "Category")
    var category: NJTimeSlotCategoryIntent

    @Parameter(title: "Duration (Minutes)", default: 45)
    var durationMinutes: Int

    @Parameter(title: "Title", default: "")
    var title: String

    @Parameter(title: "Notes", default: "")
    var notes: String

    static var parameterSummary: some ParameterSummary {
        Summary("Log a \(\.$category) time slot for \(\.$durationMinutes) minutes") {
            \.$title
            \.$notes
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackTitle: String = {
            switch category {
            case .piano: return "Piano Practice"
            case .exercise: return "Exercise"
            case .personal: return "Personal Focus"
            }
        }()

        let created = await MainActor.run {
            NJTimeSlotStore.quickCreateNow(
                category: category.toDomain,
                durationMinutes: max(15, durationMinutes),
                title: cleanTitle.isEmpty ? fallbackTitle : cleanTitle,
                notes: notes
            )
        }

        if created {
            return .result(dialog: "Time slot created.")
        }
        return .result(dialog: "Could not create time slot.")
    }
}

@available(iOS 16.0, watchOS 10.0, *)
struct NJTimeSlotAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NJLogTimeSlotIntent(),
            phrases: [
                "Log time slot in \(.applicationName)",
                "Add piano slot in \(.applicationName)",
                "Add exercise slot in \(.applicationName)"
            ],
            shortTitle: "Log Time Slot",
            systemImageName: "applewatch"
        )
    }
}
#endif
