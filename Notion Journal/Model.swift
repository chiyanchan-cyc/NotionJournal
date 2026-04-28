import Foundation

enum NJNoteType: String, Codable, Hashable, CaseIterable {
    case note = "note"
    case card = "card"

    var title: String {
        switch self {
        case .note: return "Note"
        case .card: return "Card"
        }
    }
}

enum NJNoteDominanceMode: String, Codable, Hashable, CaseIterable {
    case note = "note"
    case block = "block"

    var title: String {
        switch self {
        case .note: return "Note dominate"
        case .block: return "Block dominate"
        }
    }
}

struct NJNoteID: Hashable, Codable, Identifiable {
    let raw: String
    var id: String { raw }
    init(_ raw: String) { self.raw = raw }
}

struct NJNote: Identifiable, Codable, Hashable {
    var id: NJNoteID
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var notebook: String
    var tabDomain: String
    var title: String
    var rtfData: Data
    var deleted: Int64
    var pinned: Int64
    var favorited: Int64
    var noteTypeRaw: String
    var dominanceModeRaw: String
    var isChecklist: Int64
    var cardID: String
    var cardCategory: String
    var cardArea: String
    var cardContext: String
    var cardStatus: String
    var cardPriority: String

    var noteType: NJNoteType {
        get { NJNoteType(rawValue: noteTypeRaw) ?? .note }
        set { noteTypeRaw = newValue.rawValue }
    }

    var dominanceMode: NJNoteDominanceMode {
        get { NJNoteDominanceMode(rawValue: dominanceModeRaw) ?? .block }
        set { dominanceModeRaw = newValue.rawValue }
    }

    init(
        id: NJNoteID,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        notebook: String,
        tabDomain: String,
        title: String,
        rtfData: Data,
        deleted: Int64,
        pinned: Int64 = 0,
        favorited: Int64 = 0,
        noteTypeRaw: String = NJNoteType.note.rawValue,
        dominanceModeRaw: String = NJNoteDominanceMode.block.rawValue,
        isChecklist: Int64 = 0,
        cardID: String = "",
        cardCategory: String = "",
        cardArea: String = "",
        cardContext: String = "",
        cardStatus: String = "",
        cardPriority: String = ""
    ) {
        self.id = id
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.notebook = notebook
        self.tabDomain = tabDomain
        self.title = title
        self.rtfData = rtfData
        self.deleted = deleted
        self.pinned = pinned
        self.favorited = favorited
        self.noteTypeRaw = noteTypeRaw
        self.dominanceModeRaw = dominanceModeRaw
        self.isChecklist = isChecklist
        self.cardID = cardID
        self.cardCategory = cardCategory
        self.cardArea = cardArea
        self.cardContext = cardContext
        self.cardStatus = cardStatus
        self.cardPriority = cardPriority
    }

    init(
        id: NJNoteID,
        notebook: String,
        tabDomain: String,
        title: String,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        pinned: Int64 = 0,
        favorited: Int64 = 0,
        noteTypeRaw: String = NJNoteType.note.rawValue,
        dominanceModeRaw: String = NJNoteDominanceMode.block.rawValue,
        isChecklist: Int64 = 0,
        cardID: String = "",
        cardCategory: String = "",
        cardArea: String = "",
        cardContext: String = "",
        cardStatus: String = "",
        cardPriority: String = ""
    ) {
        self.id = id
        self.notebook = notebook
        self.tabDomain = tabDomain
        self.title = title
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.rtfData = Data()
        self.deleted = 0
        self.pinned = pinned
        self.favorited = favorited
        self.noteTypeRaw = noteTypeRaw
        self.dominanceModeRaw = dominanceModeRaw
        self.isChecklist = isChecklist
        self.cardID = cardID
        self.cardCategory = cardCategory
        self.cardArea = cardArea
        self.cardContext = cardContext
        self.cardStatus = cardStatus
        self.cardPriority = cardPriority
    }
}

struct NJCalendarItem: Identifiable, Codable, Hashable {
    var dateKey: String
    var title: String
    var photoAttachmentID: String
    var photoLocalID: String
    var photoCloudID: String
    var photoThumbPath: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int

    var id: String { dateKey }

    init(
        dateKey: String,
        title: String,
        photoAttachmentID: String,
        photoLocalID: String,
        photoCloudID: String,
        photoThumbPath: String,
        createdAtMs: Int64,
        updatedAtMs: Int64,
        deleted: Int
    ) {
        self.dateKey = dateKey
        self.title = title
        self.photoAttachmentID = photoAttachmentID
        self.photoLocalID = photoLocalID
        self.photoCloudID = photoCloudID
        self.photoThumbPath = photoThumbPath
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.deleted = deleted
    }

    static func empty(dateKey: String, nowMs: Int64) -> NJCalendarItem {
        NJCalendarItem(
            dateKey: dateKey,
            title: "",
            photoAttachmentID: "",
            photoLocalID: "",
            photoCloudID: "",
            photoThumbPath: "",
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            deleted: 0
        )
    }
}

struct NJFinanceMacroEvent: Identifiable, Codable, Hashable {
    var eventID: String
    var dateKey: String
    var title: String
    var category: String
    var region: String
    var timeText: String
    var impact: String
    var source: String
    var notes: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { eventID }
}

struct NJFinanceDailyBrief: Identifiable, Codable, Hashable {
    var dateKey: String
    var newsSummary: String
    var expectationSummary: String
    var watchItems: String
    var bias: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { dateKey }

    static func empty(dateKey: String, nowMs: Int64) -> NJFinanceDailyBrief {
        NJFinanceDailyBrief(
            dateKey: dateKey,
            newsSummary: "",
            expectationSummary: "",
            watchItems: "",
            bias: "",
            createdAtMs: nowMs,
            updatedAtMs: nowMs,
            deleted: 0
        )
    }
}

struct NJFinanceResearchSession: Identifiable, Codable, Hashable {
    var sessionID: String
    var title: String
    var themeID: String
    var premiseID: String
    var status: String
    var summary: String
    var lastMessageAtMs: Int64
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { sessionID }
}

struct NJFinanceResearchMessage: Identifiable, Codable, Hashable {
    var messageID: String
    var sessionID: String
    var role: String
    var body: String
    var sourceRefsJSON: String
    var retrievalContextJSON: String
    var taskRequestJSON: String
    var syncStatus: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { messageID }
}

struct NJFinanceResearchTask: Identifiable, Codable, Hashable {
    var taskID: String
    var sessionID: String
    var messageID: String
    var taskKind: String
    var instruction: String
    var status: String
    var priority: Int64
    var resultSummary: String
    var resultRefsJSON: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { taskID }
}

struct NJAgentHeartbeatRun: Identifiable, Codable, Hashable {
    var runID: String
    var heartbeatKey: String
    var scheduledForMs: Int64
    var startedAtMs: Int64
    var completedAtMs: Int64
    var status: String
    var coverageStartMs: Int64
    var coverageEndMs: Int64
    var dateKey: String
    var marketSession: String
    var outputRef: String
    var errorSummary: String
    var sourceRefsJSON: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { runID }
}

struct NJAgentBackfillTask: Identifiable, Codable, Hashable {
    var taskID: String
    var heartbeatKey: String
    var missedRunID: String
    var targetRunID: String
    var dateKey: String
    var marketSession: String
    var coverageStartMs: Int64
    var coverageEndMs: Int64
    var reason: String
    var status: String
    var priority: Int64
    var attemptCount: Int64
    var lastAttemptAtMs: Int64
    var resultRef: String
    var resultSummary: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { taskID }
}

struct NJFinanceFinding: Identifiable, Codable, Hashable {
    var findingID: String
    var sessionID: String
    var premiseID: String
    var stance: String
    var summary: String
    var confidence: Double
    var sourceRefsJSON: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { findingID }
}

struct NJFinanceJournalLink: Identifiable, Codable, Hashable {
    var linkID: String
    var sessionID: String
    var messageID: String
    var findingID: String
    var noteBlockID: String
    var excerpt: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { linkID }
}

struct NJFinanceSourceItem: Identifiable, Codable, Hashable {
    var sourceItemID: String
    var sourceID: String
    var sourceName: String
    var sourceURL: String
    var marketID: String
    var premiseIDsJSON: String
    var fetchedAtMs: Int64
    var publishedAtMs: Int64
    var contentHash: String
    var rawExcerpt: String
    var rawTextCKAssetPath: String
    var rawJSON: String
    var deleted: Int64

    var id: String { sourceItemID }
}

struct NJFinanceTransaction: Identifiable, Codable, Hashable {
    var transactionID: String
    var fingerprint: String
    var sourceType: String
    var accountID: String
    var accountLabel: String
    var externalRef: String
    var occurredAtMs: Int64
    var dateKey: String
    var merchantName: String
    var amountMinor: Int64
    var currencyCode: String
    var direction: String
    var analysisNature: String
    var category: String
    var tagText: String
    var fxRateToCNY: Double
    var amountCNYMinor: Int64
    var status: String
    var counterparty: String
    var itemName: String
    var details: String
    var note: String
    var importBatchID: String
    var sourceFileName: String
    var rawPayloadJSON: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { transactionID }

    var signedAmount: Decimal {
        Decimal(amountMinor) / Decimal(100)
    }

    var signedAmountCNY: Decimal {
        Decimal(amountCNYMinor) / Decimal(100)
    }
}

struct NJGoalSummary: Identifiable, Hashable {
    let goalID: String
    let name: String
    let goalTag: String
    let status: String
    let domainTagsJSON: String
    let createdAtMs: Int64
    let updatedAtMs: Int64

    var id: String { goalID }
}

struct NJPlannedExercise: Identifiable, Codable, Hashable {
    var planID: String
    var dateKey: String
    var weekKey: String
    var title: String
    var category: String
    var sport: String
    var sessionType: String
    var targetDistanceKm: Double
    var targetDurationMin: Double
    var notes: String
    var goalJSON: String
    var cueJSON: String
    var blockJSON: String
    var sourcePlanID: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int

    var id: String { planID }

    init(
        planID: String,
        dateKey: String,
        weekKey: String = "",
        title: String = "",
        category: String = "",
        sport: String,
        sessionType: String = "",
        targetDistanceKm: Double,
        targetDurationMin: Double,
        notes: String,
        goalJSON: String = "",
        cueJSON: String = "",
        blockJSON: String = "",
        sourcePlanID: String = "",
        createdAtMs: Int64,
        updatedAtMs: Int64,
        deleted: Int
    ) {
        self.planID = planID
        self.dateKey = dateKey
        self.weekKey = weekKey
        self.title = title
        self.category = category
        self.sport = sport
        self.sessionType = sessionType
        self.targetDistanceKm = targetDistanceKm
        self.targetDurationMin = targetDurationMin
        self.notes = notes
        self.goalJSON = goalJSON
        self.cueJSON = cueJSON
        self.blockJSON = blockJSON
        self.sourcePlanID = sourcePlanID
        self.createdAtMs = createdAtMs
        self.updatedAtMs = updatedAtMs
        self.deleted = deleted
    }
}

struct NJTrainingGoalContext: Codable, Hashable {
    var startWeightKg: Double?
    var targetWeightKg: Double?
    var primaryGoal: String
    var targetRace: String
    var targetRaceTimeSec: Int?
    var coreDailyMinMin: Int?
    var coreDailyMaxMin: Int?
    var notes: String?
}

struct NJTrainingPlanFile: Codable, Hashable {
    var schema: String
    var weekOf: String
    var generatedAtMs: Int64?
    var goalContext: NJTrainingGoalContext?
    var sessions: [NJTrainingPlanSessionFile]
}

struct NJTrainingPlanSessionFile: Codable, Hashable, Identifiable {
    var id: String
    var date: String
    var title: String
    var category: String
    var sport: String
    var sessionType: String?
    var plannedStart: String?
    var durationMin: Double?
    var targetDistanceKm: Double?
    var notes: String?
    var goals: [NJTrainingGoalFile]?
    var cueRules: [NJTrainingCueRuleFile]?
    var blocks: [NJTrainingBlockFile]?
}

struct NJTrainingGoalFile: Codable, Hashable {
    var type: String
    var label: String?
    var zone: Int?
    var lowBpm: Double?
    var highBpm: Double?
    var paceLowMinPerKm: Double?
    var paceHighMinPerKm: Double?
    var durationSec: Int?
    var distanceKm: Double?
    var exercise: String?
    var reps: Int?
    var sets: Int?
    var metadata: [String: String]?
}

struct NJTrainingCueRuleFile: Codable, Hashable {
    var trigger: String
    var speech: String
    var cooldownSec: Int?
    var priority: Int?
}

struct NJTrainingBlockFile: Codable, Hashable {
    var id: String?
    var kind: String
    var name: String?
    var durationSec: Int?
    var sets: Int?
    var reps: Int?
    var restSec: Int?
    var coachingCues: [NJTrainingCoachingCueFile]?
}

struct NJTrainingCoachingCueFile: Codable, Hashable {
    var trigger: String
    var speech: String
}

struct NJTrainingReviewFile: Codable, Hashable {
    struct Recovery: Codable, Hashable {
        var avgSleepHours: Double?
        var avgWeightKg: Double?
        var avgBMI: Double?
        var avgBodyFatPct: Double?
        var avgBpSys: Double?
        var avgBpDia: Double?
    }

    struct SessionReview: Codable, Hashable {
        var sessionID: String
        var date: String
        var title: String
        var category: String
        var sport: String
        var sessionType: String
        var plannedDurationMin: Double
        var plannedDistanceKm: Double
        var actualDurationMin: Double
        var actualDistanceKm: Double
        var avgHeartRateBpm: Double?
        var avgPaceMinPerKm: Double?
        var completed: Bool
        var notes: String
    }

    var schema: String
    var weekOf: String
    var goalContext: NJTrainingGoalContext?
    var recovery: Recovery
    var sessions: [SessionReview]
}

struct NJPlanningNote: Identifiable, Codable, Hashable {
    var planningKey: String
    var kind: String
    var targetKey: String
    var note: String
    var protonJSON: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int

    var id: String { planningKey }

    static func key(kind: String, targetKey: String) -> String {
        "\(kind):\(targetKey)"
    }
}

struct NJTimeSlotRecord: Identifiable, Codable, Hashable {
    var timeSlotID: String
    var ownerScope: String
    var title: String
    var category: String
    var startAtMs: Int64
    var endAtMs: Int64
    var notes: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { timeSlotID }
}

struct NJPersonalGoalRecord: Identifiable, Codable, Hashable {
    var goalID: String
    var ownerScope: String
    var title: String
    var focus: String
    var keyword: String
    var weeklyTarget: Int64
    var status: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { goalID }
}

struct NJRenewalItemRecord: Identifiable, Codable, Hashable {
    var renewalItemID: String
    var ownerScope: String
    var personName: String
    var documentName: String
    var documentType: String
    var jurisdiction: String
    var documentNumberHint: String
    var expiryDateKey: String
    var status: String
    var priority: String
    var reminderOffsetsJSON: String
    var notes: String
    var createdAtMs: Int64
    var updatedAtMs: Int64
    var deleted: Int64

    var id: String { renewalItemID }
}
