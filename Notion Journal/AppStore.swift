import Foundation
import SwiftUI
import UIKit
import Combine
import CloudKit
import WidgetKit
import CryptoKit
import SQLite3

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJNotebook: Identifiable, Hashable {
    let notebookID: String
    var title: String
    var colorHex: String
    var id: String { notebookID }
}


struct NJTab: Identifiable, Hashable {
    let tabID: String
    var notebookID: String
    var title: String
    var domainKey: String
    var colorHex: String
    var id: String { tabID }
}

struct NJPendingMoveBlock: Hashable {
    let blockID: String
    let instanceID: String
    let fromNoteID: String
    let fromNoteDomain: String
    let preview: String
}

private struct NJWidgetGoalJournalDay: Codable, Hashable {
    let key: String
    let shortLabel: String
}

private struct NJWidgetGoalJournalRow: Codable, Hashable {
    let id: String
    let owner: String
    let name: String
    let goalTag: String
    let filledDayKeys: [String]
}

private struct NJWidgetGoalJournalSection: Codable, Hashable {
    let owner: String
    let rows: [NJWidgetGoalJournalRow]
}

private struct NJWidgetGoalJournalSnapshot: Codable, Hashable {
    let days: [NJWidgetGoalJournalDay]
    let sections: [NJWidgetGoalJournalSection]
    let generatedAt: Date
}

private struct NJWidgetTimeSlot: Codable, Hashable {
    let id: String
    let title: String
    let category: String
    let startDate: Date
    let endDate: Date
    let notes: String
}

private struct NJWidgetHabitDay: Codable, Hashable {
    let key: String
    let shortLabel: String
}

private struct NJWidgetHabitRow: Codable, Hashable {
    let id: String
    let name: String
    let subtitle: String
    let dayMinutes: [String: Int]
}

private struct NJWidgetHabitSnapshot: Codable, Hashable {
    let days: [NJWidgetHabitDay]
    let rows: [NJWidgetHabitRow]
    let generatedAt: Date
}

final class UIState: ObservableObject {
    @Published var showDBDebug = false
}

@MainActor
final class AppStore: ObservableObject {
    private let blockRepushRepairKey = "nj_known_block_repush_v2"
    private let appActivationSyncDebounceMs: Int64 = 60_000
    private let knownBlockRepushIDs = [
        "5c787ede-d8cb-4242-baab-fd5534cce777",
        "43d59787-47ad-4b15-9d44-326c46e1b3f8",
        "6d72fca7-e9de-4fe2-a26b-770ac86b9118",
        "1C67DF53-A4C9-47DE-9C29-154D8951F537"
    ]
    private let widgetAppGroupID = "group.com.CYC.NotionJournal"
    private let widgetTrainingWeekKey = "nj_training_week_snapshot_v1"

    @Published var notebooks: [NJNotebook]
    @Published var tabs: [NJTab]
    @Published var selectedNotebookID: String?
    @Published var selectedTabID: String?
    @Published var showFavoriteNotesOnly = false
    @Published var selectedModule: NJUIModule = .note
    @Published var selectedInvestmentSection: NJInvestmentSection = .macro
    @Published var selectedInvestmentMarket: NJInvestmentMarket = .all
    @Published var selectedInvestmentTradeTab: NJInvestmentTradeTab = .saasOvershoot
    @Published var selectedInvestmentLedgerTab: NJInvestmentLedgerTab = .ledger
    @Published var pendingInvestmentShortcutMarket: NJInvestmentShortcutMarket? = nil
    @Published var investmentRefreshNonce: Int = 0
    @Published var investmentMFSFocusCount: Int = 0
    @Published var investmentCriticalNewsCount: Int = 0
    @Published var selectedGoalID: String? = nil
    @Published var selectedOutlineID: String? = nil
    @Published var selectedOutlineMainTabID: String? = "ME"
    @Published var selectedOutlineCategoryID: String? = nil
    @Published var selectedOutlineNodeID: String? = nil
    @Published var selectedFamilyInfoPerson: String = "All"
    @Published var selectedFamilyInfoType: String = "All"
    @Published var showDBDebugPanel = false
    @Published var didFinishInitialPull = false
    @Published var initialPullError: String? = nil
    @Published var localDataReady = false
    @Published var showGoalMigrationAlert = false
    @Published var goalMigrationCount: Int = 0
    @Published var pendingMoveBlock: NJPendingMoveBlock? = nil
    @Published var quickClipboardCount: Int = 0

    @StateObject var ui = UIState()

    let db: SQLiteDB
    let notes: DBNoteRepository
    let sync: CloudSyncEngine
    let outline: NJOutlineStore
    private var lastAppActivationSyncAtMs: Int64 = 0
    private var appActivationSyncInFlight = false
    private var goalJournalSnapshotTask: Task<Void, Never>? = nil
    private var timeSlotWidgetSnapshotTask: Task<Void, Never>? = nil

    init() {
        let dbPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notion_journal.sqlite")
            .path

        let db = SQLiteDB(path: dbPath, resetSchema: false)
        DBSchemaInstaller.ensureSchema(db: db)

        self.db = db
        self.notes = DBNoteRepository(db: db)
        self.outline = NJOutlineStore(repo: self.notes)

        let deviceID =
            UIDevice.current.identifierForVendor?.uuidString.lowercased()
            ?? UUID().uuidString.lowercased()

        self.sync = CloudSyncEngine(
            repo: self.notes,
            deviceID: deviceID,
            containerID: NJCloudConfig.containerID
        )
        
        if let reason = self.sync.cloudSyncUnavailableReason {
            print("CK_PING skipped reason=\(reason)")
        } else {
            CKContainer.default().accountStatus { status, error in
                print("CK_PING status=", status.rawValue, "error=", String(describing: error))
            }
        }

        self.notebooks = []
        self.tabs = []
        self.selectedNotebookID = nil
        self.selectedTabID = nil

        runAttachmentCacheCleanupIfNeeded()
        notes.cleanupCalendarItemsOlderThan3Months()
        seedOfficialFinanceMacroCalendar2026()
        seedInvestmentMacroCalendar2026()
        seedMarketClosureCalendar2026()
        seedUSMarketSnapshotBackfill2026()
        cleanupDuplicateMeNotebookCreatedByInvestmentLedgerV1()
        seedInvestmentLedgerSQQQTradeV1()
        seedInvestmentLedgerPLTRTradeV1()
        seedInvestmentLedgerSLVTradeV1()
        seedInvestmentLedgerSMICTradeV1()
        seedRenewalRegistryV1()
        runMeCommonInformationCleanupV1()
        runMeDatabaseCleanupV2()
        runMeDatabaseCleanupV3()
        mirrorPersonalIdentificationCards()
        ensurePersonalIdentificationDatabaseNote()
        notes.syncPersonalIdentificationCardsIntoDatabaseNote()
        seedInvestmentLedgerSQQQTradeV1()
        seedInvestmentLedgerPLTRTradeV1()
        seedInvestmentLedgerSLVTradeV1()
        seedInvestmentLedgerSMICTradeV1()
        let personalIDDuplicateCount = notes.cleanupDuplicatePersonalIdentificationDatabaseNotes()
        if personalIDDuplicateCount > 0 {
            print("NJ_PERSONAL_ID_DUPLICATE_CLEANUP deleted=\(personalIDDuplicateCount)")
        }
        enqueueCardDirtyBackfillIfNeeded()
        let investmentLedgerDirtyBackfillCount = enqueueInvestmentLedgerDirtyBackfillIfNeeded()

        let outlineBackfillCount = runStartupOutlineBackfillIfNeeded()
        let liveBlockDirtyBackfillKey = "nj_dirty_live_block_backfill_done_v1"
        let liveBlockDirtyBackfillCount: Int = {
            if UserDefaults.standard.bool(forKey: liveBlockDirtyBackfillKey) {
                return 0
            }
            let changed = NJLocalBLRunner(db: db).backfillMissingDirtyForLiveBlocks(limit: 20000)
            UserDefaults.standard.set(true, forKey: liveBlockDirtyBackfillKey)
            return changed
        }()
        let prePullTimestampRepairDirtyClearCount = notes.clearFutureTimestampRepairDirtyForAttachedBlocks(nowMs: DBNoteRepository.nowMs())
        let bl = NJLocalBLRunner(db: db)
        let duplicateNoteBlockRepairCount = bl.dedupeDuplicateLiveNoteBlockLinks(limit: 8000)
        let recentNoteBlockRepushKey = "nj_recent_note_block_repush_done_v1"
        let recentNoteBlockRepushCount: Int = {
            if UserDefaults.standard.bool(forKey: recentNoteBlockRepushKey) {
                return 0
            }
            let changed = bl.backfillDirtyForRecentlyUpdatedLiveNoteBlocks(windowHours: 72, limit: 6000)
            UserDefaults.standard.set(true, forKey: recentNoteBlockRepushKey)
            return changed
        }()
        let noteBlockLinkRepairCount = bl.repairMissingNoteBlockLinksFromAttachments(limit: 8000)
        let noteBlockHistoryRepairCount = bl.repairMissingNoteBlockLinksFromHistory(limit: 8000)
        let weeklyCalendarNoteRepairCount = repairOrphanWeeklyCalendarNoteLinks()
        let calendarPhotoRepairKey = "nj_calendar_photo_sync_repair_done_v2"
        let calendarPhotoRepairCount: Int = {
            if UserDefaults.standard.bool(forKey: calendarPhotoRepairKey) {
                return 0
            }
            let changed = NJLocalBLRunner(db: db).backfillDirtyForCalendarPhotos(limit: 12000)
            UserDefaults.standard.set(true, forKey: calendarPhotoRepairKey)
            return changed
        }()
        let outlineCount = notes.localCount(entity: "outline")
        let outlineNodeCount = notes.localCount(entity: "outline_node")
        print("NJ_OUTLINE_LOCAL outlines=\(outlineCount) nodes=\(outlineNodeCount) backfill_changed=\(outlineBackfillCount)")
        print("NJ_DIRTY_BACKFILL live_block_missing_dirty=\(liveBlockDirtyBackfillCount)")
        print("NJ_DIRTY_BACKFILL pre_pull_future_timestamp_dirty_clear=\(prePullTimestampRepairDirtyClearCount)")
        print("NJ_LINK_REPAIR duplicate_live_note_block=\(duplicateNoteBlockRepairCount)")
        print("NJ_DIRTY_BACKFILL recent_note_block_repush=\(recentNoteBlockRepushCount)")
        print("NJ_DIRTY_BACKFILL investment_ledger=\(investmentLedgerDirtyBackfillCount)")
        print("NJ_LINK_REPAIR missing_note_block_from_attachment=\(noteBlockLinkRepairCount)")
        print("NJ_LINK_REPAIR missing_note_block_from_history=\(noteBlockHistoryRepairCount)")
        print("NJ_LINK_REPAIR weekly_calendar_orphans=\(weeklyCalendarNoteRepairCount)")
        print("NJ_CALENDAR_PHOTO_REPAIR dirty_requeued=\(calendarPhotoRepairCount)")
        runOneTimeBlockCursorRepairIfNeeded()
        refreshQuickClipboardCount()
        refreshInvestmentCriticalNewsBadge()
        repairOutlineAttachedBlocksIfNeeded()
        repairKnownMissingCloudBlocksIfNeeded()
        publishTrainingWeekSnapshotToWidget()
        reloadNotebooksTabsFromDB()
        if sync.initialPullCompleted {
            ensureRollingFutureWeeklyCalendarNotes()
        }
        localDataReady = true

        self.sync.start()
        if notes.pendingDirtyCount() > 0 ||
            liveBlockDirtyBackfillCount > 0 ||
            duplicateNoteBlockRepairCount > 0 ||
            recentNoteBlockRepushCount > 0 ||
            investmentLedgerDirtyBackfillCount > 0 ||
            noteBlockLinkRepairCount > 0 ||
            noteBlockHistoryRepairCount > 0 ||
            weeklyCalendarNoteRepairCount > 0 ||
            calendarPhotoRepairCount > 0 {
            sync.schedulePush(debounceMs: 0)
        }
        Task { await runInitialPullGate() }

        NotificationCenter.default.addObserver(
            forName: .njPullCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let bl = NJLocalBLRunner(db: self.db)
                bl.markBlocksMissingTagIndexDirty(limit: 8000)
                bl.run(.deriveBlockTagIndexAndDomainV1, limit: 2000)
                self.refreshQuickClipboardCount()
                self.refreshInvestmentCriticalNewsBadge()
                self.publishTrainingWeekSnapshotToWidget(referenceDate: Date())
                self.scheduleGoalJournalWidgetRefresh(delayMs: 250)
                self.scheduleTimeSlotWidgetRefresh(delayMs: 250)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .njGoalUpdated,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleGoalJournalWidgetRefresh(delayMs: 150)
                self?.scheduleTimeSlotWidgetRefresh(delayMs: 150)
            }
        }

        NotificationCenter.default.addObserver(
            forName: .njDirtyEnqueued,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleGoalJournalWidgetRefresh(delayMs: 400)
                self?.scheduleTimeSlotWidgetRefresh(delayMs: 400)
            }
        }

        runGoalStatusMigrationIfNeeded()
        publishTrainingWeekSnapshotToWidget()
        scheduleGoalJournalWidgetRefresh(delayMs: 0)
        scheduleTimeSlotWidgetRefresh(delayMs: 0)
    }

    func presentInvestmentShortcutMenu(market: NJInvestmentShortcutMarket) {
        selectedModule = .investment
        selectedInvestmentMarket = market.investmentMarket
        pendingInvestmentShortcutMarket = market
        investmentRefreshNonce += 1
    }

    func openInvestmentShortcutDestination(_ destination: NJInvestmentShortcutDestination) {
        selectedModule = .investment
        selectedInvestmentSection = destination.section
        selectedInvestmentMarket = destination.market.investmentMarket
        if let tradeTab = destination.tradeTab {
            selectedInvestmentTradeTab = tradeTab
        }
        pendingInvestmentShortcutMarket = nil
        investmentRefreshNonce += 1
    }

    func consumePendingInvestmentShortcutFromSharedDefaults() {
        let defaults = UserDefaults(suiteName: widgetAppGroupID) ?? .standard
        guard let rawMarket = defaults.string(forKey: "nj_pending_investment_shortcut_market_v1") else { return }
        defaults.removeObject(forKey: "nj_pending_investment_shortcut_market_v1")
        presentInvestmentShortcutMenu(market: NJInvestmentShortcutMarket.from(rawValue: rawMarket))
    }

    func refreshInvestmentCriticalNewsBadge() {
        investmentCriticalNewsCount = investmentCriticalUnreadNewsCount()
    }

    private func investmentCriticalUnreadNewsCount() -> Int {
        guard let url = investmentAnalysisInboxMarkdownURL(),
              let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return 0 }
        let readMap = investmentAnalysisInboxReadMap()
        var seen = Set<String>()
        return investmentAnalysisInboxBlocks(in: text).filter { block in
            let dedupeKey = investmentAnalysisInboxDedupeKey(header: block.header, body: block.body)
            guard seen.insert(dedupeKey).inserted else { return false }
            guard investmentAnalysisInboxBlockIsCritical(header: block.header, body: block.body) else { return false }
            let id = investmentAnalysisInboxBlockID(header: block.header, body: block.body, sourceLabel: url.lastPathComponent)
            return readMap[id] == nil
        }.count
    }

    private func investmentAnalysisInboxMarkdownURL() -> URL? {
        let fm = FileManager.default
        if let root = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") {
            return root
                .appendingPathComponent("Documents", isDirectory: true)
                .appendingPathComponent("Investment", isDirectory: true)
                .appendingPathComponent("AnalysisInbox.md", isDirectory: false)
        }
        return fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("NotionJournal/Investment/AnalysisInbox.md", isDirectory: false)
    }

    private func investmentAnalysisInboxReadMap() -> [String: Double] {
        let raw = UserDefaults.standard.string(forKey: "nj_investment_analysis_inbox_read_v1") ?? "{}"
        guard let data = raw.data(using: .utf8) else { return [:] }
        return (try? JSONDecoder().decode([String: Double].self, from: data)) ?? [:]
    }

    private func investmentAnalysisInboxBlocks(in text: String) -> [(header: String, body: [String])] {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var blocks: [(header: String, body: [String])] = []
        var currentHeader: String?
        var currentBody: [String] = []

        func flush() {
            guard let currentHeader else { return }
            blocks.append((header: currentHeader, body: currentBody))
        }

        for line in lines {
            if line.hasPrefix("### ") {
                flush()
                currentHeader = String(line.dropFirst(4)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentBody = []
            } else if currentHeader != nil {
                currentBody.append(line)
            }
        }
        flush()
        return blocks
    }

    private func investmentAnalysisInboxBlockIsCritical(header: String, body: [String]) -> Bool {
        let headline = investmentAnalysisInboxField("Headline", body: body).lowercased()
        let whatHappened = investmentAnalysisInboxField("What happened", body: body).lowercased()
        let nextWatch = investmentAnalysisInboxField("Next watch", body: body).lowercased()
        let combined = "\(headline) \(whatHappened) \(nextWatch)"
        let escalationTerms = [
            "war", "invasion", "missile", "drone attack", "airstrike", "terror attack",
            "ceasefire collapse", "ceasefire collapsed", "blockade", "strait",
            "red sea", "taiwan", "nato", "mobilization", "martial law", "sanction",
            "project freedom",
            "default", "missed payment", "bank run", "deposit freeze", "debt restructuring",
            "failed auction", "weak auction", "auction tail", "tails", "emergency treasury",
            "currency slump", "currency slumped", "currency plunge", "devaluation",
            "capital controls", "fx intervention", "circuit breaker", "trading halt",
            "bank failure", "sovereign downgrade", "emergency rate hike", "bond rout"
        ]
        let geopoliticalActors = [
            "trump", "white house", "iran", "israel", "russia", "ukraine", "china",
            "taiwan", "nato", "gulf", "hormuz", "opec"
        ]
        let geopoliticalActions = [
            "deal", "peace", "ceasefire", "negotiate", "negotiation", "talks",
            "sanction", "nuclear", "attack", "strike", "retaliation", "blockade", "closed", "over"
        ]
        let promoTerms = [
            "press release", "collaborat", "partnership", "partner", "expands ai",
            "ai capabilities", "ai-powered features", "conference", "media alert",
            "price target", "raised to", "upgraded", "downgraded", "earnings",
            "revenue", "eps", "guidance", "shares", "stock", "rebound", "selloff",
            "slump", "beat", "miss", "analyst", "barrons", "market talk",
            "launches", "introducing", "platform", "software"
        ]
        let hasEmergencyTerm = escalationTerms.contains { investmentNewsContainsRiskTerm($0, in: combined) }
        let hasGeopoliticalActor = geopoliticalActors.contains { investmentNewsContainsRiskTerm($0, in: combined) }
        let hasGeopoliticalAction = geopoliticalActions.contains { combined.contains($0) }
        let looksPromotional = promoTerms.contains { combined.contains($0) }
        if hasEmergencyTerm || (hasGeopoliticalActor && hasGeopoliticalAction) { return true }
        if looksPromotional { return false }
        return false
    }

    private func investmentAnalysisInboxBlockID(header: String, body: [String], sourceLabel: String) -> String {
        let cloudKitNewsID = investmentAnalysisInboxField("CloudKit News ID", body: body)
        if !cloudKitNewsID.isEmpty { return cloudKitNewsID }
        let parsedVerdict = investmentAnalysisInboxField("Verdict", body: body)
        let verdict = parsedVerdict.isEmpty ? "No Signal" : parsedVerdict
        let notify = investmentAnalysisInboxField("Notify", body: body).lowercased().hasPrefix("y")
        let headline = cleanInvestmentNewsHeadline(investmentAnalysisInboxField("Headline", body: body))
        var whatHappened = investmentAnalysisInboxField("What happened", body: body)
        let tradeRead = investmentAnalysisInboxField("Trade read", body: body)
        let nextWatch = investmentAnalysisInboxField("Next watch", body: body)
        let cleanedBody = body.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        if whatHappened.isEmpty && tradeRead.isEmpty && nextWatch.isEmpty {
            whatHappened = cleanedBody
        }
        let rawID = "\(header)\n\(verdict)\n\(notify ? 1 : 0)\n\(headline)\n\(whatHappened)\n\(tradeRead)\n\(nextWatch)\n\(sourceLabel)"
        let hash = SHA256.hash(data: Data(rawID.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func investmentAnalysisInboxDedupeKey(header: String, body: [String]) -> String {
        let headline = investmentAnalysisInboxField("Headline", body: body)
        let whatHappened = investmentAnalysisInboxField("What happened", body: body)
        let base = headline.isEmpty ? whatHappened : headline
        let cleaned = cleanInvestmentNewsHeadline(base).lowercased()
        let words = cleaned
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty && $0 != "and" && $0 != "to" && $0 != "the" && $0 != "a" && $0 != "an" }
        if cleaned.contains("collaborat") || cleaned.contains("partnership") || cleaned.contains("partner") {
            let entityWords = words.filter {
                !["collaborate", "collaborates", "collaboration", "partnership", "partner", "partners", "explore", "expands", "accelerate", "across", "with", "on", "ai", "innovation", "technological", "technology", "capabilities", "powered", "features", "saudi", "arabia"].contains($0)
            }
            if entityWords.count >= 2 {
                return "collab " + entityWords.prefix(2).joined(separator: " ")
            }
        }
        if !words.isEmpty {
            return words.prefix(14).joined(separator: " ")
        }
        return header.lowercased()
    }

    private func categoryContainsMacroRisk(header: String, body: [String]) -> Bool {
        let category = investmentAnalysisInboxField("Category", body: body).lowercased()
        let text = "\(header) \(category)"
        return ["macro", "geopolitical", "credit", "fx", "rates", "sovereign", "bond", "treasury", "currency"].contains { text.contains($0) }
    }

    private func cleanInvestmentNewsHeadline(_ title: String) -> String {
        title
            .replacingOccurrences(of: #"\{A:[^}]+\}"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)^press release:\s*"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #">\w+$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func investmentNewsContainsRiskTerm(_ term: String, in text: String) -> Bool {
        let escaped = NSRegularExpression.escapedPattern(for: term)
        let pattern = #"(?<![A-Za-z0-9])"# + escaped + #"(?![A-Za-z0-9])"#
        return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    private func investmentAnalysisInboxField(_ key: String, body: [String]) -> String {
        let prefix = key + ":"
        for line in body {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.lowercased().hasPrefix(prefix.lowercased()) {
                return trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        return ""
    }

    private func runGoalStatusMigrationIfNeeded() {
        let key = "nj_migrate_goal_status_tagged_v1"
        if UserDefaults.standard.bool(forKey: key) { return }
        let count = notes.migrateGoalStatusForTaggedGoals()
        if count > 0 {
            goalMigrationCount = count
            showGoalMigrationAlert = true
            sync.schedulePush(debounceMs: 0)
        }
        UserDefaults.standard.set(true, forKey: key)
    }

    func refreshQuickClipboardCount() {
        quickClipboardCount = notes.listOrphanQuickBlocks(limit: 2000).count
    }

    private func runAttachmentCacheCleanupIfNeeded() {
        let key = "nj_attachment_cache_cleanup_ms"
        let now = Int64(Date().timeIntervalSince1970 * 1000.0)
        let last = Int64(UserDefaults.standard.double(forKey: key))
        let dayMs: Int64 = 24 * 60 * 60 * 1000
        if last > 0, now - last < dayMs { return }
        UserDefaults.standard.set(Double(now), forKey: key)

        NJAttachmentCache.cleanupOlderThan(days: 30) { [weak self] attachmentID in
            self?.notes.clearAttachmentThumbPath(attachmentID: attachmentID, nowMs: now)
        }
    }

    private func seedOfficialFinanceMacroCalendar2026() {
        let seedVersion = "nj_finance_macro_seed_2026_v1"
        let seed = officialFinanceMacroSeed2026()
        let existingIDs = Set(notes.listFinanceMacroEvents(startKey: "2026-03-01", endKey: "2026-12-31").map(\.eventID))
        let pending = seed.filter { !existingIDs.contains($0.id) }
        guard !pending.isEmpty else {
            UserDefaults.standard.set(true, forKey: seedVersion)
            return
        }

        let now = DBNoteRepository.nowMs()
        for item in pending {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: item.id,
                    dateKey: item.dateKey,
                    title: item.title,
                    category: item.category,
                    region: item.region,
                    timeText: item.timeText,
                    impact: item.impact,
                    source: item.source,
                    notes: item.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
        }
        UserDefaults.standard.set(true, forKey: seedVersion)
        sync.schedulePush(debounceMs: 0)
    }

    private func officialFinanceMacroSeed2026() -> [(id: String, dateKey: String, title: String, category: String, region: String, timeText: String, impact: String, source: String, notes: String)] {
        let fedURL = "https://www.federalreserve.gov/monetarypolicy/fomccalendars.htm"
        let blsCPIURL = "https://www.bls.gov/schedule/news_release/cpi.htm"
        let blsJobsURL = "https://www.bls.gov/schedule/news_release/empsit.htm"
        let beaURL = "https://www.bea.gov/news/schedule"
        let ecbURL = "https://www.ecb.europa.eu/press/calendars/mgcgc/html/index.en.html"
        let bojURL = "https://www.boj.or.jp/en/mopo/mpmsche_minu/index.htm"

        return [
            ("official.fed.fomc.2026-03-18", "2026-03-18", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),
            ("official.fed.fomc.2026-04-29", "2026-04-29", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),
            ("official.fed.fomc.2026-06-17", "2026-06-17", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),
            ("official.fed.fomc.2026-07-29", "2026-07-29", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),
            ("official.fed.fomc.2026-09-16", "2026-09-16", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),
            ("official.fed.fomc.2026-10-28", "2026-10-28", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),
            ("official.fed.fomc.2026-12-09", "2026-12-09", "FOMC rate decision", "central_bank", "US", "TBD", "high", "Federal Reserve", "Official calendar: \(fedURL)"),

            ("official.bls.cpi.2026-03-12", "2026-03-12", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-04-10", "2026-04-10", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-05-12", "2026-05-12", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-06-11", "2026-06-11", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-07-15", "2026-07-15", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-08-12", "2026-08-12", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-09-11", "2026-09-11", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-10-15", "2026-10-15", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-11-13", "2026-11-13", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),
            ("official.bls.cpi.2026-12-15", "2026-12-15", "US CPI release", "inflation", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsCPIURL)"),

            ("official.bls.payrolls.2026-04-03", "2026-04-03", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-05-08", "2026-05-08", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-06-05", "2026-06-05", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-07-02", "2026-07-02", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-08-07", "2026-08-07", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-09-04", "2026-09-04", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-10-02", "2026-10-02", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-11-06", "2026-11-06", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),
            ("official.bls.payrolls.2026-12-04", "2026-12-04", "US Employment Situation", "labor", "US", "08:30 ET", "high", "BLS", "Official schedule: \(blsJobsURL)"),

            ("official.bea.pce.2026-03-27", "2026-03-27", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-04-30", "2026-04-30", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-05-29", "2026-05-29", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-06-26", "2026-06-26", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-07-31", "2026-07-31", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-08-28", "2026-08-28", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-09-25", "2026-09-25", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-10-30", "2026-10-30", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-11-25", "2026-11-25", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),
            ("official.bea.pce.2026-12-23", "2026-12-23", "US Personal Income and Outlays (PCE)", "inflation", "US", "10:00 ET", "high", "BEA", "Official release schedule: \(beaURL)"),

            ("official.ecb.2026-03-19", "2026-03-19", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),
            ("official.ecb.2026-04-30", "2026-04-30", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),
            ("official.ecb.2026-06-04", "2026-06-04", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),
            ("official.ecb.2026-07-23", "2026-07-23", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),
            ("official.ecb.2026-09-10", "2026-09-10", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),
            ("official.ecb.2026-10-29", "2026-10-29", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),
            ("official.ecb.2026-12-17", "2026-12-17", "ECB monetary policy meeting", "central_bank", "Euro Area", "TBD", "high", "ECB", "Official calendar: \(ecbURL)"),

            ("official.boj.2026-03-19", "2026-03-19", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)"),
            ("official.boj.2026-04-30", "2026-04-30", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)"),
            ("official.boj.2026-06-16", "2026-06-16", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)"),
            ("official.boj.2026-07-30", "2026-07-30", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)"),
            ("official.boj.2026-09-18", "2026-09-18", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)"),
            ("official.boj.2026-10-29", "2026-10-29", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)"),
            ("official.boj.2026-12-18", "2026-12-18", "BOJ monetary policy meeting", "central_bank", "Japan", "TBD", "high", "BOJ", "Official schedule: \(bojURL)")
        ]
    }

    private func seedInvestmentMacroCalendar2026() {
        let seedVersion = "nj_investment_macro_seed_2026_v2"
        let seed = investmentMacroSeed2026()
        let existingIDs = Set(notes.listFinanceMacroEvents(startKey: "2026-05-01", endKey: "2026-12-31").map(\.eventID))
        let pending = seed.filter { !existingIDs.contains($0.id) }
        guard !pending.isEmpty else {
            UserDefaults.standard.set(true, forKey: seedVersion)
            return
        }

        let now = DBNoteRepository.nowMs()
        for item in pending {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: item.id,
                    dateKey: item.dateKey,
                    title: item.title,
                    category: item.category,
                    region: item.region,
                    timeText: item.timeText,
                    impact: item.impact,
                    source: item.source,
                    notes: item.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
        }
        UserDefaults.standard.set(true, forKey: seedVersion)
        sync.schedulePush(debounceMs: 0)
    }

    private func investmentMacroSeed2026() -> [(id: String, dateKey: String, title: String, category: String, region: String, timeText: String, impact: String, source: String, notes: String)] {
        let censusURL = "https://www.census.gov/economic-indicators/calendar-listview.html"
        let treasuryURL = "https://home.treasury.gov/news/press-releases"
        let fedBioURL = "https://www.federalreserve.gov/aboutthefed/bios/board/powell.htm"
        let nvidiaURL = "https://investor.nvidia.com/events-and-presentations/events-and-presentations/default.aspx"
        let chinaNBSURL = "https://www.stats.gov.cn/english/PressRelease/ReleaseCalendar/"
        let hongKongURL = "https://www.censtatd.gov.hk/en/press_release/index.html"
        let japanStatsURL = "https://www.stat.go.jp/english/data/"
        let tencentIRURL = "https://www.tencent.com/en-us/investors.html"
        let alibabaIRURL = "https://www.alibabagroup.com/en/ir/home"
        let jdIRURL = "https://ir.jd.com/"
        let baiduIRURL = "https://ir.baidu.com/"
        let softBankIRURL = "https://group.softbank/en/ir"
        let sonyIRURL = "https://www.sony.com/en/SonyInfo/IR/"
        let toyotaIRURL = "https://global.toyota/jp/ir/"
        let nintendoIRURL = "https://www.nintendo.co.jp/ir/en/schedule/index.html"
        let novoIRURL = "https://www.novonordisk.com/investors/financial-results.html"
        let shellIRURL = "https://www.shell.com/investors/results-and-reporting/annual-report.html"
        let siemensIRURL = "https://www.siemens.com/en-us/company/investor-relations/financial-calendar/"

        return [
            ("investment.us.retail_sales.2026-05-15", "2026-05-15", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-06-16", "2026-06-16", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "June convergence watch. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-07-16", "2026-07-16", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-08-14", "2026-08-14", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-09-15", "2026-09-15", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-10-16", "2026-10-16", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-11-17", "2026-11-17", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),
            ("investment.us.retail_sales.2026-12-17", "2026-12-17", "US Retail Sales", "consumer", "US", "08:30 ET", "high", "US Census Bureau", "Consumer-spending read for US demand. Official calendar: \(censusURL)"),

            ("investment.us.fed_chair_watch.2026-05-15", "2026-05-15", "Federal Reserve Chair transition watch", "central_bank", "US", "TBD", "high", "Federal Reserve", "Powell's Chair term is scheduled through May 15, 2026. Watch successor guidance, policy path, and market reaction. Source: \(fedBioURL)"),
            ("investment.us.nvidia_earnings.2026-05-27", "2026-05-27", "NVIDIA earnings", "earnings", "US", "After close", "high", "NVIDIA IR", "Key AI and ATH-hold catalyst. Verify final timing from investor relations before trading. Source: \(nvidiaURL)"),
            ("investment.us.treasury_refunding.2026-05-06", "2026-05-06", "US Treasury quarterly refunding watch", "debt", "US", "08:30 ET", "high", "US Treasury", "Debt supply, auction scale, and term premium watch. Verify final announcement and auction details. Source: \(treasuryURL)"),
            ("investment.us.treasury_refunding.2026-08-05", "2026-08-05", "US Treasury quarterly refunding watch", "debt", "US", "08:30 ET", "high", "US Treasury", "Debt supply, auction scale, and term premium watch. Verify final announcement and auction details. Source: \(treasuryURL)"),
            ("investment.us.treasury_refunding.2026-11-04", "2026-11-04", "US Treasury quarterly refunding watch", "debt", "US", "08:30 ET", "high", "US Treasury", "Debt supply, auction scale, and term premium watch. Verify final announcement and auction details. Source: \(treasuryURL)"),

            ("investment.hk.jd_earnings.2026-05-12", "2026-05-12", "JD.com Q1 2026 results", "earnings", "Hong Kong/China", "Before US open / 20:00 HKT call", "high", "JD.com IR", "Major China consumer and e-commerce read-through. Company said Q1 2026 results release is before the US market opens, with an 8:00 a.m. ET / 8:00 p.m. HKT call. Source: \(jdIRURL)"),
            ("investment.hk.tencent_earnings.2026-05-13", "2026-05-13", "Tencent Q1 2026 results", "earnings", "Hong Kong/China", "20:00 HKT", "high", "Tencent IR", "Mega-cap China internet, gaming, ads, and AI demand read-through. Tencent calendar lists the Q1 2026 results announcement at 20:00 HKT. Source: \(tencentIRURL)"),
            ("investment.hk.alibaba_earnings.2026-05-13", "2026-05-13", "Alibaba March quarter FY2026 results", "earnings", "Hong Kong/China", "Before US open / 19:30 HKT call", "high", "Alibaba IR", "China consumer, cloud, and AI-stack bellwether. Alibaba said results are due before the US market opens, with a 7:30 p.m. HKT conference call. Source: \(alibabaIRURL)"),
            ("investment.hk.baidu_earnings.2026-05-18", "2026-05-18", "Baidu Q1 2026 results", "earnings", "Hong Kong/China", "08:00 EDT / 20:00 HKT", "high", "Baidu IR", "China AI, search, cloud, and autonomous-driving read-through. Baidu IR calendar lists the Q1 2026 earnings conference call for 8:00 a.m. EDT. Source: \(baiduIRURL)"),

            ("investment.china.cpi_ppi.2026-05-11", "2026-05-11", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-06-10", "2026-06-10", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "June convergence watch. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-07-09", "2026-07-09", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-08-10", "2026-08-10", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-09-09", "2026-09-09", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-10-15", "2026-10-15", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-11-09", "2026-11-09", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.cpi_ppi.2026-12-09", "2026-12-09", "China CPI / PPI", "inflation", "China", "09:30 CST", "high", "NBS China", "Inflation and deflation-pressure check. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-05-19", "2026-05-19", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-06-15", "2026-06-15", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "June convergence watch across China growth, Fed, and BOJ. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-07-15", "2026-07-15", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-08-14", "2026-08-14", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-09-15", "2026-09-15", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-10-20", "2026-10-20", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-11-14", "2026-11-14", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),
            ("investment.china.activity.2026-12-15", "2026-12-15", "China activity data", "growth", "China", "10:00 CST", "high", "NBS China", "Retail sales, industrial production, fixed asset investment, and property read. Release calendar: \(chinaNBSURL)"),

            ("investment.hk.retail_sales.2026-05-04", "2026-05-04", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-06-02", "2026-06-02", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-07-02", "2026-07-02", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-08-03", "2026-08-03", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-09-01", "2026-09-01", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-10-02", "2026-10-02", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-11-02", "2026-11-02", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.retail_sales.2026-12-01", "2026-12-01", "Hong Kong retail sales", "consumer", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK consumer and mainland-spillover read. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-05-21", "2026-05-21", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-06-23", "2026-06-23", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-07-21", "2026-07-21", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-08-21", "2026-08-21", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-09-21", "2026-09-21", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-10-22", "2026-10-22", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-11-23", "2026-11-23", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),
            ("investment.hk.cpi.2026-12-21", "2026-12-21", "Hong Kong CPI", "inflation", "Hong Kong", "16:30 HKT", "medium", "Hong Kong C&SD", "HK inflation and FX-linked real rate watch. Release calendar: \(hongKongURL)"),

            ("investment.japan.nintendo_earnings.2026-05-08", "2026-05-08", "Nintendo fiscal-year results", "earnings", "Japan", "TBD JST", "high", "Nintendo IR", "Large-cap Japan consumer-tech and hardware demand check. Nintendo IR calendar lists the fiscal-year earnings release for May 8, 2026. Source: \(nintendoIRURL)"),
            ("investment.japan.sony_earnings.2026-05-08", "2026-05-08", "Sony Group FY2025 results", "earnings", "Japan", "May 8 presentation", "high", "Sony IR", "Japan consumer electronics, entertainment, sensors, and console-cycle read-through. Sony posted a Corporate Strategy and Earnings Announcement Presentation for May 8. Source: \(sonyIRURL)"),
            ("investment.japan.toyota_earnings.2026-05-08", "2026-05-08", "Toyota FY2025 results", "earnings", "Japan", "TBD JST", "high", "Toyota IR", "Japan industrial, auto, FX, and global demand bellwether. Toyota IR calendar lists fiscal-year results on May 8, 2026. Source: \(toyotaIRURL)"),
            ("investment.japan.softbank_earnings.2026-05-13", "2026-05-13", "SoftBank Group FY2025 results", "earnings", "Japan", "TBD JST", "high", "SoftBank Group IR", "Vision Fund, OpenAI exposure, and Japan tech-risk read-through. SoftBank IR calendar lists FY2025 earnings results on May 13, 2026. Source: \(softBankIRURL)"),

            ("investment.japan.national_cpi.2026-05-22", "2026-05-22", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "BOJ-rate-pressure watch. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-06-19", "2026-06-19", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "Post-BOJ June convergence check. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-07-24", "2026-07-24", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "BOJ-rate-pressure watch. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-08-21", "2026-08-21", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "BOJ-rate-pressure watch. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-09-18", "2026-09-18", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "Same day as BOJ decision. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-10-23", "2026-10-23", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "BOJ-rate-pressure watch. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-11-20", "2026-11-20", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "BOJ-rate-pressure watch. Release calendar: \(japanStatsURL)"),
            ("investment.japan.national_cpi.2026-12-18", "2026-12-18", "Japan national CPI", "inflation", "Japan", "08:30 JST", "high", "Statistics Bureau of Japan", "Same day as BOJ decision. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-05-29", "2026-05-29", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-06-26", "2026-06-26", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-07-31", "2026-07-31", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-08-28", "2026-08-28", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-09-25", "2026-09-25", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-10-30", "2026-10-30", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-11-27", "2026-11-27", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),
            ("investment.japan.tokyo_cpi.2026-12-25", "2026-12-25", "Tokyo CPI", "inflation", "Japan", "08:30 JST", "medium", "Statistics Bureau of Japan", "Early Japan inflation signal before national CPI. Release calendar: \(japanStatsURL)"),

            ("investment.europe.novo_q1.2026-05-06", "2026-05-06", "Novo Nordisk Q1 2026 results", "earnings", "Europe", "07:30 CEST", "high", "Novo Nordisk IR", "Europe healthcare and obesity-drug bellwether. Novo says Q1 2026 financial results are due at 07:30 CEST. Source: \(novoIRURL)"),
            ("investment.europe.shell_q1.2026-05-07", "2026-05-07", "Shell Q1 2026 results", "earnings", "Europe", "TBD", "high", "Shell IR", "Europe energy, oil cashflow, and capital-return read-through. Shell's 2026 financial calendar lists first-quarter results on May 7, 2026. Source: \(shellIRURL)"),
            ("investment.europe.siemens_q2.2026-05-13", "2026-05-13", "Siemens Q2 FY2026 results", "earnings", "Europe", "TBD", "high", "Siemens IR", "Europe industrial, capex, automation, and factory-demand read-through. Siemens financial calendar lists second-quarter fiscal 2026 results on May 13, 2026. Source: \(siemensIRURL)"),
            ("investment.europe.shell_q2.2026-07-30", "2026-07-30", "Shell Q2 2026 results", "earnings", "Europe", "TBD", "high", "Shell IR", "Second-half Europe energy and cash-return checkpoint. Shell's 2026 financial calendar lists second-quarter results on July 30, 2026. Source: \(shellIRURL)"),
            ("investment.europe.novo_h1.2026-08-05", "2026-08-05", "Novo Nordisk H1 2026 results", "earnings", "Europe", "07:30 CEST", "high", "Novo Nordisk IR", "Europe healthcare and obesity-drug demand follow-through. Novo says first-half 2026 results are due on August 5, 2026 at 07:30 CEST. Source: \(novoIRURL)"),

            ("investment.crypto.weekly_scan.2026-05-04", "2026-05-04", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-05-11", "2026-05-11", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-05-18", "2026-05-18", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-05-25", "2026-05-25", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-06-01", "2026-06-01", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-06-08", "2026-06-08", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-06-15", "2026-06-15", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "June convergence crypto spillover watch: liquidity, rates, USD, and risk appetite."),
            ("investment.crypto.weekly_scan.2026-06-22", "2026-06-22", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.weekly_scan.2026-06-29", "2026-06-29", "Crypto weekly catalyst scan", "crypto", "Crypto", "Weekly", "medium", "Manual watch", "Review BTC, ETH, SOL, ETF flows, stablecoin supply, regulatory headlines, and exchange stress."),
            ("investment.crypto.options_expiry.2026-05-29", "2026-05-29", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-06-26", "2026-06-26", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-07-31", "2026-07-31", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-08-28", "2026-08-28", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-09-25", "2026-09-25", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-10-30", "2026-10-30", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-11-27", "2026-11-27", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading."),
            ("investment.crypto.options_expiry.2026-12-25", "2026-12-25", "Crypto options expiry watch", "crypto", "Crypto", "TBD", "medium", "Manual watch", "Liquidity and positioning watch. Verify venue-specific open interest and expiry calendar before trading.")
        ]
    }

    private func seedMarketClosureCalendar2026() {
        let seedVersion = "nj_market_closure_seed_2026_v1"
        let seed = marketClosureSeed2026()
        let existingIDs = Set(notes.listFinanceMacroEvents(startKey: "2026-01-01", endKey: "2026-12-31").map(\.eventID))
        let pending = seed.filter { !existingIDs.contains($0.id) }
        guard !pending.isEmpty else {
            UserDefaults.standard.set(true, forKey: seedVersion)
            return
        }

        let now = DBNoteRepository.nowMs()
        for item in pending {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: item.id,
                    dateKey: item.dateKey,
                    title: item.title,
                    category: item.category,
                    region: item.region,
                    timeText: item.timeText,
                    impact: item.impact,
                    source: item.source,
                    notes: item.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
        }
        UserDefaults.standard.set(true, forKey: seedVersion)
        sync.schedulePush(debounceMs: 0)
    }

    private func seedUSMarketSnapshotBackfill2026() {
        let spxSeedVersion = "nj_us_market_snapshot_spx_2026_v1"
        let spxRows: [(dateKey: String, close: String, change: String)] = [
            ("2026-01-02", "6858.47", "n/a"), ("2026-01-05", "6902.05", "+0.64%"),
            ("2026-01-06", "6944.82", "+0.62%"), ("2026-01-07", "6920.93", "-0.34%"),
            ("2026-01-08", "6921.46", "+0.01%"), ("2026-01-09", "6966.28", "+0.65%"),
            ("2026-01-12", "6977.27", "+0.16%"), ("2026-01-13", "6963.74", "-0.19%"),
            ("2026-01-14", "6926.60", "-0.53%"), ("2026-01-15", "6944.47", "+0.26%"),
            ("2026-01-16", "6940.01", "-0.06%"), ("2026-01-20", "6796.86", "-2.06%"),
            ("2026-01-21", "6875.62", "+1.16%"), ("2026-01-22", "6913.35", "+0.55%"),
            ("2026-01-23", "6915.61", "+0.03%"), ("2026-01-26", "6950.23", "+0.50%"),
            ("2026-01-27", "6978.60", "+0.41%"), ("2026-01-28", "6978.03", "-0.01%"),
            ("2026-01-29", "6969.01", "-0.13%"), ("2026-01-30", "6939.03", "-0.43%"),
            ("2026-02-02", "6976.44", "+0.54%"), ("2026-02-03", "6917.81", "-0.84%"),
            ("2026-02-04", "6882.72", "-0.51%"), ("2026-02-05", "6798.40", "-1.23%"),
            ("2026-02-06", "6932.30", "+1.97%"), ("2026-02-09", "6964.82", "+0.47%"),
            ("2026-02-10", "6941.81", "-0.33%"), ("2026-02-11", "6941.47", "-0.00%"),
            ("2026-02-12", "6832.76", "-1.57%"), ("2026-02-13", "6836.17", "+0.05%"),
            ("2026-02-17", "6843.22", "+0.10%"), ("2026-02-18", "6881.31", "+0.56%"),
            ("2026-02-19", "6861.89", "-0.28%"), ("2026-02-20", "6909.51", "+0.69%"),
            ("2026-02-23", "6837.75", "-1.04%"), ("2026-02-24", "6890.07", "+0.77%"),
            ("2026-02-25", "6946.13", "+0.81%"), ("2026-02-26", "6908.86", "-0.54%"),
            ("2026-02-27", "6878.88", "-0.43%"), ("2026-03-02", "6881.62", "+0.04%"),
            ("2026-03-03", "6816.63", "-0.94%"), ("2026-03-04", "6869.50", "+0.78%"),
            ("2026-03-05", "6830.71", "-0.56%"), ("2026-03-06", "6740.02", "-1.33%"),
            ("2026-03-09", "6795.99", "+0.83%"), ("2026-03-10", "6781.48", "-0.21%"),
            ("2026-03-11", "6775.80", "-0.08%"), ("2026-03-12", "6672.62", "-1.52%"),
            ("2026-03-13", "6632.19", "-0.61%"), ("2026-03-16", "6699.38", "+1.01%"),
            ("2026-03-17", "6716.09", "+0.25%"), ("2026-03-18", "6624.70", "-1.36%"),
            ("2026-03-19", "6606.49", "-0.27%"), ("2026-03-20", "6506.48", "-1.51%"),
            ("2026-03-23", "6581.00", "+1.15%"), ("2026-03-24", "6556.37", "-0.37%"),
            ("2026-03-25", "6591.90", "+0.54%"), ("2026-03-26", "6477.16", "-1.74%"),
            ("2026-03-27", "6368.85", "-1.67%"), ("2026-03-30", "6343.72", "-0.39%"),
            ("2026-03-31", "6528.52", "+2.91%"), ("2026-04-01", "6575.32", "+0.72%"),
            ("2026-04-02", "6582.69", "+0.11%"), ("2026-04-06", "6611.83", "+0.44%"),
            ("2026-04-07", "6616.85", "+0.08%"), ("2026-04-08", "6782.81", "+2.51%"),
            ("2026-04-09", "6824.66", "+0.62%"), ("2026-04-10", "6816.89", "-0.11%"),
            ("2026-04-13", "6886.24", "+1.02%"), ("2026-04-14", "6967.38", "+1.18%"),
            ("2026-04-15", "7022.95", "+0.80%"), ("2026-04-16", "7041.28", "+0.26%"),
            ("2026-04-17", "7126.06", "+1.20%"), ("2026-04-20", "7109.14", "-0.24%"),
            ("2026-04-21", "7064.01", "-0.63%"), ("2026-04-22", "7137.90", "+1.05%"),
            ("2026-04-23", "7108.40", "-0.41%"), ("2026-04-24", "7165.08", "+0.80%"),
            ("2026-04-27", "7173.91", "+0.12%"), ("2026-04-28", "7138.80", "-0.49%"),
            ("2026-04-29", "7135.95", "-0.04%")
        ]
        var existingIDs = Set(notes.listFinanceMacroEvents(startKey: "2026-01-01", endKey: "2026-12-31").map(\.eventID))
        var changed = 0
        let now = DBNoteRepository.nowMs()
        for row in spxRows {
            let eventID = "market_snapshot.us.spx.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "S&P \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: row.dateKey == "2026-04-29" || row.dateKey == "2026-04-28" ? "AP / Xinhua US close recap" : (row.dateKey == "2026-04-27" ? "AP / Xinhua US close recap" : "Countryeconomy S&P 500 historical chart"),
                    notes: "S&P 500 close \(row.close), daily change \(row.change). Stored by US market session date, not by Asia/Shanghai heartbeat run date.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let dowSeedVersion = "nj_us_market_snapshot_dow_2026_v1"
        let dowRows: [(dateKey: String, close: String, change: String)] = [
            ("2026-04-27", "49167.79", "-0.13%"),
            ("2026-04-28", "49141.93", "-0.05%"),
            ("2026-04-29", "48861.81", "-0.57%")
        ]
        for row in dowRows {
            let eventID = "market_snapshot.us.dow.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "Dow \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "AP US close recap",
                    notes: "Dow Jones Industrial Average close \(row.close), daily change \(row.change). Stored by US market session date.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let nasdaqSeedVersion = "nj_us_market_snapshot_nasdaq_2026_v1"
        let nasdaqRows: [(dateKey: String, close: String, change: String)] = [
            ("2026-04-27", "24887.10", "+0.20%"),
            ("2026-04-28", "24663.80", "-0.90%"),
            ("2026-04-29", "24673.24", "+0.04%")
        ]
        for row in nasdaqRows {
            let eventID = "market_snapshot.us.nasdaq.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "Nasdaq \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "AP US close recap",
                    notes: "Nasdaq Composite close \(row.close), daily change \(row.change). Stored by US market session date.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let us10ySeedVersion = "nj_us_market_snapshot_us10y_2026_v1"
        let us10yRows: [(dateKey: String, yield: String, change: String)] = [
            ("2026-01-02", "4.16", "n/a"),
            ("2026-01-05", "4.17", "+1 bp vs Jan 2"),
            ("2026-01-06", "4.18", "+1 bp vs Jan 5"),
            ("2026-01-07", "4.20", "+2 bp vs Jan 6"),
            ("2026-01-08", "4.22", "+2 bp vs Jan 7"),
            ("2026-01-09", "4.24", "+2 bp vs Jan 8"),
            ("2026-01-12", "4.27", "+3 bp vs Jan 9"),
            ("2026-01-13", "4.28", "+1 bp vs Jan 12"),
            ("2026-01-14", "4.27", "-1 bp vs Jan 13"),
            ("2026-01-15", "4.29", "+2 bp vs Jan 14"),
            ("2026-01-16", "4.30", "+1 bp vs Jan 15"),
            ("2026-01-20", "4.25", "-5 bp vs Jan 16"),
            ("2026-01-21", "4.23", "-2 bp vs Jan 20"),
            ("2026-01-22", "4.24", "+1 bp vs Jan 21"),
            ("2026-01-23", "4.25", "+1 bp vs Jan 22"),
            ("2026-01-26", "4.27", "+2 bp vs Jan 23"),
            ("2026-01-27", "4.28", "+1 bp vs Jan 26"),
            ("2026-01-28", "4.27", "-1 bp vs Jan 27"),
            ("2026-01-29", "4.26", "-1 bp vs Jan 28"),
            ("2026-01-30", "4.26", "n/a"),
            ("2026-02-10", "4.16", "-10 bp vs Jan 30"),
            ("2026-02-26", "4.02", "-14 bp vs Feb 10"),
            ("2026-03-10", "4.15", "+13 bp vs Feb 26"),
            ("2026-03-30", "4.35", "+20 bp vs Mar 10"),
            ("2026-04-01", "4.30", "-5 bp vs Mar 30"),
            ("2026-04-10", "4.31", "+1 bp vs Apr 1"),
            ("2026-04-14", "4.26", "-5 bp vs Apr 10"),
            ("2026-04-20", "4.26", "0 bp vs Apr 14"),
            ("2026-04-22", "4.30", "+4 bp vs Apr 20"),
            ("2026-04-24", "4.31", "+1 bp vs Apr 22"),
            ("2026-04-27", "4.30", "-1 bp vs Apr 24"),
            ("2026-04-28", "4.35", "+5 bp vs Apr 27"),
            ("2026-04-29", "4.42", "+6 bp vs Apr 28")
        ]
        for row in us10yRows {
            let eventID = "market_snapshot.us.us10y.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "US10Y \(row.yield) \(row.change)",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "YCharts / Treasury yield snapshots",
                    notes: "US 10Y Treasury yield \(row.yield)%, daily move \(row.change). Yield level, not percent change.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let vixRows: [(dateKey: String, close: String, change: String)] = [
            ("2026-04-13", "19.12", "-2.05 pts / -9.68%"),
            ("2026-04-14", "18.36", "-0.76 pts / -3.97%"),
            ("2026-04-15", "18.17", "-0.19 pts / -1.03%"),
            ("2026-04-16", "17.94", "-0.23 pts / -1.27%"),
            ("2026-04-17", "17.48", "-0.46 pts / -2.56%"),
            ("2026-04-20", "18.87", "+1.39 pts / +7.95%"),
            ("2026-04-21", "19.50", "+0.63 pts / +3.34%"),
            ("2026-04-22", "18.92", "-0.58 pts / -2.97%"),
            ("2026-04-23", "19.31", "+0.39 pts / +2.06%"),
            ("2026-04-24", "18.71", "-0.60 pts / -3.11%"),
            ("2026-04-27", "18.02", "pending official Cboe Apr 28 row")
        ]
        for row in vixRows {
            let eventID = "market_snapshot.us.vix.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "VIX \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "Cboe VIX historical daily prices",
                    notes: "Official Cboe VIX close \(row.close), daily move \(row.change). Source file: https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let vixPendingEventID = "market_snapshot.us.vix.2026-04-28"
        if !existingIDs.contains(vixPendingEventID) {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: vixPendingEventID,
                    dateKey: "2026-04-28",
                    title: "VIX 18.02 pending official Cboe refresh",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: "up",
                    source: "Cboe VIX historical daily prices",
                    notes: "Target US close is Apr 28, 2026. Latest available official-style close carried into the system is 18.02 while the Apr 28 Cboe public CSV row remains pending verification.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(vixPendingEventID)
            changed += 1
        }

        let nextVIXPendingEventID = "market_snapshot.us.vix.2026-04-29"
        if !existingIDs.contains(nextVIXPendingEventID) {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: nextVIXPendingEventID,
                    dateKey: "2026-04-29",
                    title: "VIX 17.83 pending official Cboe refresh",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: "down",
                    source: "Cboe VIX historical daily prices; Saxo market quick take",
                    notes: "Target US close is Apr 29, 2026. Latest cited completed close available during this heartbeat was Apr 28 at 17.83, while direct official Cboe CSV verification for the Apr 29 row remained pending in this environment.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(nextVIXPendingEventID)
            changed += 1
        }

        let japanSeedVersion = "nj_japan_market_snapshot_2026_v1"
        let nikkeiRows: [(dateKey: String, close: String, change: String)] = [
            ("2026-04-24", "59715.96", "+0.58%"),
            ("2026-04-27", "60537.36", "+1.37%"),
            ("2026-04-28", "59917.46", "-1.02%")
        ]
        for row in nikkeiRows {
            let eventID = "market_snapshot.japan.nikkei.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "Nikkei \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "Japan",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "Xinhua / Reuters Japan close coverage",
                    notes: "Nikkei 225 close \(row.close), daily change \(row.change). Stored by Japan market-session date.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let jgbRows: [(dateKey: String, yield: String, change: String)] = [
            ("2026-04-24", "2.435", "+2 bps"),
            ("2026-04-27", "2.465", "+3 bps"),
            ("2026-04-28", "2.465", "0 bp after touching 2.48 intraday")
        ]
        for row in jgbRows {
            let eventID = "market_snapshot.japan.jgb10y.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "JGB10Y \(row.yield) \(row.change)",
                    category: "market_snapshot",
                    region: "Japan",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "Reuters / Barron's Japan rates coverage",
                    notes: "Japan 10-year government bond yield \(row.yield)%, daily move \(row.change). Stored by Japan market-session date.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let usdjpyRows: [(dateKey: String, close: String, change: String)] = [
            ("2026-04-24", "159.37", "+0.04%"),
            ("2026-04-27", "159.30", "-0.04%"),
            ("2026-04-28", "159.30", "flat after BOJ hawkish hold"),
            ("2026-04-29", "159.46", "-0.08%")
        ]
        for row in usdjpyRows {
            let eventID = "market_snapshot.japan.usdjpy.\(row.dateKey)"
            if existingIDs.contains(eventID) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: eventID,
                    dateKey: row.dateKey,
                    title: "USDJPY \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "Japan",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: "Reuters / FX market coverage",
                    notes: "USD/JPY spot \(row.close), session move \(row.change). Stored under the Japan FX monitoring line for carry-stress tracking.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(eventID)
            changed += 1
        }

        let hkChinaSeedVersion = "nj_hk_china_market_snapshot_2026_v1"
        let hkChinaRows: [(id: String, dateKey: String, title: String, impact: String, source: String, notes: String)] = [
            (
                "market_snapshot.hk_china.hang_seng.2026-04-29",
                "2026-04-29",
                "HSI 26111.84 +1.68%",
                "up",
                "Latest US-close heartbeat market snapshot",
                "Hang Seng close 26111.84, daily change +1.68%. Stored by HK market-session date."
            ),
            (
                "market_snapshot.hk_china.shanghai_a.2026-04-29",
                "2026-04-29",
                "ShanghaiA 4107.51 +0.71%",
                "up",
                "Latest US-close heartbeat market snapshot",
                "Shanghai A close 4107.51, daily change +0.71%. Stored by China market-session date."
            ),
            (
                "market_snapshot.hk_china.usdcnh.2026-04-27",
                "2026-04-27",
                "USDCNH 6.8261 -0.18%",
                "down",
                "USD/CNH historical exchange-rate table",
                "Offshore USD/CNH close 6.8261, daily change -0.18%. Stored under HK/China FX confidence line."
            ),
            (
                "market_snapshot.hk_china.usdcnh.2026-04-28",
                "2026-04-28",
                "USDCNH 6.8369 +0.16%",
                "up",
                "USD/CNH historical exchange-rate table",
                "Offshore USD/CNH close 6.8369, daily change +0.16%. Stored under HK/China FX confidence line."
            ),
            (
                "market_snapshot.hk_china.usdcnh.2026-04-29",
                "2026-04-29",
                "USDCNH 6.8467 +0.14%",
                "up",
                "USD/CNH historical exchange-rate table",
                "Offshore USD/CNH close 6.8467, daily change +0.14%. Stored under HK/China FX confidence line."
            )
        ]
        for row in hkChinaRows {
            if existingIDs.contains(row.id) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: row.id,
                    dateKey: row.dateKey,
                    title: row.title,
                    category: "market_snapshot",
                    region: "HK / China",
                    timeText: "Close",
                    impact: row.impact,
                    source: row.source,
                    notes: row.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(row.id)
            changed += 1
        }

        let europeRows: [(id: String, dateKey: String, title: String, impact: String, source: String, notes: String)] = [
            (
                "market_snapshot.europe.stoxx600.2026-04-27",
                "2026-04-27",
                "STOXX600 608.84 -0.30%",
                "down",
                "Yahoo Finance chart endpoint (^STOXX)",
                "STOXX Europe 600 close 608.84, daily change -0.30%. Stored by Europe market-session date."
            ),
            (
                "market_snapshot.europe.stoxx50.2026-04-27",
                "2026-04-27",
                "STOXX50 5860.32 -0.39%",
                "down",
                "Yahoo Finance chart endpoint (^STOXX50E)",
                "Euro Stoxx 50 close 5860.32, daily change -0.39%. Stored by Europe market-session date."
            ),
            (
                "market_snapshot.europe.bund10y.2026-04-27",
                "2026-04-27",
                "Bund10Y 3.036 +2.92 bps",
                "up",
                "Investing.com Germany 10-Year Bond Yield historical data",
                "Germany 10-year Bund yield close 3.0360%, up 2.92 bps from 3.0068% on Apr 24."
            ),
            (
                "market_snapshot.europe.uk10y.2026-04-27",
                "2026-04-27",
                "UK10Y 5.00 +8 bps intraday",
                "up",
                "MarketWatch Europe bond context",
                "UK 10-year gilt near 5.00%, about +8 bps intraday on Apr 27. Keep labeled intraday until a clean final close is captured."
            ),
            (
                "market_snapshot.europe.eurusd.2026-04-27",
                "2026-04-27",
                "EURUSD 1.1749 ECB reference",
                "up",
                "ECB reference rate",
                "EUR/USD ECB reference rate 1.1749 for Apr 27, 2026."
            )
        ]
        for row in europeRows {
            if existingIDs.contains(row.id) { continue }
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: row.id,
                    dateKey: row.dateKey,
                    title: row.title,
                    category: "market_snapshot",
                    region: "Europe",
                    timeText: "Close",
                    impact: row.impact,
                    source: row.source,
                    notes: row.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(row.id)
            changed += 1
        }

        let pendingBackfillRows: [(id: String, dateKey: String, title: String, region: String, source: String, notes: String)] = [
            ("market_snapshot.us.vix.refresh_latest_missing_2026_04_27", "2026-04-27", "VIX Apr 27 official close pending Cboe refresh", "US", "Cboe VIX historical daily prices", "Refresh VIX from Cboe daily prices as soon as the Apr 27, 2026 row appears. Current official public file is only populated through Apr 24, 2026."),
            ("market_snapshot.us.vix.backfill_from_2026_01_01", "2026-01-01", "VIX needs full backfill from 2026-01-01", "US", "Cboe VIX historical daily prices", "Backfill VIX daily close, point change, and percent change from 2026-01-01 onward using https://cdn.cboe.com/api/global/us_indices/daily_prices/VIX_History.csv."),
            ("market_snapshot.europe.stoxx600.backfill_from_2026_01_01", "2026-01-01", "STOXX Europe 600 needs backfill from 2026-01-01", "Europe", "Backfill queue", "Backfill STOXX Europe 600 daily close and percent change from 2026-01-01 onward."),
            ("market_snapshot.europe.stoxx50.backfill_from_2026_01_01", "2026-01-01", "Euro Stoxx 50 needs backfill from 2026-01-01", "Europe", "Backfill queue", "Backfill Euro Stoxx 50 daily close and percent change from 2026-01-01 onward."),
            ("market_snapshot.europe.bund10y.backfill_from_2026_01_01", "2026-01-01", "10Y Bund needs backfill from 2026-01-01", "Europe", "Backfill queue", "Backfill Germany 10Y Bund daily yield level and basis-point move from 2026-01-01 onward."),
            ("market_snapshot.europe.uk10y.backfill_from_2026_01_01", "2026-01-01", "UK 10Y Gilt needs backfill from 2026-01-01", "Europe", "Backfill queue", "Backfill UK 10Y Gilt daily yield level and basis-point move from 2026-01-01 onward."),
            ("market_snapshot.europe.eurusd.backfill_from_2026_01_01", "2026-01-01", "EUR/USD needs backfill from 2026-01-01", "Europe", "Backfill queue", "Backfill EUR/USD daily close and percent change from 2026-01-01 onward.")
        ]
        for row in pendingBackfillRows where !existingIDs.contains(row.id) {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: row.id,
                    dateKey: row.dateKey,
                    title: row.title,
                    category: "market_snapshot_backfill",
                    region: row.region,
                    timeText: "Pending",
                    impact: "medium",
                    source: row.source,
                    notes: row.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert(row.id)
            changed += 1
        }

        UserDefaults.standard.set(true, forKey: spxSeedVersion)
        UserDefaults.standard.set(true, forKey: dowSeedVersion)
        UserDefaults.standard.set(true, forKey: nasdaqSeedVersion)
        UserDefaults.standard.set(true, forKey: us10ySeedVersion)
        UserDefaults.standard.set(true, forKey: japanSeedVersion)
        UserDefaults.standard.set(true, forKey: hkChinaSeedVersion)
        if changed > 0 {
            print("NJ_US_MARKET_SNAPSHOT_SEED changed=\(changed)")
            sync.schedulePush(debounceMs: 0)
        }
    }

    private func seedInvestmentLedgerSQQQTradeV1() {
        let transactionID = "investment.sqqq.P309105"
        let now = DBNoteRepository.nowMs()
        let tradeDateKey = "2026-04-30"
        let symbol = "SQQQ"
        let tradeThesis = "2026 Q1 US Trade"
        let institution = "HSBC Investment"
        let accountID = "investment"
        let accountLabel = "HSBC Investment"
        let quantity = 200.0
        let executionPrice = 53.50
        let grossNotional = quantity * executionPrice
        let rawPayload: [String: Any] = [
            "schema": "investment_ledger_execution_v1",
            "order_ref": "P309105",
            "order_status": "Fully Executed",
            "order_type": "BUY",
            "institution": institution,
            "account_id": accountID,
            "account_label": accountLabel,
            "region": "US",
            "trade": "USQ12026",
            "symbol": symbol,
            "instrument_name": "ULTRAPRO SHORT / ProShares UltraPro Short QQQ",
            "side": "BUY",
            "quantity": quantity,
            "execution_price": executionPrice,
            "total_executed_quantity": quantity,
            "gross_notional": grossNotional,
            "currency": "USD",
            "fees_status": "Pending statement",
            "transaction_cost": NSNull(),
            "trade_thesis": tradeThesis,
            "source_text": "Fully Executed BUY Trade Order of SQQQ: ULTRAPRO SHORT. Order ref P309105. Market execution price USD53.50. Total executed quantity 200."
        ]

        let existingTransaction = notes.financeTransactionByFingerprint(transactionID)
        notes.upsertFinanceTransaction(
            NJFinanceTransaction(
                transactionID: transactionID,
                fingerprint: transactionID,
                sourceType: "broker_trade",
                accountID: accountID,
                accountLabel: accountLabel,
                externalRef: "P309105",
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                dateKey: tradeDateKey,
                merchantName: symbol,
                amountMinor: -Int64((grossNotional * 100).rounded()),
                currencyCode: "USD",
                direction: "outflow",
                analysisNature: "investment_trade",
                category: "Investment Transaction",
                tagText: "SQQQ, P309105, 2026Q1 US Trade, QQQ short",
                fxRateToCNY: 1.0,
                amountCNYMinor: 0,
                status: "open",
                counterparty: institution,
                itemName: "ProShares UltraPro Short QQQ",
                details: "Transaction 1 | Date \(tradeDateKey) | Bank Reference P309105 | Bank \(institution) | Symbol SQQQ | CCY USD | Qty 200 | Price 53.50 | Region US | Trade USQ12026",
                note: "Atomic investment transaction row. Symbol, institution/account, side, quantity, price, currency, fees, and order ref are the basis for all position/thesis views.",
                importBatchID: "manual-2026q1-us-trade",
                sourceFileName: "manual_trade_confirmation_P309105",
                rawPayloadJSON: jsonString(rawPayload),
                createdAtMs: existingTransaction?.createdAtMs ?? now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        notes.upsertInvestmentLedgerTransaction(
            NJInvestmentLedgerTransaction(
                ledgerTransactionID: "investment-ledger.P309105.SQQQ",
                transactionNumber: 1,
                tradeDateKey: tradeDateKey,
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                institution: institution,
                accountID: accountID,
                accountLabel: accountLabel,
                brokerReference: "P309105",
                symbol: symbol,
                instrumentName: "ProShares UltraPro Short QQQ",
                assetClass: "ETF",
                region: "US",
                tradeCode: "USQ12026",
                tradeThesis: tradeThesis,
                side: "BUY",
                quantity: quantity,
                price: executionPrice,
                currencyCode: "USD",
                grossAmount: grossNotional,
                fees: 0,
                netAmount: grossNotional,
                fxRateToBase: 1.0,
                baseCurrencyCode: "USD",
                status: "Open",
                sourceType: "broker_trade",
                sourceFileName: "manual_trade_confirmation_P309105",
                rawPayloadJSON: jsonString(rawPayload),
                note: "First leg of QQQ short thesis under 2026 Q1 US Trade. Fees pending investment statement.",
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )
        retireInvestmentLedgerCards()

        sync.schedulePush(debounceMs: 0)
        reloadNotebooksTabsFromDB()
    }

    private func seedInvestmentLedgerPLTRTradeV1() {
        let transactionID = "investment.pltr.P542076"
        let now = DBNoteRepository.nowMs()
        let tradeDateKey = "2026-05-07"
        let symbol = "PLTR"
        let tradeThesis = "2026 Q1 US Trade"
        let tradeCode = "USQ12026"
        let institution = "HSBC Investment"
        let accountID = "014-809974-888"
        let accountLabel = "HSBC Premier Investment Services"
        let quantity = 150.0
        let executionPrice = 138.160
        let grossNotional = quantity * executionPrice
        let rawPayload: [String: Any] = [
            "schema": "investment_ledger_execution_v1",
            "order_ref": "P542076",
            "order_status": "Fully Executed",
            "order_type": "BUY",
            "institution": institution,
            "account_id": accountID,
            "account_label": accountLabel,
            "hold_securities_in": "HSBC Premier Investment Services 014-809974-888",
            "pay_from": "HSBC Premier USD Savings 014-809974-888",
            "region": "US",
            "market": "United States",
            "trade": tradeCode,
            "symbol": symbol,
            "instrument_name": "Palantir Technologies Inc.",
            "side": "BUY",
            "quantity": quantity,
            "execution_price": executionPrice,
            "total_executed_quantity": quantity,
            "gross_notional": grossNotional,
            "currency": "USD",
            "good_until": "2026-05-07 U.S. ET",
            "order_placed_on": "2026-05-07 U.S. ET",
            "order_placed_via": "Mobile Banking",
            "fees_status": "Pending statement",
            "transaction_cost": NSNull(),
            "trade_thesis": tradeThesis,
            "source_text": "Fully Executed BUY Trade Order of PLTR. Order ref P542076. Limit price USD138.160. Total executed quantity 150."
        ]

        let existingTransaction = notes.financeTransactionByFingerprint(transactionID)
        notes.upsertFinanceTransaction(
            NJFinanceTransaction(
                transactionID: transactionID,
                fingerprint: transactionID,
                sourceType: "broker_trade",
                accountID: accountID,
                accountLabel: accountLabel,
                externalRef: "P542076",
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                dateKey: tradeDateKey,
                merchantName: symbol,
                amountMinor: -Int64((grossNotional * 100).rounded()),
                currencyCode: "USD",
                direction: "outflow",
                analysisNature: "investment_trade",
                category: "Investment Transaction",
                tagText: "PLTR, P542076, 2026Q1 US Trade, Palantir",
                fxRateToCNY: 1.0,
                amountCNYMinor: 0,
                status: "open",
                counterparty: institution,
                itemName: "Palantir Technologies Inc.",
                details: "Transaction 2 | Date \(tradeDateKey) | Bank Reference P542076 | Bank \(institution) | Symbol PLTR | CCY USD | Qty 150 | Price 138.160 | Region US | Trade \(tradeCode)",
                note: "Atomic investment transaction row. Fees pending investment statement.",
                importBatchID: "manual-2026q1-us-trade",
                sourceFileName: "manual_trade_confirmation_P542076",
                rawPayloadJSON: jsonString(rawPayload),
                createdAtMs: existingTransaction?.createdAtMs ?? now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        notes.upsertInvestmentLedgerTransaction(
            NJInvestmentLedgerTransaction(
                ledgerTransactionID: "investment-ledger.P542076.PLTR",
                transactionNumber: 2,
                tradeDateKey: tradeDateKey,
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                institution: institution,
                accountID: accountID,
                accountLabel: accountLabel,
                brokerReference: "P542076",
                symbol: symbol,
                instrumentName: "Palantir Technologies Inc.",
                assetClass: "Equity",
                region: "US",
                tradeCode: tradeCode,
                tradeThesis: tradeThesis,
                side: "BUY",
                quantity: quantity,
                price: executionPrice,
                currencyCode: "USD",
                grossAmount: grossNotional,
                fees: 0,
                netAmount: grossNotional,
                fxRateToBase: 1.0,
                baseCurrencyCode: "USD",
                status: "Open",
                sourceType: "broker_trade",
                sourceFileName: "manual_trade_confirmation_P542076",
                rawPayloadJSON: jsonString(rawPayload),
                note: "Second leg under 2026 Q1 US Trade. PLTR BUY 150 @ USD138.160, ref P542076. Fees pending investment statement.",
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        sync.schedulePush(debounceMs: 0)
        reloadNotebooksTabsFromDB()
    }

    private func seedInvestmentLedgerSLVTradeV1() {
        let transactionID = "investment.slv.ORD21923355"
        let now = DBNoteRepository.nowMs()
        let tradeDateKey = "2026-05-07"
        let symbol = "SLV"
        let tradeThesis = "2026 Q1 US Trade"
        let tradeCode = "USQ12026"
        let institution = "Bank of East Asia Investment"
        let accountID = "bea-investment"
        let accountLabel = "BEA Investment"
        let quantity = 70.0
        let executionPrice = 73.30
        let grossNotional = quantity * executionPrice
        let rawPayload: [String: Any] = [
            "schema": "investment_ledger_execution_v1",
            "reference_number": "ORD 21923355",
            "order_ref": "ORD21923355",
            "order_status": "Fully Executed",
            "order_type": "BUY",
            "institution": institution,
            "account_id": accountID,
            "account_label": accountLabel,
            "region": "US",
            "market": "United States",
            "trade": tradeCode,
            "symbol": "SLV(US)",
            "instrument_name": "iShares Silver Trust",
            "side": "BUY",
            "quantity": quantity,
            "execution_price": executionPrice,
            "average_execution_price": executionPrice,
            "total_executed_quantity": quantity,
            "gross_notional": grossNotional,
            "currency": "USD",
            "expiry_date": "2026-05-07",
            "fees_status": "Pending statement",
            "transaction_cost": NSNull(),
            "trade_thesis": tradeThesis,
            "source_text": "東亞銀行 reference ORD 21923355. Buy SLV(US). Expiry 2026/05/07. Average execution price USD73.30. Executed 70 shares. Status fully executed."
        ]

        let existingTransaction = notes.financeTransactionByFingerprint(transactionID)
        notes.upsertFinanceTransaction(
            NJFinanceTransaction(
                transactionID: transactionID,
                fingerprint: transactionID,
                sourceType: "broker_trade",
                accountID: accountID,
                accountLabel: accountLabel,
                externalRef: "ORD21923355",
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                dateKey: tradeDateKey,
                merchantName: symbol,
                amountMinor: -Int64((grossNotional * 100).rounded()),
                currencyCode: "USD",
                direction: "outflow",
                analysisNature: "investment_trade",
                category: "Investment Transaction",
                tagText: "SLV, ORD21923355, 2026Q1 US Trade, silver",
                fxRateToCNY: 1.0,
                amountCNYMinor: 0,
                status: "open",
                counterparty: institution,
                itemName: "iShares Silver Trust",
                details: "Transaction 3 | Date \(tradeDateKey) | Bank Reference ORD 21923355 | Bank \(institution) | Symbol SLV | CCY USD | Qty 70 | Price 73.30 | Region US | Trade \(tradeCode)",
                note: "Atomic investment transaction row. Fees pending investment statement.",
                importBatchID: "manual-2026q1-us-trade",
                sourceFileName: "manual_trade_confirmation_ORD21923355",
                rawPayloadJSON: jsonString(rawPayload),
                createdAtMs: existingTransaction?.createdAtMs ?? now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        notes.upsertInvestmentLedgerTransaction(
            NJInvestmentLedgerTransaction(
                ledgerTransactionID: "investment-ledger.ORD21923355.SLV",
                transactionNumber: 3,
                tradeDateKey: tradeDateKey,
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                institution: institution,
                accountID: accountID,
                accountLabel: accountLabel,
                brokerReference: "ORD21923355",
                symbol: symbol,
                instrumentName: "iShares Silver Trust",
                assetClass: "ETF",
                region: "US",
                tradeCode: tradeCode,
                tradeThesis: tradeThesis,
                side: "BUY",
                quantity: quantity,
                price: executionPrice,
                currencyCode: "USD",
                grossAmount: grossNotional,
                fees: 0,
                netAmount: grossNotional,
                fxRateToBase: 1.0,
                baseCurrencyCode: "USD",
                status: "Open",
                sourceType: "broker_trade",
                sourceFileName: "manual_trade_confirmation_ORD21923355",
                rawPayloadJSON: jsonString(rawPayload),
                note: "Third leg under 2026 Q1 US Trade. SLV BUY 70 @ USD73.30, ref ORD 21923355. Fees pending investment statement.",
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        sync.schedulePush(debounceMs: 0)
        reloadNotebooksTabsFromDB()
    }

    private func seedInvestmentLedgerSMICTradeV1() {
        let transactionID = "investment.smic.U12285031.20260507"
        let now = DBNoteRepository.nowMs()
        let tradeDateKey = "2026-05-07"
        let symbol = "0981 HK"
        let tradeThesis = "China AI Trade"
        let tradeCode = "CHINAAI2026"
        let institution = "IBKR"
        let accountID = "U12285031"
        let accountLabel = "IBKR"
        let quantity = 6500.0
        let executionPrice = 76.55
        let fees = 809.979525
        let grossNotional = quantity * executionPrice
        let netAmount = grossNotional + fees
        let rawPayload: [String: Any] = [
            "schema": "investment_ledger_execution_v1",
            "order_ref": "U12285031-20260507-092015",
            "order_status": "Fully Executed",
            "order_type": "BUY",
            "institution": institution,
            "account_id": accountID,
            "account_label": accountLabel,
            "region": "HK/China",
            "market": "Hong Kong",
            "trade": tradeCode,
            "symbol": symbol,
            "instrument_name": "Semiconductor Manufacturing International Corporation",
            "side": "BUY",
            "quantity": quantity,
            "execution_price": executionPrice,
            "total_executed_quantity": quantity,
            "gross_notional": grossNotional,
            "fees": fees,
            "net_amount": netAmount,
            "currency": "HKD",
            "trade_thesis": tradeThesis,
            "confirmed_at": "2026-05-07 09:20:15",
            "source_text": "IBKR U12285031 buy confirmed 2026-05-07 09:20:15. BUY 0981 HK / SMIC 6,500 @ HKD76.55. Commission HKD809.979525."
        ]

        let existingTransaction = notes.financeTransactionByFingerprint(transactionID)
        notes.upsertFinanceTransaction(
            NJFinanceTransaction(
                transactionID: transactionID,
                fingerprint: transactionID,
                sourceType: "broker_trade",
                accountID: accountID,
                accountLabel: accountLabel,
                externalRef: "U12285031-20260507-092015",
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                dateKey: tradeDateKey,
                merchantName: symbol,
                amountMinor: -Int64((netAmount * 100).rounded()),
                currencyCode: "HKD",
                direction: "outflow",
                analysisNature: "investment_trade",
                category: "Investment Transaction",
                tagText: "0981 HK, SMIC, IBKR, U12285031, China AI Trade",
                fxRateToCNY: 1.0,
                amountCNYMinor: 0,
                status: "open",
                counterparty: institution,
                itemName: "Semiconductor Manufacturing International Corporation",
                details: "Transaction 4 | Date \(tradeDateKey) | Reference U12285031-20260507-092015 | Bank \(institution) | Symbol 0981 HK | CCY HKD | Qty 6500 | Price 76.55 | Fees 809.979525 | Region HK/China | Trade \(tradeCode)",
                note: "Atomic investment transaction row for the China AI Trade. Cost includes HKD809.979525 commission.",
                importBatchID: "manual-china-ai-trade",
                sourceFileName: "manual_trade_confirmation_U12285031_20260507_092015",
                rawPayloadJSON: jsonString(rawPayload),
                createdAtMs: existingTransaction?.createdAtMs ?? now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        notes.upsertInvestmentLedgerTransaction(
            NJInvestmentLedgerTransaction(
                ledgerTransactionID: "investment-ledger.U12285031.20260507.SMIC",
                transactionNumber: 4,
                tradeDateKey: tradeDateKey,
                occurredAtMs: existingTransaction?.occurredAtMs ?? now,
                institution: institution,
                accountID: accountID,
                accountLabel: accountLabel,
                brokerReference: "U12285031-20260507-092015",
                symbol: symbol,
                instrumentName: "Semiconductor Manufacturing International Corporation",
                assetClass: "Equity",
                region: "HK/China",
                tradeCode: tradeCode,
                tradeThesis: tradeThesis,
                side: "BUY",
                quantity: quantity,
                price: executionPrice,
                currencyCode: "HKD",
                grossAmount: grossNotional,
                fees: fees,
                netAmount: netAmount,
                fxRateToBase: 1.0,
                baseCurrencyCode: "HKD",
                status: "Open",
                sourceType: "broker_trade",
                sourceFileName: "manual_trade_confirmation_U12285031_20260507_092015",
                rawPayloadJSON: jsonString(rawPayload),
                note: "China AI Trade. SMIC BUY 6,500 @ HKD76.55, commission HKD809.979525, confirmed 2026-05-07 09:20:15.",
                createdAtMs: now,
                updatedAtMs: now,
                deleted: 0
            )
        )

        sync.schedulePush(debounceMs: 0)
        reloadNotebooksTabsFromDB()
    }

    private func retireInvestmentLedgerCards() {
        let now = DBNoteRepository.nowMs()
        let rows = db.queryRows("""
        SELECT note_id
        FROM nj_note
        WHERE deleted = 0
          AND (
              title IN (
                  'Investment Transaction Ledger',
                  'Transaction - P309105 - SQQQ BUY 200 @ USD53.50',
                  'Trade Ledger - 2026 Q1 US Trade - SQQQ - P309105'
              )
              OR card_category IN ('Investment Ledger', 'Investment Transaction')
          );
        """)
        for row in rows {
            guard let noteID = row["note_id"], !noteID.isEmpty else { continue }
            db.exec("""
            UPDATE nj_note
            SET deleted = 1,
                pinned = 0,
                updated_at_ms = \(now)
            WHERE note_id = \(sqlQuote(noteID));
            """)
            notes.enqueueDirty(entity: "note", entityID: noteID, op: "delete", updatedAtMs: now)
        }
    }

    private func ensureInvestmentLedgerCard(transactionID: String, title: String, legacyTitles: [String], body: String) {
        let target = investmentLedgerDatabaseTarget()
        let titleList = ([title] + legacyTitles).map(sqlQuote).joined(separator: ", ")
        let existingID = db.queryRows("""
        SELECT note_id
        FROM nj_note
        WHERE deleted = 0
          AND title IN (\(titleList))
        ORDER BY CASE WHEN notebook = \(sqlQuote(target.notebookTitle)) AND tab_domain = \(sqlQuote(target.tabDomain)) THEN 0 ELSE 1 END,
                 updated_at_ms DESC
        LIMIT 1;
        """).first?["note_id"]

        let existing = existingID.flatMap { notes.getNote(NJNoteID($0)) }
        var note = existing ?? notes.createNote(notebook: target.notebookTitle, tabDomain: target.tabDomain, title: title, noteType: .card)
        let createdNewNote = existing == nil
        note.notebook = target.notebookTitle
        note.tabDomain = target.tabDomain
        note.title = title
        note.deleted = 0
        note.pinned = 1
        note.noteType = .card
        note.cardCategory = "Investment Ledger"
        note.cardArea = "Investment"
        note.cardContext = ""
        note.cardStatus = "Open"
        note.cardPriority = "High"
        note.updatedAtMs = DBNoteRepository.nowMs()
        notes.upsertNote(note)
        cleanupDuplicateInvestmentLedgerCards(
            keepingNoteID: note.id.raw,
            target: target,
            titles: [title] + legacyTitles
        )

        guard createdNewNote else { return }
        let payloadJSON = NJQuickNotePayload.makePayloadJSON(from: body)
        guard let blockID = notes.createQuickNoteBlock(
            payloadJSON: payloadJSON,
            createdAtMs: DBNoteRepository.nowMs(),
            tags: ["investment", "investment-ledger", "investment-transaction", "USQ12026", "sqqq", "P309105", transactionID]
        ) else { return }
        let orderKey = notes.nextAppendOrderKey(noteID: note.id.raw)
        _ = notes.attachExistingBlockToNote(noteID: note.id.raw, blockID: blockID, orderKey: orderKey)
    }

    private func cleanupDuplicateInvestmentLedgerCards(
        keepingNoteID: String,
        target: (notebookTitle: String, tabDomain: String),
        titles: [String]
    ) {
        let titleList = titles.map(sqlQuote).joined(separator: ", ")
        let duplicateRows = db.queryRows("""
        SELECT note_id
        FROM nj_note
        WHERE deleted = 0
          AND note_id <> \(sqlQuote(keepingNoteID))
          AND (
              title IN (\(titleList))
              OR card_category IN ('Investment Ledger', 'Investment Transaction')
          )
          AND notebook = \(sqlQuote(target.notebookTitle))
          AND tab_domain = \(sqlQuote(target.tabDomain));
        """)

        guard !duplicateRows.isEmpty else { return }
        let now = DBNoteRepository.nowMs()
        for row in duplicateRows {
            guard let noteID = row["note_id"], !noteID.isEmpty else { continue }
            db.exec("""
            UPDATE nj_note
            SET deleted = 1,
                pinned = 0,
                updated_at_ms = \(now)
            WHERE note_id = \(sqlQuote(noteID));
            """)
            notes.enqueueDirty(entity: "note", entityID: noteID, op: "delete", updatedAtMs: now)
        }
    }

    private func investmentLedgerDatabaseTarget() -> (notebookTitle: String, tabDomain: String) {
        if let row = db.queryRows("""
        SELECT n.title AS notebook_title, t.domain_key
        FROM nj_tab t
        LEFT JOIN nj_notebook n ON n.notebook_id = t.notebook_id
        WHERE (
            lower(t.notebook_id) IN ('me', 'self')
            OR lower(n.title) IN ('me', 'self')
        )
          AND lower(t.title) = 'database'
          AND t.deleted = 0
        ORDER BY CASE WHEN lower(n.title) = 'me' THEN 0 ELSE 1 END, t.ord ASC
        LIMIT 1;
        """).first,
           let notebookTitle = row["notebook_title"], !notebookTitle.isEmpty,
           let tabDomain = row["domain_key"], !tabDomain.isEmpty {
            return (notebookTitle, tabDomain)
        }

        let notebookID = UUID().uuidString.lowercased()
        notes.upsertNotebook(notebookID: notebookID, title: "Me", colorHex: "#2563EB", isArchived: 0)
        notes.upsertTab(tabID: UUID().uuidString.lowercased(), notebookID: notebookID, title: "Database", domainKey: "me.database", colorHex: "#2563EB", order: 2, isHidden: 0)
        return ("Me", "me.database")
    }

    private func cleanupDuplicateMeNotebookCreatedByInvestmentLedgerV1() {
        let now = DBNoteRepository.nowMs()
        let visibleMeExists = db.queryRows("""
        SELECT 1
        FROM nj_notebook
        WHERE deleted = 0
          AND is_archived = 0
          AND lower(title) = 'me'
          AND notebook_id <> 'ME'
        LIMIT 1;
        """).first != nil
        guard visibleMeExists else { return }

        db.exec("""
        UPDATE nj_tab
        SET deleted = 1,
            updated_at_ms = \(now)
        WHERE notebook_id = 'ME'
          AND domain_key = 'me.database';
        """)
        db.exec("""
        UPDATE nj_notebook
        SET deleted = 1,
            is_archived = 1,
            updated_at_ms = \(now)
        WHERE notebook_id = 'ME';
        """)
        notes.enqueueDirty(entity: "notebook", entityID: "ME", op: "delete", updatedAtMs: now)
        notes.enqueueDirty(entity: "tab", entityID: "ME_DATABASE", op: "delete", updatedAtMs: now)
    }

    private func jsonString(_ value: [String: Any]) -> String {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8)
        else { return "{}" }
        return string
    }

    private func marketClosureSeed2026() -> [(id: String, dateKey: String, title: String, category: String, region: String, timeText: String, impact: String, source: String, notes: String)] {
        let nyseURL = "https://www.nyse.com/markets/hours-calendars"
        let hkexURL = "https://www.hkex.com.hk/services/trading/derivatives/overview/trading-calendar-and-holiday-schedule?sc_lang=en"
        let jpxURL = "https://www.jpx.co.jp/english/corporate/about-jpx/calendar/"
        let chinaURL = "https://www.shfe.com.cn/eng/CircularNews/Circular/202512/t20251217_829807.html"

        return [
            ("market_close.us.2026-01-01", "2026-01-01", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "New Year's Day. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-01-19", "2026-01-19", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Martin Luther King Jr. Day. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-02-16", "2026-02-16", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Washington's Birthday / Presidents Day. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-04-03", "2026-04-03", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Good Friday. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-05-25", "2026-05-25", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Memorial Day. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-06-19", "2026-06-19", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Juneteenth National Independence Day. Official calendar: \(nyseURL)"),
            ("market_close.us.early.2026-07-02", "2026-07-02", "US equity market early close", "market_close", "US", "Early close", "medium", "NYSE", "Early close ahead of Independence Day observance. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-07-03", "2026-07-03", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Independence Day observed. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-09-07", "2026-09-07", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Labor Day. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-11-26", "2026-11-26", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Thanksgiving Day. Official calendar: \(nyseURL)"),
            ("market_close.us.early.2026-11-27", "2026-11-27", "US equity market early close", "market_close", "US", "Early close", "medium", "NYSE", "Day after Thanksgiving early close. Official calendar: \(nyseURL)"),
            ("market_close.us.early.2026-12-24", "2026-12-24", "US equity market early close", "market_close", "US", "Early close", "medium", "NYSE", "Christmas Eve early close. Official calendar: \(nyseURL)"),
            ("market_close.us.2026-12-25", "2026-12-25", "US equity market closed", "market_close", "US", "Closed", "medium", "NYSE", "Christmas Day. Official calendar: \(nyseURL)"),

            ("market_close.hk.2026-01-01", "2026-01-01", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "First day of January. Official calendar: \(hkexURL)"),
            ("market_close.hk.early.2026-02-16", "2026-02-16", "Hong Kong market half day", "market_close", "Hong Kong", "No afternoon session", "medium", "HKEX", "Eve of Lunar New Year. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-02-17", "2026-02-17", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Lunar New Year's Day. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-02-18", "2026-02-18", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Second day of Lunar New Year. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-02-19", "2026-02-19", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Third day of Lunar New Year. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-04-03", "2026-04-03", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Good Friday. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-04-06", "2026-04-06", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Day following Ching Ming Festival. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-04-07", "2026-04-07", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Day following Easter Monday. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-05-01", "2026-05-01", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Labour Day. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-05-25", "2026-05-25", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Day following Birthday of the Buddha. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-06-19", "2026-06-19", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Tuen Ng Festival. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-07-01", "2026-07-01", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Hong Kong SAR Establishment Day. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-10-01", "2026-10-01", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "National Day. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-10-19", "2026-10-19", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Day following Chung Yeung Festival. Official calendar: \(hkexURL)"),
            ("market_close.hk.early.2026-12-24", "2026-12-24", "Hong Kong market half day", "market_close", "Hong Kong", "No afternoon session", "medium", "HKEX", "Christmas Eve. Official calendar: \(hkexURL)"),
            ("market_close.hk.2026-12-25", "2026-12-25", "Hong Kong market closed", "market_close", "Hong Kong", "Closed", "medium", "HKEX", "Christmas Day. Official calendar: \(hkexURL)"),
            ("market_close.hk.early.2026-12-31", "2026-12-31", "Hong Kong market half day", "market_close", "Hong Kong", "No afternoon session", "medium", "HKEX", "Eve of New Year. Official calendar: \(hkexURL)"),

            ("market_close.china.2026-01-01", "2026-01-01", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "New Year's Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-01-02", "2026-01-02", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "New Year's Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-02-16", "2026-02-16", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Spring Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-02-17", "2026-02-17", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Spring Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-02-18", "2026-02-18", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Spring Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-02-19", "2026-02-19", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Spring Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-02-20", "2026-02-20", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Spring Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-02-23", "2026-02-23", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Spring Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-04-06", "2026-04-06", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Qingming Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-05-01", "2026-05-01", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Labor Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-05-04", "2026-05-04", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Labor Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-05-05", "2026-05-05", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Labor Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-06-19", "2026-06-19", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Dragon Boat Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-09-25", "2026-09-25", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "Mid-Autumn Festival holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-10-01", "2026-10-01", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "National Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-10-02", "2026-10-02", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "National Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-10-05", "2026-10-05", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "National Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-10-06", "2026-10-06", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "National Day holiday. Official schedule: \(chinaURL)"),
            ("market_close.china.2026-10-07", "2026-10-07", "Mainland China market closed", "market_close", "China", "Closed", "medium", "SHFE / CSRC schedule", "National Day holiday. Official schedule: \(chinaURL)"),

            ("market_close.japan.2026-01-01", "2026-01-01", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "New Year's Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-01-02", "2026-01-02", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Market holiday. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-01-12", "2026-01-12", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Coming of Age Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-02-11", "2026-02-11", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "National Foundation Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-02-23", "2026-02-23", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Emperor's Birthday. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-03-20", "2026-03-20", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Vernal Equinox. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-04-29", "2026-04-29", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Showa Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-05-04", "2026-05-04", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Greenery Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-05-05", "2026-05-05", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Children's Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-05-06", "2026-05-06", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Constitution Memorial Day observed. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-07-20", "2026-07-20", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Marine Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-08-11", "2026-08-11", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Mountain Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-09-21", "2026-09-21", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Respect for the Aged Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-09-22", "2026-09-22", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Holiday under Japan national holiday rules. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-09-23", "2026-09-23", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Autumnal Equinox. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-10-12", "2026-10-12", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Sports Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-11-03", "2026-11-03", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Culture Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-11-23", "2026-11-23", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Labor Thanksgiving Day. Official calendar: \(jpxURL)"),
            ("market_close.japan.2026-12-31", "2026-12-31", "Japan market closed", "market_close", "Japan", "Closed", "medium", "JPX", "Market holiday. Official calendar: \(jpxURL)")
        ]
    }

    private func seedRenewalRegistryV1() {
        let seedVersion = "nj_renewal_registry_seed_v1"
        let existingIDs = Set(notes.listRenewalItems(ownerScope: "ME").map(\.renewalItemID))
        let pending = renewalRegistrySeedV1().filter { !existingIDs.contains($0.id) }
        guard !pending.isEmpty else {
            UserDefaults.standard.set(true, forKey: seedVersion)
            print("NJ_RENEWAL_SEED skipped existing=\(existingIDs.count)")
            return
        }

        let now = DBNoteRepository.nowMs()
        for seed in pending {
            notes.upsertRenewalItem(
                NJRenewalItemRecord(
                    renewalItemID: seed.id,
                    ownerScope: "ME",
                    personName: seed.personName,
                    documentName: seed.documentName,
                    documentType: seed.documentType,
                    jurisdiction: seed.jurisdiction,
                    documentNumberHint: seed.documentNumberHint,
                    expiryDateKey: seed.expiryDateKey,
                    status: renewalStatus(for: seed.expiryDateKey),
                    priority: renewalPriority(for: seed.expiryDateKey),
                    reminderOffsetsJSON: reminderOffsetsJSON(for: seed.documentType),
                    notes: seed.notes,
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
        }
        UserDefaults.standard.set(true, forKey: seedVersion)
        let localCount = notes.localCount(entity: "renewal_item")
        print("NJ_RENEWAL_SEED inserted=\(pending.count) local_count=\(localCount)")
        sync.schedulePush(debounceMs: 0)
    }

    private func mirrorPersonalIdentificationCards() {
        notes.portRenewalItemsToPersonalIdentificationCards()
    }

    private func enqueueCardDirtyBackfillIfNeeded() {
        let key = "nj_card_dirty_backfill_done_v1"
        if UserDefaults.standard.bool(forKey: key) { return }

        var changed = 0
        for row in db.queryRows("SELECT schema_key, updated_at_ms FROM nj_card_schema WHERE deleted = 0;") {
            guard let id = row["schema_key"], !id.isEmpty else { continue }
            notes.enqueueDirty(entity: "card_schema", entityID: id, op: "upsert", updatedAtMs: Int64(row["updated_at_ms"] ?? "") ?? DBNoteRepository.nowMs())
            changed += 1
        }
        for row in db.queryRows("SELECT card_id, updated_at_ms FROM nj_card WHERE deleted = 0;") {
            guard let id = row["card_id"], !id.isEmpty else { continue }
            notes.enqueueDirty(entity: "card", entityID: id, op: "upsert", updatedAtMs: Int64(row["updated_at_ms"] ?? "") ?? DBNoteRepository.nowMs())
            changed += 1
        }

        UserDefaults.standard.set(true, forKey: key)
        if changed > 0 {
            print("NJ_CARD_DIRTY_BACKFILL changed=\(changed)")
            sync.schedulePush(debounceMs: 0)
        }
    }

    private func enqueueInvestmentLedgerDirtyBackfillIfNeeded() -> Int {
        let key = "nj_investment_ledger_dirty_backfill_done_v1"
        if appKVValue(key) == "1" { return 0 }

        var changed = 0
        for row in db.queryRows("SELECT ledger_transaction_id, updated_at_ms FROM nj_investment_ledger_transaction WHERE deleted = 0;") {
            guard let id = row["ledger_transaction_id"], !id.isEmpty else { continue }
            let updatedAtMs = Int64(row["updated_at_ms"] ?? "") ?? DBNoteRepository.nowMs()
            notes.enqueueDirty(entity: "investment_ledger_transaction", entityID: id, op: "upsert", updatedAtMs: updatedAtMs)
            changed += 1
        }

        setAppKVValue(key, "1")
        return changed
    }

    private func runStartupOutlineBackfillIfNeeded() -> Int {
        let key = "nj_outline_dirty_backfill_done_v2"
        if appKVValue(key) == "1" { return 0 }
        let changed = notes.enqueueOutlineDirtyBackfillIfNeeded()
        setAppKVValue(key, "1")
        return changed
    }

    private func appKVValue(_ key: String) -> String {
        db.queryRows("""
        SELECT v
        FROM nj_kv
        WHERE k = \(sqlQuote(key))
        LIMIT 1;
        """).first?["v"] ?? ""
    }

    private func setAppKVValue(_ key: String, _ value: String) {
        db.exec("""
        INSERT INTO nj_kv(k, v)
        VALUES(\(sqlQuote(key)), \(sqlQuote(value)))
        ON CONFLICT(k) DO UPDATE SET v = excluded.v;
        """)
    }

    private func ensurePersonalIdentificationDatabaseNote() {
        let row = db.queryRows("""
        SELECT n.notebook_id, n.title AS notebook_title, t.domain_key
        FROM nj_tab t
        LEFT JOIN nj_notebook n ON n.notebook_id = t.notebook_id
        WHERE (
            lower(t.notebook_id) IN ('me', 'self')
            OR lower(n.title) IN ('me', 'self')
        )
          AND lower(t.title) = 'database'
          AND t.deleted = 0
        ORDER BY CASE WHEN lower(n.title) = 'me' THEN 0 ELSE 1 END, t.ord ASC
        LIMIT 1;
        """).first

        guard let row,
              let notebookTitle = row["notebook_title"], !notebookTitle.isEmpty,
              let tabDomain = row["domain_key"], !tabDomain.isEmpty else {
            return
        }

        let existingID = db.queryRows("""
        SELECT
          n.note_id,
          COALESCE(SUM(
            CASE
              WHEN nb.deleted = 0
               AND trim(nb.card_row_id) <> ''
               AND trim(nb.card_title) <> ''
               AND lower(trim(nb.card_title)) <> 'untitled block'
              THEN 1 ELSE 0
            END
          ), 0) AS data_rows
        FROM nj_note n
        LEFT JOIN nj_note_block nb ON nb.note_id = n.note_id
        WHERE n.deleted = 0
          AND n.notebook = \(sqlQuote(notebookTitle))
          AND n.tab_domain = \(sqlQuote(tabDomain))
          AND n.title = 'Personal Identification'
        GROUP BY n.note_id, n.pinned, n.updated_at_ms
        ORDER BY data_rows DESC, n.pinned DESC, n.updated_at_ms DESC
        LIMIT 1;
        """).first?["note_id"]

        let now = DBNoteRepository.nowMs()
        let note: NJNote
        if let existingID, let existing = notes.getNote(NJNoteID(existingID)) {
            let desiredCardID = existing.cardID.isEmpty ? "DB-PERSONAL-ID" : existing.cardID
            if existing.notebook == notebookTitle,
               existing.tabDomain == tabDomain,
               existing.title == "Personal Identification",
               existing.deleted == 0,
               existing.pinned == 1,
               existing.noteTypeRaw == NJNoteType.card.rawValue,
               desiredCardID == existing.cardID,
               existing.cardCategory == "Database",
               existing.cardArea == "Database",
               existing.cardContext == "Personal Identification",
               existing.cardStatus == "Active",
               existing.cardPriority == "High" {
                return
            }
            note = NJNote(
                id: existing.id,
                createdAtMs: existing.createdAtMs,
                updatedAtMs: now,
                notebook: notebookTitle,
                tabDomain: tabDomain,
                title: "Personal Identification",
                rtfData: existing.rtfData,
                deleted: existing.deleted,
                pinned: 1,
                favorited: existing.favorited,
                noteTypeRaw: NJNoteType.card.rawValue,
                dominanceModeRaw: existing.dominanceModeRaw,
                isChecklist: existing.isChecklist,
                cardID: existing.cardID.isEmpty ? "DB-PERSONAL-ID" : existing.cardID,
                cardCategory: "Database",
                cardArea: "Database",
                cardContext: "Personal Identification",
                cardStatus: "Active",
                cardPriority: "High"
            )
        } else {
            let created = notes.createNote(
                notebook: notebookTitle,
                tabDomain: tabDomain,
                title: "Personal Identification",
                noteType: .card
            )
            note = NJNote(
                id: created.id,
                createdAtMs: created.createdAtMs,
                updatedAtMs: now,
                notebook: notebookTitle,
                tabDomain: tabDomain,
                title: "Personal Identification",
                rtfData: created.rtfData,
                deleted: 0,
                pinned: 1,
                favorited: 0,
                noteTypeRaw: NJNoteType.card.rawValue,
                dominanceModeRaw: created.dominanceModeRaw,
                isChecklist: created.isChecklist,
                cardID: "DB-PERSONAL-ID",
                cardCategory: "Database",
                cardArea: "Database",
                cardContext: "Personal Identification",
                cardStatus: "Active",
                cardPriority: "High"
            )
        }
        notes.upsertNote(note)
    }

    private func runMeCommonInformationCleanupV1() {
        let repairKey = "nj_me_common_information_cleanup_done_v1"
        if UserDefaults.standard.bool(forKey: repairKey) { return }

        let oldTabRows = db.queryRows("""
        SELECT tab_id, notebook_id, domain_key
        FROM nj_tab
        WHERE lower(notebook_id) IN ('me', 'self')
          AND lower(title) IN ('relationship', 'relationships', 'marriage')
          AND deleted = 0;
        """)

        let oldDomains = Set(
            oldTabRows.compactMap { $0["domain_key"] }
                + ["me.rel", "me.relationship", "self.marriage", "self.relationship"]
        )

        if !oldDomains.isEmpty {
            let targetDomain = preferredMeReflectionDomain()
            let quotedOldDomains = oldDomains.map(sqlQuote).joined(separator: ", ")
            let movedNoteRows = db.queryRows("""
            SELECT note_id
            FROM nj_note
            WHERE deleted = 0
              AND lower(notebook) IN ('me', 'self')
              AND tab_domain IN (\(quotedOldDomains));
            """)

            if !movedNoteRows.isEmpty {
                let now = DBNoteRepository.nowMs()
                db.exec("""
                UPDATE nj_note
                SET tab_domain = \(sqlQuote(targetDomain)),
                    updated_at_ms = \(now)
                WHERE deleted = 0
                  AND lower(notebook) IN ('me', 'self')
                  AND tab_domain IN (\(quotedOldDomains));
                """)
                for row in movedNoteRows {
                    if let noteID = row["note_id"], !noteID.isEmpty {
                        notes.enqueueDirty(entity: "note", entityID: noteID, op: "upsert", updatedAtMs: now)
                    }
                }
            }
        }

        let now = DBNoteRepository.nowMs()
        for row in oldTabRows {
            guard let tabID = row["tab_id"], let notebookID = row["notebook_id"] else { continue }
            let commonDomain = notebookID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ME"
                ? "me.database"
                : "self.database"
            db.exec("""
            UPDATE nj_tab
            SET title = 'Database',
                domain_key = \(sqlQuote(commonDomain)),
                updated_at_ms = \(now)
            WHERE tab_id = \(sqlQuote(tabID));
            """)
            notes.enqueueDirty(entity: "tab", entityID: tabID, op: "upsert", updatedAtMs: now)
        }

        UserDefaults.standard.set(true, forKey: repairKey)
    }

    private func runMeDatabaseCleanupV2() {
        let repairKey = "nj_me_database_cleanup_done_v2"
        if UserDefaults.standard.bool(forKey: repairKey) { return }

        let targetRows = db.queryRows("""
        SELECT tab_id, notebook_id, domain_key
        FROM nj_tab
        WHERE lower(notebook_id) IN ('me', 'self')
          AND lower(title) IN ('relationship', 'relationships', 'marriage', 'common information', 'database')
          AND deleted = 0;
        """)

        let sourceDomains = Set(
            targetRows.compactMap { $0["domain_key"] }
                + ["me.rel", "me.relationship", "me.common", "self.marriage", "self.relationship", "self.common"]
        )

        if !sourceDomains.isEmpty {
            let quotedSourceDomains = sourceDomains.map(sqlQuote).joined(separator: ", ")
            let targetDomain = preferredMeReflectionDomain()
            let movedNoteRows = db.queryRows("""
            SELECT note_id
            FROM nj_note
            WHERE deleted = 0
              AND lower(notebook) IN ('me', 'self')
              AND tab_domain IN (\(quotedSourceDomains));
            """)

            if !movedNoteRows.isEmpty {
                let now = DBNoteRepository.nowMs()
                db.exec("""
                UPDATE nj_note
                SET tab_domain = \(sqlQuote(targetDomain)),
                    updated_at_ms = \(now)
                WHERE deleted = 0
                  AND lower(notebook) IN ('me', 'self')
                  AND tab_domain IN (\(quotedSourceDomains));
                """)
                for row in movedNoteRows {
                    if let noteID = row["note_id"], !noteID.isEmpty {
                        notes.enqueueDirty(entity: "note", entityID: noteID, op: "upsert", updatedAtMs: now)
                    }
                }
            }
        }

        let now = DBNoteRepository.nowMs()
        for row in targetRows {
            guard let tabID = row["tab_id"], let notebookID = row["notebook_id"] else { continue }
            let databaseDomain = notebookID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ME"
                ? "me.database"
                : "self.database"
            db.exec("""
            UPDATE nj_tab
            SET title = 'Database',
                domain_key = \(sqlQuote(databaseDomain)),
                updated_at_ms = \(now)
            WHERE tab_id = \(sqlQuote(tabID));
            """)
            notes.enqueueDirty(entity: "tab", entityID: tabID, op: "upsert", updatedAtMs: now)
        }

        db.exec("""
        UPDATE nj_card_schema
        SET category = 'Database',
            updated_at_ms = \(now)
        WHERE schema_key = \(sqlQuote(DBCardTable.personalIdentificationSchemaKey));
        """)

        db.exec("""
        UPDATE nj_card
        SET area = 'Database',
            updated_at_ms = \(now)
        WHERE schema_key = \(sqlQuote(DBCardTable.personalIdentificationSchemaKey));
        """)

        notes.enqueueDirty(entity: "card_schema", entityID: DBCardTable.personalIdentificationSchemaKey, op: "upsert", updatedAtMs: now)
        for row in db.queryRows("SELECT card_id FROM nj_card WHERE schema_key = \(sqlQuote(DBCardTable.personalIdentificationSchemaKey));") {
            if let cardID = row["card_id"], !cardID.isEmpty {
                notes.enqueueDirty(entity: "card", entityID: cardID, op: "upsert", updatedAtMs: now)
            }
        }

        UserDefaults.standard.set(true, forKey: repairKey)
        sync.schedulePush(debounceMs: 0)
    }

    private func runMeDatabaseCleanupV3() {
        let repairKey = "nj_me_database_cleanup_done_v3"
        if UserDefaults.standard.bool(forKey: repairKey) { return }

        let targetRows = db.queryRows("""
        SELECT t.tab_id, t.notebook_id, t.domain_key
        FROM nj_tab t
        LEFT JOIN nj_notebook n ON n.notebook_id = t.notebook_id
        WHERE (
            lower(t.notebook_id) IN ('me', 'self')
            OR lower(n.title) IN ('me', 'self')
        )
          AND lower(t.title) IN ('relationship', 'relationships', 'marriage', 'common information', 'database')
          AND t.deleted = 0;
        """)

        let sourceDomains = Set(
            targetRows.compactMap { $0["domain_key"] }
                + ["me.rel", "me.relationship", "me.common", "self.marriage", "self.relationship", "self.common"]
        )

        let targetNotebookValues = db.queryRows("""
        SELECT notebook_id AS value FROM nj_notebook WHERE lower(title) IN ('me', 'self')
        UNION
        SELECT title AS value FROM nj_notebook WHERE lower(title) IN ('me', 'self')
        UNION
        SELECT 'Me' AS value
        UNION
        SELECT 'Self' AS value
        UNION
        SELECT 'ME' AS value
        UNION
        SELECT 'self' AS value;
        """)
        let notebookValues = Set(targetNotebookValues.compactMap { $0["value"] }.filter { !$0.isEmpty })

        if !sourceDomains.isEmpty, !notebookValues.isEmpty {
            let quotedSourceDomains = sourceDomains.map(sqlQuote).joined(separator: ", ")
            let quotedNotebookValues = notebookValues.map(sqlQuote).joined(separator: ", ")
            let targetDomain = preferredMeReflectionDomain()
            let movedNoteRows = db.queryRows("""
            SELECT note_id
            FROM nj_note
            WHERE deleted = 0
              AND notebook IN (\(quotedNotebookValues))
              AND tab_domain IN (\(quotedSourceDomains));
            """)

            if !movedNoteRows.isEmpty {
                let now = DBNoteRepository.nowMs()
                db.exec("""
                UPDATE nj_note
                SET tab_domain = \(sqlQuote(targetDomain)),
                    updated_at_ms = \(now)
                WHERE deleted = 0
                  AND notebook IN (\(quotedNotebookValues))
                  AND tab_domain IN (\(quotedSourceDomains));
                """)
                for row in movedNoteRows {
                    if let noteID = row["note_id"], !noteID.isEmpty {
                        notes.enqueueDirty(entity: "note", entityID: noteID, op: "upsert", updatedAtMs: now)
                    }
                }
            }
        }

        let now = DBNoteRepository.nowMs()
        for row in targetRows {
            guard let tabID = row["tab_id"], let notebookID = row["notebook_id"] else { continue }
            let title = db.queryRows("SELECT title FROM nj_notebook WHERE notebook_id = \(sqlQuote(notebookID)) LIMIT 1;")
                .first?["title"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() ?? ""
            let databaseDomain = title == "me" || notebookID.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() == "ME"
                ? "me.database"
                : "self.database"
            db.exec("""
            UPDATE nj_tab
            SET title = 'Database',
                domain_key = \(sqlQuote(databaseDomain)),
                updated_at_ms = \(now)
            WHERE tab_id = \(sqlQuote(tabID));
            """)
            notes.enqueueDirty(entity: "tab", entityID: tabID, op: "upsert", updatedAtMs: now)
        }

        UserDefaults.standard.set(true, forKey: repairKey)
        if !targetRows.isEmpty {
            reloadNotebooksTabsFromDB()
            sync.schedulePush(debounceMs: 0)
        }
    }

    private func preferredMeReflectionDomain() -> String {
        let candidates = db.queryRows("""
        SELECT t.domain_key, t.title
        FROM nj_tab t
        LEFT JOIN nj_notebook n ON n.notebook_id = t.notebook_id
        WHERE (
            lower(t.notebook_id) IN ('me', 'self')
            OR lower(n.title) IN ('me', 'self')
        )
          AND t.deleted = 0
        ORDER BY t.ord ASC, t.updated_at_ms DESC;
        """)

        let planner = candidates.first {
            ($0["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "planner"
        }?["domain_key"]
        if let planner, !planner.isEmpty { return planner }

        let reflection = candidates.first {
            let title = ($0["title"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let domain = ($0["domain_key"] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return title == "reflection" || domain == "me.mind" || domain == "self.reflection"
        }?["domain_key"]
        if let reflection, !reflection.isEmpty { return reflection }

        return "me.mind"
    }

    private func sqlQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func renewalRegistrySeedV1() -> [(id: String, personName: String, documentName: String, documentType: String, jurisdiction: String, documentNumberHint: String, expiryDateKey: String, notes: String)] {
        [
            ("renewal.dad.hk-passport", "Dad", "HK Passport", "passport", "HK", "", "2035-08-30", ""),
            ("renewal.zz.hk-passport", "Zhou Zhou", "HK Passport", "passport", "HK", "", "2028-03-22", ""),
            ("renewal.dad.china-driver-license", "Dad", "China Driver License", "driver_license", "China", "", "2037-12-20", ""),
            ("renewal.zz.hkid", "Zhou Zhou", "HKID", "identity_card", "HK", "", "", "Expiry date not provided yet."),
            ("renewal.zz.home-return-permit", "Zhou Zhou", "回鄉証", "travel_permit", "China", "", "2028-05-10", ""),
            ("renewal.zz.re-entry-permit", "Zhou Zhou", "回港証", "travel_permit", "HK", "", "2028-03-20", ""),
            ("renewal.dad.home-return-permit", "Dad", "回鄉証", "travel_permit", "China", "", "2029-08-25", ""),
            ("renewal.dad.hk-driver-license", "Dad", "HK Driver License", "driver_license", "HK", "", "2030-11-23", ""),
            ("renewal.mm.home-return-permit", "Mushy Mushy", "回鄉証", "travel_permit", "China", "", "2029-04-06", ""),
            ("renewal.mm.hk-passport", "Mushy Mushy", "HK Passport", "passport", "HK", "H24426771", "2031-04-11", ""),
            ("renewal.mm.us-passport", "Mushy Mushy", "US Passport", "passport", "US", "", "2029-04-28", ""),
            ("renewal.zz.us-passport", "Zhou Zhou", "US Passport", "passport", "US", "", "2023-08-14", "Already expired before seed date; needs review."),
            ("renewal.dad.us-passport", "Dad", "US Passport", "passport", "US", "", "2026-07-06", "")
        ]
    }

    private func renewalStatus(for expiryDateKey: String) -> String {
        guard let expiryDate = renewalDate(from: expiryDateKey) else { return "missing_date" }
        let today = Calendar.current.startOfDay(for: Date())
        if expiryDate < today { return "expired" }
        let days = Calendar.current.dateComponents([.day], from: today, to: expiryDate).day ?? Int.max
        if days <= 90 { return "due_soon" }
        return "active"
    }

    private func renewalPriority(for expiryDateKey: String) -> String {
        guard let expiryDate = renewalDate(from: expiryDateKey) else { return "review" }
        let today = Calendar.current.startOfDay(for: Date())
        if expiryDate < today { return "critical" }
        let days = Calendar.current.dateComponents([.day], from: today, to: expiryDate).day ?? Int.max
        if days <= 30 { return "critical" }
        if days <= 90 { return "high" }
        if days <= 365 { return "medium" }
        return "low"
    }

    private func reminderOffsetsJSON(for documentType: String) -> String {
        switch documentType {
        case "passport", "travel_permit", "identity_card":
            return "[365,180,90,30,7,1,0]"
        case "driver_license":
            return "[180,90,30,7,1,0]"
        default:
            return "[90,30,7,1,0]"
        }
    }

    private func renewalDate(from dateKey: String) -> Date? {
        let trimmed = dateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: trimmed)
    }

    func createQuickNoteToClipboard(payloadJSON: String, createdAtMs: Int64? = nil, tags: [String] = []) {
        guard notes.createQuickNoteBlock(payloadJSON: payloadJSON, createdAtMs: createdAtMs, tags: tags) != nil else { return }
        refreshQuickClipboardCount()
        sync.schedulePush(debounceMs: 0)
        scheduleGoalJournalWidgetRefresh(delayMs: 150)
    }

    @discardableResult
    func createFutureWeeklyCalendarNote(for date: Date) -> String? {
        createFutureWeeklyCalendarBlock(for: date, reveal: true, scheduleSync: true)
    }

    @discardableResult
    private func createFutureWeeklyCalendarBlock(for date: Date, reveal: Bool, scheduleSync: Bool) -> String? {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)
        guard day > calendar.startOfDay(for: Date()) else { return nil }

        let createdAt = Int64(((calendar.date(byAdding: .hour, value: 12, to: day) ?? day).timeIntervalSince1970 * 1000.0).rounded())

        if let blockID = existingWeeklyCalendarBlockID(on: day, calendar: calendar) {
            if reveal {
                selectedModule = .note
            }
            return blockID
        }

        let body = futureWeeklyDailyTitle(for: day, calendar: calendar)
        let payloadJSON = NJQuickNotePayload.makePayloadJSON(from: body)
        guard let blockID = notes.createQuickNoteBlock(payloadJSON: payloadJSON, createdAtMs: createdAt, tags: ["#WEEKLY"], blockType: "text") else { return nil }
        _ = attachWeeklyBlockToHiddenOwnerNote(blockID: blockID, createdAtMs: createdAt)

        if reveal {
            selectedModule = .note
        }
        if scheduleSync {
            sync.schedulePush(debounceMs: 0)
            scheduleGoalJournalWidgetRefresh(delayMs: 150)
        }
        return blockID
    }

    private func ensureRollingFutureWeeklyCalendarNotes(daysAhead: Int = 30) {
        let cleaned = cleanupCurrentWeekFutureWeeklyScaffoldPlaceholdersIfNeeded()
        let repaired = repairMisfiledFutureWeeklyScaffoldNotesIfNeeded()
        let defaultsKey = "nj_future_weekly_calendar_notes_rolling_last_day_v1"
        let todayKey = DBNoteRepository.dateKey(Date())
        if UserDefaults.standard.string(forKey: defaultsKey) == todayKey {
            if cleaned > 0 || repaired > 0 {
                reloadNotebooksTabsFromDB()
                sync.schedulePush(debounceMs: 0)
                scheduleGoalJournalWidgetRefresh(delayMs: 150)
            }
            return
        }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let scaffoldStart = nextWeeklyScaffoldStart(after: today, calendar: calendar)
        var created = 0
        for offset in 0..<max(1, daysAhead) {
            guard let day = calendar.date(byAdding: .day, value: offset, to: scaffoldStart) else { continue }
            let beforeCount = notes.localCount(entity: "block")
            if createFutureWeeklyCalendarBlock(for: day, reveal: false, scheduleSync: false) != nil,
               notes.localCount(entity: "block") > beforeCount {
                created += 1
            }
        }

        UserDefaults.standard.set(todayKey, forKey: defaultsKey)
        if created > 0 || cleaned > 0 || repaired > 0 {
            reloadNotebooksTabsFromDB()
            sync.schedulePush(debounceMs: 0)
            scheduleGoalJournalWidgetRefresh(delayMs: 150)
            print("NJ_FUTURE_WEEKLY_BLOCKS_ROLLING created=\(created) cleaned=\(cleaned) repaired=\(repaired) start=\(DBNoteRepository.dateKey(scaffoldStart)) days_ahead=\(daysAhead)")
        }
    }

    @discardableResult
    private func repairOrphanWeeklyCalendarNoteLinks(limit: Int = 500) -> Int {
        let rows = db.queryRows("""
        SELECT b.block_id, b.created_at_ms, b.updated_at_ms
        FROM nj_block b
        WHERE b.deleted = 0
          AND EXISTS (
            SELECT 1
            FROM nj_block_tag t
            WHERE t.block_id = b.block_id
              AND t.tag = '#WEEKLY' COLLATE NOCASE
          )
          AND NOT EXISTS (
            SELECT 1
            FROM nj_note_block nb
            WHERE nb.block_id = b.block_id
              AND nb.deleted = 0
          )
        ORDER BY b.created_at_ms ASC
        LIMIT \(max(1, limit));
        """)

        guard !rows.isEmpty else { return 0 }

        var repaired = 0
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current

        for row in rows {
            let blockID = row["block_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !blockID.isEmpty else { continue }
            let createdAtMs = Int64(row["created_at_ms"] ?? "") ?? 0
            guard createdAtMs > 0 else { continue }

            let blockDate = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
            let day = calendar.startOfDay(for: blockDate)
            let dayKey = DBNoteRepository.dateKey(day).replacingOccurrences(of: "-", with: "")
            let year = calendar.component(.year, from: day)
            let nowMs = DBNoteRepository.nowMs()

            guard let noteID = weeklyOwnerNoteID(day: day, dayKey: dayKey, year: year, nowMs: nowMs) else {
                continue
            }

            let instanceID = UUID().uuidString.uppercased()
            let orderKey = nextOrderKey(for: noteID)
            guard insertWeeklyNoteBlockLink(
                instanceID: instanceID,
                noteID: noteID,
                blockID: blockID,
                orderKey: orderKey,
                createdAtMs: createdAtMs,
                updatedAtMs: nowMs
            ) else {
                continue
            }

            touchNote(noteID: noteID, updatedAtMs: nowMs)
            notes.enqueueDirty(entity: "note", entityID: noteID, op: "upsert", updatedAtMs: nowMs)
            notes.enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: nowMs)
            notes.updateBlockPayloadJSON(
                blockID: blockID,
                payloadJSON: notes.loadBlockPayloadJSON(blockID: blockID),
                updatedAtMs: nowMs
            )
            repaired += 1
        }

        if repaired > 0 {
            print("NJ_WEEKLY_ORPHAN_NOTE_REPAIR repaired=\(repaired)")
        }
        return repaired
    }

    private func weeklyOwnerNoteID(day: Date, dayKey: String, year: Int, nowMs: Int64) -> String? {
        let existing = existingHiddenWeeklyNoteID(dayKey: dayKey)
        if !existing.isEmpty { return existing }

        let noteID = UUID().uuidString.lowercased()
        let title = "(\(dayKey)) Weekly Sync"
        let tabDomain = "_system.weekly"
        let createdAtMs = Int64((day.timeIntervalSince1970 * 1000.0).rounded())

        let ok = db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_note(
              note_id, created_at_ms, updated_at_ms,
              notebook, tab_domain, title, note_type, dominance_mode, is_checklist,
              card_id, card_category, card_area, card_context, card_status, card_priority,
              pinned, favorited, pinned_updated_at_ms, favorited_updated_at_ms, deleted
            )
            VALUES(?, ?, ?, '_SYSTEM', ?, ?, 'note', 'block', 0, '', '', '', '', '', '', 0, 0, 0, 0, 0);
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                db.dbgErr(dbp, "weeklyOwnerNoteID.insert.prepare", rc0)
                return false
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64(stmt, 2, createdAtMs)
            sqlite3_bind_int64(stmt, 3, nowMs)
            sqlite3_bind_text(stmt, 4, tabDomain, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 5, title, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE {
                db.dbgErr(dbp, "weeklyOwnerNoteID.insert.step", rc1)
                return false
            }
            return true
        }

        return ok ? noteID : nil
    }

    private func existingHiddenWeeklyNoteID(dayKey: String) -> String {
        let escaped = dayKey.replacingOccurrences(of: "'", with: "''")
        let rows = db.queryRows("""
        SELECT note_id
        FROM nj_note
        WHERE deleted = 0
          AND title LIKE '(\(escaped))%'
          AND notebook = '_SYSTEM'
          AND tab_domain = '_system.weekly'
        ORDER BY created_at_ms ASC
        LIMIT 1;
        """)
        return rows.first?["note_id"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    @discardableResult
    private func attachWeeklyBlockToHiddenOwnerNote(blockID: String, createdAtMs: Int64) -> Bool {
        guard createdAtMs > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let blockDate = Date(timeIntervalSince1970: Double(createdAtMs) / 1000.0)
        let day = calendar.startOfDay(for: blockDate)
        let dayKey = DBNoteRepository.dateKey(day).replacingOccurrences(of: "-", with: "")
        let year = calendar.component(.year, from: day)
        let nowMs = DBNoteRepository.nowMs()

        if hasLiveNoteBlockLink(blockID: blockID) { return true }
        guard let noteID = weeklyOwnerNoteID(day: day, dayKey: dayKey, year: year, nowMs: nowMs) else {
            return false
        }

        let instanceID = UUID().uuidString.uppercased()
        guard insertWeeklyNoteBlockLink(
            instanceID: instanceID,
            noteID: noteID,
            blockID: blockID,
            orderKey: nextOrderKey(for: noteID),
            createdAtMs: createdAtMs,
            updatedAtMs: nowMs
        ) else {
            return false
        }

        touchNote(noteID: noteID, updatedAtMs: nowMs)
        notes.enqueueDirty(entity: "note", entityID: noteID, op: "upsert", updatedAtMs: nowMs)
        notes.enqueueDirty(entity: "note_block", entityID: instanceID, op: "upsert", updatedAtMs: nowMs)
        return true
    }

    private func hasLiveNoteBlockLink(blockID: String) -> Bool {
        let escaped = blockID.replacingOccurrences(of: "'", with: "''")
        let rows = db.queryRows("""
        SELECT instance_id
        FROM nj_note_block
        WHERE block_id = '\(escaped)'
          AND deleted = 0
        LIMIT 1;
        """)
        return !(rows.first?["instance_id"] ?? "").isEmpty
    }

    private func nextOrderKey(for noteID: String) -> Double {
        let escaped = noteID.replacingOccurrences(of: "'", with: "''")
        let rows = db.queryRows("""
        SELECT COALESCE(MAX(order_key), 0) AS max_order
        FROM nj_note_block
        WHERE note_id = '\(escaped)'
          AND deleted = 0;
        """)
        let maxOrder = Double(rows.first?["max_order"] ?? "") ?? 0
        return max(1000, maxOrder + 1000)
    }

    private func insertWeeklyNoteBlockLink(
        instanceID: String,
        noteID: String,
        blockID: String,
        orderKey: Double,
        createdAtMs: Int64,
        updatedAtMs: Int64
    ) -> Bool {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            INSERT INTO nj_note_block(
              instance_id, note_id, block_id, order_key, is_checked,
              card_row_id, card_status, card_priority, card_category, card_area, card_context, card_title,
              view_state_json, created_at_ms, updated_at_ms, deleted
            )
            VALUES(?, ?, ?, ?, 0, '', '', '', '', '', '', '', '', ?, ?, 0)
            ON CONFLICT(instance_id) DO NOTHING;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                db.dbgErr(dbp, "insertWeeklyNoteBlockLink.prepare", rc0)
                return false
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, instanceID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 2, noteID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_text(stmt, 3, blockID, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 4, orderKey)
            sqlite3_bind_int64(stmt, 5, createdAtMs)
            sqlite3_bind_int64(stmt, 6, updatedAtMs)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE {
                db.dbgErr(dbp, "insertWeeklyNoteBlockLink.step", rc1)
                return false
            }
            return sqlite3_changes(dbp) > 0
        }
    }

    private func touchNote(noteID: String, updatedAtMs: Int64) {
        db.withDB { dbp in
            var stmt: OpaquePointer?
            let rc0 = sqlite3_prepare_v2(dbp, """
            UPDATE nj_note
            SET updated_at_ms = ?, deleted = 0
            WHERE note_id = ?;
            """, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                db.dbgErr(dbp, "touchNote.prepare", rc0)
                return
            }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_int64(stmt, 1, updatedAtMs)
            sqlite3_bind_text(stmt, 2, noteID, -1, SQLITE_TRANSIENT)
            let rc1 = sqlite3_step(stmt)
            if rc1 != SQLITE_DONE {
                db.dbgErr(dbp, "touchNote.step", rc1)
            }
        }
    }

    private func existingWeeklyCalendarBlockID(on day: Date, calendar: Calendar) -> String? {
        let startMs = Int64((day.timeIntervalSince1970 * 1000.0).rounded())
        let endDay = calendar.date(byAdding: .day, value: 1, to: day) ?? day
        let endMs = Int64((endDay.timeIntervalSince1970 * 1000.0).rounded())
        let rows = db.queryRows("""
        SELECT b.block_id, b.payload_json, b.tag_json
        FROM nj_block b
        WHERE b.deleted = 0
          AND b.created_at_ms >= \(startMs)
          AND b.created_at_ms < \(endMs)
        ORDER BY b.updated_at_ms DESC
        LIMIT 300;
        """)

        for row in rows {
            guard let blockID = row["block_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !blockID.isEmpty
            else { continue }

            let tagJSON = (row["tag_json"] ?? "").lowercased()
            let payloadText = NJQuickNotePayload.plainText(from: row["payload_json"] ?? "")
            let lines = weeklyScaffoldLines(from: payloadText)
            if lines.first.map(isFutureWeeklyDailyTitle) == true {
                return blockID
            }
        }
        return nil
    }

    private func cleanupCurrentWeekFutureWeeklyScaffoldPlaceholdersIfNeeded() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDay = calendar.date(byAdding: .day, value: 60, to: today) ?? today
        let startMs = Int64((today.timeIntervalSince1970 * 1000.0).rounded())
        let endMs = Int64((endDay.timeIntervalSince1970 * 1000.0).rounded())
        let rows = db.queryRows("""
        SELECT date(b.created_at_ms / 1000, 'unixepoch', 'localtime') AS day_key,
               n.note_id, n.title, n.updated_at_ms, n.deleted AS note_deleted,
               nb.instance_id, nb.block_id, nb.deleted AS note_block_deleted,
               b.updated_at_ms AS block_updated_at_ms,
               b.payload_json, b.tag_json
        FROM nj_note n
        JOIN nj_note_block nb ON nb.note_id = n.note_id
        JOIN nj_block b ON b.block_id = nb.block_id AND b.deleted = 0
        WHERE n.created_at_ms >= \(startMs)
          AND n.created_at_ms < \(endMs)
        ORDER BY n.created_at_ms ASC, nb.order_key ASC;
        """)

        var weeklyCountByDay: [String: Int] = [:]
        var scaffoldCountByDay: [String: Int] = [:]
        var byNote: [String: [(dayKey: String, updatedAtMs: Int64, blockUpdatedAtMs: Int64, instanceID: String, blockID: String, title: String, payloadJSON: String, tagJSON: String)]] = [:]
        var cleaned = 0
        let now = DBNoteRepository.nowMs()
        for row in rows {
            guard let noteID = row["note_id"], !noteID.isEmpty else { continue }
            let dayKey = row["day_key"] ?? ""
            let title = row["title"] ?? ""
            let payloadJSON = row["payload_json"] ?? ""
            let tagJSON = row["tag_json"] ?? ""
            let isScaffold = isDateKeyTitle(title) && isBlankWeeklyScaffoldPayload(payloadJSON, tagJSON: tagJSON)
            let noteDeleted = (Int(row["note_deleted"] ?? "") ?? 0) != 0
            let noteBlockDeleted = (Int(row["note_block_deleted"] ?? "") ?? 0) != 0
            let instanceID = row["instance_id"] ?? ""
            let blockID = row["block_id"] ?? ""
            let deletionMs = max(now, (Int64(row["block_updated_at_ms"] ?? "") ?? now) + 1)

            if isScaffold, noteDeleted || noteBlockDeleted {
                if !instanceID.isEmpty {
                    notes.markNoteBlockDeleted(instanceID: instanceID, nowMs: deletionMs)
                }
                notes.markNoteDeleted(noteID: noteID, nowMs: deletionMs)
                cleaned += 1
                continue
            }

            weeklyCountByDay[dayKey, default: 0] += 1
            if isScaffold {
                scaffoldCountByDay[dayKey, default: 0] += 1
            }
            byNote[noteID, default: []].append((
                dayKey: dayKey,
                updatedAtMs: Int64(row["updated_at_ms"] ?? "") ?? 0,
                blockUpdatedAtMs: Int64(row["block_updated_at_ms"] ?? "") ?? 0,
                instanceID: instanceID,
                blockID: blockID,
                title: title,
                payloadJSON: payloadJSON,
                tagJSON: tagJSON
            ))
        }

        var scaffoldNotesByDay: [String: [(noteID: String, updatedAtMs: Int64, blocks: [(dayKey: String, updatedAtMs: Int64, blockUpdatedAtMs: Int64, instanceID: String, blockID: String, title: String, payloadJSON: String, tagJSON: String)])]] = [:]
        for (noteID, blocks) in byNote {
            guard let only = blocks.first,
                  isDateKeyTitle(only.title),
                  blocks.allSatisfy({ isBlankWeeklyScaffoldPayload($0.payloadJSON, tagJSON: $0.tagJSON) }),
                  isBlankWeeklyScaffoldPayload(only.payloadJSON, tagJSON: only.tagJSON)
            else { continue }
            scaffoldNotesByDay[only.dayKey, default: []].append((noteID: noteID, updatedAtMs: only.updatedAtMs, blocks: blocks))
        }

        for (dayKey, scaffoldNotes) in scaffoldNotesByDay {
            let weeklyCount = weeklyCountByDay[dayKey, default: 0]
            let scaffoldCount = scaffoldCountByDay[dayKey, default: 0]
            guard weeklyCount > 1 || scaffoldCount > 1 else { continue }

            let hasNonScaffoldWeekly = weeklyCount > scaffoldCount
            let keepNoteID: String? = hasNonScaffoldWeekly
                ? nil
                : scaffoldNotes.max(by: { $0.updatedAtMs < $1.updatedAtMs })?.noteID

            for scaffoldNote in scaffoldNotes where scaffoldNote.noteID != keepNoteID {
                var noteDeletionMs = now
                for block in scaffoldNote.blocks {
                    let deletionMs = max(now, block.blockUpdatedAtMs + 1)
                    noteDeletionMs = max(noteDeletionMs, deletionMs)
                    if !block.instanceID.isEmpty {
                        notes.markNoteBlockDeleted(instanceID: block.instanceID, nowMs: deletionMs)
                    }
                }
                notes.markNoteDeleted(noteID: scaffoldNote.noteID, nowMs: noteDeletionMs)
                cleaned += 1
            }
        }

        if cleaned > 0 {
            print("NJ_FUTURE_WEEKLY_SCAFFOLD_CLEANUP cleaned=\(cleaned)")
        }
        return cleaned
    }

    private func repairMisfiledFutureWeeklyScaffoldNotesIfNeeded() -> Int {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let endDay = calendar.date(byAdding: .day, value: 120, to: today) ?? today
        let startMs = Int64((today.timeIntervalSince1970 * 1000.0).rounded())
        let endMs = Int64((endDay.timeIntervalSince1970 * 1000.0).rounded())
        let rows = db.queryRows("""
        SELECT n.note_id, n.title, n.updated_at_ms, nb.order_key,
               b.block_id, b.domain_tag, b.payload_json, b.tag_json
        FROM nj_note n
        JOIN nj_note_block nb ON nb.note_id = n.note_id AND nb.deleted = 0
        JOIN nj_block b ON b.block_id = nb.block_id AND b.deleted = 0
        WHERE n.deleted = 0
          AND n.created_at_ms >= \(startMs)
          AND n.created_at_ms < \(endMs)
          AND (
            lower(n.tab_domain) = 'me.finance'
            OR lower(n.tab_domain) = 'self.finance'
            OR lower(n.tab_domain) LIKE '%.finance'
            OR lower(n.tab_domain) = 'me.database'
            OR lower(n.tab_domain) = 'self.database'
            OR lower(b.domain_tag) = 'me.finance'
            OR lower(b.domain_tag) = 'self.finance'
            OR EXISTS (
              SELECT 1
              FROM nj_block_tag t
              WHERE t.block_id = b.block_id
                AND lower(t.tag) IN ('me.finance', 'self.finance')
            )
          )
        ORDER BY n.note_id ASC, nb.order_key ASC;
        """)

        var byNote: [String: [(title: String, updatedAtMs: Int64, blockID: String, domainTag: String, payloadJSON: String, tagJSON: String)]] = [:]
        for row in rows {
            guard let noteID = row["note_id"]?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !noteID.isEmpty
            else { continue }
            byNote[noteID, default: []].append((
                title: row["title"] ?? "",
                updatedAtMs: Int64(row["updated_at_ms"] ?? "") ?? 0,
                blockID: row["block_id"] ?? "",
                domainTag: row["domain_tag"] ?? "",
                payloadJSON: row["payload_json"] ?? "",
                tagJSON: row["tag_json"] ?? ""
            ))
        }

        let now = DBNoteRepository.nowMs()
        var repaired = 0
        for (noteID, blocks) in byNote {
            guard let first = blocks.first,
                  isDateKeyTitle(first.title),
                  blocks.allSatisfy({ isBlankWeeklyScaffoldPayload($0.payloadJSON, tagJSON: $0.tagJSON) }),
                  notes.getNote(NJNoteID(noteID)) != nil
            else { continue }

            let noteDeletionMs = max(now, first.updatedAtMs + 1)
            notes.markNoteDeleted(noteID: noteID, nowMs: noteDeletionMs)

            for block in blocks {
                let lowerDomainTag = block.domainTag.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                if let instanceID = db.queryRows("""
                SELECT instance_id
                FROM nj_note_block
                WHERE note_id = \(sqlQuote(noteID))
                  AND block_id = \(sqlQuote(block.blockID))
                LIMIT 1;
                """).first?["instance_id"], !instanceID.isEmpty {
                    notes.markNoteBlockDeleted(instanceID: instanceID, nowMs: noteDeletionMs)
                }

                guard !block.blockID.isEmpty else { continue }
                let hasFinanceDomainTag = lowerDomainTag == "me.finance" || lowerDomainTag == "self.finance"

                if hasFinanceDomainTag {
                    db.exec("""
                    UPDATE nj_block
                    SET domain_tag = '',
                        updated_at_ms = \(now),
                        dirty_bl = 1
                    WHERE block_id = \(sqlQuote(block.blockID));
                    """)
                    db.exec("""
                    DELETE FROM nj_block_tag
                    WHERE block_id = \(sqlQuote(block.blockID))
                      AND lower(tag) IN ('me.finance', 'self.finance');
                    """)
                }
                notes.enqueueDirty(entity: "block", entityID: block.blockID, op: "upsert", updatedAtMs: now)
            }
            repaired += 1
        }

        if repaired > 0 {
            print("NJ_FUTURE_WEEKLY_SCAFFOLD_REPAIR orphaned=\(repaired)")
        }
        return repaired
    }

    private func currentSundayWeekRange(containing date: Date, calendar: Calendar) -> (start: Date, end: Date) {
        var cal = calendar
        cal.firstWeekday = 1
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        let daysFromSunday = (weekday - cal.firstWeekday + 7) % 7
        let start = cal.date(byAdding: .day, value: -daysFromSunday, to: day) ?? day
        let end = cal.date(byAdding: .day, value: 7, to: start) ?? start
        return (start, end)
    }

    private func nextWeeklyScaffoldStart(after date: Date, calendar: Calendar) -> Date {
        let range = currentSundayWeekRange(containing: date, calendar: calendar)
        return range.end
    }

    private func isDateKeyTitle(_ title: String) -> Bool {
        let parts = title.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "-")
        guard parts.count == 3,
              parts[0].count == 4,
              parts[1].count == 2,
              parts[2].count == 2
        else { return false }
        return parts.allSatisfy { part in part.allSatisfy(\.isNumber) }
    }

    private func isBlankWeeklyScaffoldPayload(_ payloadJSON: String, tagJSON: String) -> Bool {
        let lowerTags = tagJSON.lowercased()
        guard lowerTags.contains("#weekly") else { return false }
        let lines = weeklyScaffoldLines(from: NJQuickNotePayload.plainText(from: payloadJSON))
        return lines.first.map(isFutureWeeklyDailyTitle) == true
    }

    private func weeklyScaffoldLines(from text: String) -> [String] {
        text
            .split(whereSeparator: { $0.isNewline })
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private func futureWeeklyDailyTitle(for date: Date, calendar: Calendar) -> String {
        let dayKey = DBNoteRepository.dateKey(date).replacingOccurrences(of: "-", with: "")
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "EEEE"
        return "(\(dayKey)) \(formatter.string(from: date)) - Daily"
    }

    private func isFutureWeeklyDailyTitle(_ line: String) -> Bool {
        let pattern = #"^\(\d{8}\) [A-Za-z]+ - Daily$"#
        return line.range(of: pattern, options: .regularExpression) != nil
    }

    private func formattedCalendarNoteDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateStyle = .full
        return formatter.string(from: date)
    }

    @MainActor
    func runInitialPullGate() async {
        if didFinishInitialPull { return }

        if sync.initialPullCompleted {
            reloadNotebooksTabsFromDB()
            ensureRollingFutureWeeklyCalendarNotes()
            repairFutureTimestampedAttachedBlocksAfterInitialPull()
            didFinishInitialPull = true
            return
        }

        for await v in sync.$initialPullCompleted.values {
            if v {
                reloadNotebooksTabsFromDB()
                ensureRollingFutureWeeklyCalendarNotes()
                repairFutureTimestampedAttachedBlocksAfterInitialPull()
                didFinishInitialPull = true
                break
            }
        }
    }

    private func repairFutureTimestampedAttachedBlocksAfterInitialPull() {
        let repaired = notes.repairFutureUpdatedAtAttachedBlocks(nowMs: DBNoteRepository.nowMs())
        guard repaired > 0 else { return }
        print("NJ_DIRTY_BACKFILL post_pull_future_block_timestamp_repair=\(repaired)")
        sync.schedulePush(debounceMs: 0)
    }

    
    @MainActor
    private var clipIngestRunning = false

    @MainActor
    private var audioIngestRunning = false

    @MainActor
    private var audioTranscribeRunning = false

    @MainActor
    private var timeInboxIngestRunning = false

    @MainActor
    func runClipIngestIfNeeded() {
        if clipIngestRunning { return }
        clipIngestRunning = true
        // print("NJ_CLIP_INGEST trigger")
        Task {
            await NJClipIngestor.ingestAll(store: self)
            await MainActor.run {
                self.clipIngestRunning = false
                // print("NJ_CLIP_INGEST done")
            }
        }
    }

    @MainActor
    func runAudioIngestIfNeeded() {
        if audioIngestRunning { return }
        audioIngestRunning = true
        // print("NJ_AUDIO_INGEST trigger")
        Task {
            await NJAudioIngestor.ingestAll(store: self)
            await MainActor.run {
                self.audioIngestRunning = false
                // print("NJ_AUDIO_INGEST done")
            }
        }
    }

    @MainActor
    func runAudioTranscribeIfNeeded() {
        if audioTranscribeRunning { return }
        audioTranscribeRunning = true
        // print("NJ_AUDIO_TRANSCRIBE trigger")
        Task {
            var totalProcessed = 0
            for _ in 0..<8 {
                let repaired = await NJAudioTranscriber.runRepairPass(store: self, limit: 12)
                let transcribed = await NJAudioTranscriber.runOnce(store: self, limit: 3)
                let roundTotal = repaired + transcribed
                totalProcessed += roundTotal
                if roundTotal == 0 { break }
            }
            await MainActor.run {
                self.audioTranscribeRunning = false
                // print("NJ_AUDIO_TRANSCRIBE done processed=\(totalProcessed)")
            }
        }
    }

    @MainActor
    func runTimeModuleInboxIngestIfNeeded() {
        if timeInboxIngestRunning { return }
        timeInboxIngestRunning = true
        defer { timeInboxIngestRunning = false }

        guard let shared = UserDefaults(suiteName: NJTimeSlotStore.appGroupID) else { return }
        let slotsKey = "nj_time_module_slots_v1"
        let goalsKey = "nj_time_module_goals_v1"

        var changed = false

        if let data = shared.data(forKey: slotsKey),
           let rows = try? JSONDecoder().decode([NJTimeSlot].self, from: data),
           !rows.isEmpty {
            for r in rows {
                let startMs = Int64(r.startDate.timeIntervalSince1970 * 1000.0)
                let endMs = Int64(r.endDate.timeIntervalSince1970 * 1000.0)
                let now = DBNoteRepository.nowMs()
                notes.upsertTimeSlot(
                    NJTimeSlotRecord(
                        timeSlotID: r.id,
                        ownerScope: "ME",
                        title: r.title,
                        category: r.category.rawValue.lowercased(),
                        startAtMs: startMs,
                        endAtMs: max(endMs, startMs + 15 * 60 * 1000),
                        notes: r.notes,
                        createdAtMs: startMs > 0 ? startMs : now,
                        updatedAtMs: now,
                        deleted: 0
                    )
                )
            }
            shared.removeObject(forKey: slotsKey)
            changed = true
        }

        if let data = shared.data(forKey: goalsKey),
           let rows = try? JSONDecoder().decode([NJPersonalGoal].self, from: data),
           !rows.isEmpty {
            for r in rows {
                let now = DBNoteRepository.nowMs()
                notes.upsertPersonalGoal(
                    NJPersonalGoalRecord(
                        goalID: r.id,
                        ownerScope: "ME",
                        title: r.title,
                        focus: r.focus.rawValue.lowercased(),
                        keyword: r.keyword,
                        weeklyTarget: Int64(max(1, r.weeklyTarget)),
                        status: "active",
                        createdAtMs: now,
                        updatedAtMs: now,
                        deleted: 0
                    )
                )
            }
            shared.removeObject(forKey: goalsKey)
            changed = true
        }

        if changed {
            publishTimeSlotWidgetSnapshot()
            syncTimeSlotOverrunNotifications()
            sync.schedulePush(debounceMs: 0)
        }
    }
    
    func reloadNotebooksTabsFromDB() {

        let loadedNotebooks: [NJNotebook] = notes.listNotebooks().map { row in
            let (id, title, colorHex, _, _, _) = row
            return NJNotebook(
                notebookID: id,
                title: title,
                colorHex: colorHex
            )
        }
        var seenNotebookTitles = Set<String>()
        let nbs = loadedNotebooks.filter { notebook in
            let key = notebook.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            return seenNotebookTitles.insert(key).inserted
        }

        var allTabs: [NJTab] = []

        for nb in nbs {
            let ts: [NJTab] = notes.listTabs(notebookID: nb.notebookID).map { row in
                let (tabID, notebookID, title, domainKey, colorHex, _, _, _, _) = row
                return NJTab(
                    tabID: tabID,
                    notebookID: notebookID,
                    title: title,
                    domainKey: domainKey,
                    colorHex: colorHex
                )
            }
            allTabs.append(contentsOf: ts)
        }

        notebooks = nbs
        tabs = allTabs

        if selectedNotebookID == nil, let first = notebooks.first {
            selectNotebook(first.notebookID)
        } else if let nb = selectedNotebookID,
                  !notebooks.contains(where: { $0.notebookID == nb }) {
            selectedNotebookID = nil
            selectedTabID = nil
            if let first = notebooks.first {
                selectNotebook(first.notebookID)
            }
        } else if let tab = selectedTabID,
                  !tabs.contains(where: { $0.tabID == tab }) {
            selectedTabID = tabsForSelectedNotebook.first?.tabID
        }

        // Keep derived block-tag index/domain up to date on any reload.
        NJLocalBLRunner(db: db).run(.deriveBlockTagIndexAndDomainV1)
        publishTrainingWeekSnapshotToWidget()
    }

    var currentNotebookTitle: String? {
        guard let id = selectedNotebookID else { return nil }
        return notebooks.first(where: { $0.notebookID == id })?.title
    }

    var currentTabDomain: String? {
        guard let id = selectedTabID else { return nil }
        return tabs.first(where: { $0.tabID == id })?.domainKey
    }

    var currentNotebookColorHex: String {
        guard let id = selectedNotebookID else { return "#64748B" }
        return notebooks.first(where: { $0.notebookID == id })?.colorHex ?? "#64748B"
    }

    var currentTabColorHex: String {
        guard let id = selectedTabID else { return "#64748B" }
        return tabs.first(where: { $0.tabID == id })?.colorHex ?? "#64748B"
    }

    var tabsForSelectedNotebook: [NJTab] {
        guard let nb = selectedNotebookID else { return [] }
        return tabs.filter { $0.notebookID == nb }
    }

    func selectNotebook(_ notebookID: String) {
        selectedNotebookID = notebookID
        if let first = tabsForSelectedNotebook.first {
            selectedTabID = first.tabID
        } else {
            selectedTabID = nil
        }
    }

    func selectTab(_ tabID: String) {
        selectedTabID = tabID
    }

    func addNotebook(title: String, colorHex: String) -> NJNotebook? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }

        let id = UUID().uuidString.lowercased()
        notes.upsertNotebook(
            notebookID: id,
            title: t,
            colorHex: colorHex,
            isArchived: 0
        )

        sync.schedulePush(debounceMs: 100)
        reloadNotebooksTabsFromDB()
        selectNotebook(id)
        return notebooks.first(where: { $0.notebookID == id })
    }

    func addTab(notebookID: String, title: String, domainKey: String, colorHex: String) -> NJTab? {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let d = domainKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, !d.isEmpty else { return nil }

        let id = UUID().uuidString.lowercased()
        let ord = Int64(tabsForSelectedNotebook.count)

        notes.upsertTab(
            tabID: id,
            notebookID: notebookID,
            title: t,
            domainKey: d,
            colorHex: colorHex,
            order: ord,
            isHidden: 0
        )

        sync.schedulePush(debounceMs: 100)
        reloadNotebooksTabsFromDB()
        selectedTabID = id
        return tabs.first(where: { $0.tabID == id })
    }

    func toggleDBDebug() {
        showDBDebugPanel.toggle()
    }

    func forcePullNow(forceSinceZero: Bool = true) {
        Task {
            await sync.forcePullNow(forceSinceZero: forceSinceZero)
            await MainActor.run {
                reloadNotebooksTabsFromDB()
                NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
            }
        }
    }

    func forceSyncNow() {
        Task {
            await sync.forceSyncNow()
            await MainActor.run {
                reloadNotebooksTabsFromDB()
                refreshQuickClipboardCount()
                NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
            }
        }
    }

    func syncOnAppActivationIfNeeded() {
        guard sync.initialPullCompleted else {
            // print("NJ_APP_ACTIVE_SYNC skip reason=initial_pull_not_completed")
            return
        }
        guard !appActivationSyncInFlight else {
            // print("NJ_APP_ACTIVE_SYNC skip reason=in_flight")
            return
        }

        let now = DBNoteRepository.nowMs()
        if lastAppActivationSyncAtMs > 0,
           now - lastAppActivationSyncAtMs < appActivationSyncDebounceMs {
            // print("NJ_APP_ACTIVE_SYNC skip reason=debounce elapsed_ms=\(now - lastAppActivationSyncAtMs)")
            return
        }
        lastAppActivationSyncAtMs = now
        appActivationSyncInFlight = true
        // print("NJ_APP_ACTIVE_SYNC start")

        Task { [weak self] in
            guard let self else { return }
            await sync.forceSyncNow()
            await MainActor.run {
                self.appActivationSyncInFlight = false
                // print("NJ_APP_ACTIVE_SYNC done")
                self.reloadNotebooksTabsFromDB()
                self.refreshQuickClipboardCount()
                NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
            }
        }
    }

    func recoverFromCloudNow() {
        Task {
            await MainActor.run {
                db.resetCloudKitCursors()
            }
            await sync.forcePullNow(forceSinceZero: true)
            await MainActor.run {
                reloadNotebooksTabsFromDB()
                refreshQuickClipboardCount()
                NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
            }
        }
    }

    func pullFinanceFromCloudNow() {
        Task {
            await MainActor.run {
                db.resetCloudKitCursors(entities: ["finance_transaction"])
            }
            await sync.forcePullNow(forceSinceZero: false)
            await MainActor.run {
                reloadNotebooksTabsFromDB()
                refreshQuickClipboardCount()
                NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
            }
        }
    }

    func recoverNotesAndCardsFromCloudNow() {
        Task {
            await MainActor.run {
                db.resetCloudKitCursors(entities: ["note", "block", "note_block", "attachment"])
            }
            await sync.forcePullNow(forceSinceZero: false)
            await MainActor.run {
                reloadNotebooksTabsFromDB()
                refreshQuickClipboardCount()
                NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
            }
        }
    }

    @discardableResult
    func repushBlocksToCloud(blockIDs: [String]) -> Int {
        let ids = Array(
            NSOrderedSet(
                array: blockIDs
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        ) as? [String] ?? []
        guard !ids.isEmpty else { return 0 }

        let now = DBNoteRepository.nowMs()
        var repushed = 0

        for blockID in ids {
            guard notes.hasBlock(blockID: blockID) else {
                print("NJ_BLOCK_REPUSH skip_missing_local blockID=\(blockID)")
                continue
            }
            let payloadJSON = notes.loadBlockPayloadJSON(blockID: blockID)
            guard !payloadJSON.isEmpty else {
                print("NJ_BLOCK_REPUSH skip_empty_payload blockID=\(blockID)")
                continue
            }
            notes.updateBlockPayloadJSON(blockID: blockID, payloadJSON: payloadJSON, updatedAtMs: now)
            repushed += 1
            print("NJ_BLOCK_REPUSH enqueued blockID=\(blockID) updated_at_ms=\(now)")
        }

        if repushed > 0 {
            sync.schedulePush(debounceMs: 0)
        }
        print("NJ_BLOCK_REPUSH done count=\(repushed)")
        return repushed
    }

    func movePendingBlock(toNoteID: String) -> Bool {
        guard let pending = pendingMoveBlock else { return false }
        if pending.blockID.isEmpty || pending.instanceID.isEmpty { return false }
        if pending.fromNoteID == toNoteID { return false }
        guard let targetNote = notes.getNote(NJNoteID(toNoteID)) else { return false }

        let now = DBNoteRepository.nowMs()

        notes.markNoteBlockDeleted(instanceID: pending.instanceID, nowMs: now)

        let orderKey = notes.nextAppendOrderKey(noteID: toNoteID)
        _ = notes.attachExistingBlockToNote(noteID: toNoteID, blockID: pending.blockID, orderKey: orderKey)

        let existingTagJSON = notes.loadBlockTagJSON(blockID: pending.blockID)
        let updatedTagJSON = mergeTagJSONForMove(
            tagJSON: existingTagJSON,
            removeTag: pending.fromNoteDomain,
            addTag: targetNote.tabDomain
        )
        notes.updateBlockTagJSON(blockID: pending.blockID, tagJSON: updatedTagJSON, nowMs: now)

        NJLocalBLRunner(db: db).run(.deriveBlockTagIndexAndDomainV1, limit: 2000)
        sync.schedulePush(debounceMs: 0)
        pendingMoveBlock = nil
        NotificationCenter.default.post(name: .njForceReloadNote, object: nil)
        scheduleGoalJournalWidgetRefresh(delayMs: 150)
        return true
    }

    private func mergeTagJSONForMove(tagJSON: String, removeTag: String, addTag: String) -> String {
        let decoded: [String] = {
            guard let data = tagJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()
        var merged = decoded
        let removeT = removeTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !removeT.isEmpty {
            merged.removeAll { $0.caseInsensitiveCompare(removeT) == .orderedSame }
        }
        let addT = addTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if !addT.isEmpty, !merged.contains(where: { $0.caseInsensitiveCompare(addT) == .orderedSame }) {
            merged.append(addT)
        }
        if let data = try? JSONSerialization.data(withJSONObject: merged),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return tagJSON
    }

    private func scheduleGoalJournalWidgetRefresh(delayMs: UInt64) {
        goalJournalSnapshotTask?.cancel()
        goalJournalSnapshotTask = Task { [weak self] in
            guard let self else { return }
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            await MainActor.run {
                self.publishGoalJournalWidgetSnapshot()
            }
        }
    }

    private func publishGoalJournalWidgetSnapshot(now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal") else { return }

        let days = buildGoalJournalDays(now: now)
        guard let firstDayKey = days.first?.key,
              let lastDayKey = days.last?.key,
              let startDate = goalJournalDate(from: firstDayKey),
              let lastDate = goalJournalDate(from: lastDayKey)
        else { return }

        let startMs = Int64(startDate.timeIntervalSince1970 * 1000.0)
        let endDate = Calendar.current.date(byAdding: .day, value: 1, to: lastDate) ?? now
        let endMs = Int64(endDate.timeIntervalSince1970 * 1000.0)

        let goals = notes.listGoalSummaries().filter(isGoalJournalActive)
        let dayKeysByTag = notes.listJournalEntryDateKeysByGoalTag(
            tags: goals.map(\.goalTag),
            startMs: startMs,
            endMs: endMs
        )

        let grouped = Dictionary(grouping: goals.map { goal in
            NJWidgetGoalJournalRow(
                id: goal.goalID,
                owner: goalJournalOwnerLabel(domainTagsJSON: goal.domainTagsJSON),
                name: goal.name.isEmpty ? "Untitled" : goal.name,
                goalTag: goal.goalTag,
                filledDayKeys: Array(dayKeysByTag[goal.goalTag] ?? []).sorted()
            )
        }) { $0.owner }

        let sections = preferredGoalJournalOwnerOrder(available: Set(grouped.keys)).compactMap { owner -> NJWidgetGoalJournalSection? in
            guard let rows = grouped[owner], !rows.isEmpty else { return nil }
            let sortedRows = rows.sorted {
                if $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedSame {
                    return $0.goalTag.localizedCaseInsensitiveCompare($1.goalTag) == .orderedAscending
                }
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return NJWidgetGoalJournalSection(owner: owner, rows: sortedRows)
        }

        let snapshot = NJWidgetGoalJournalSnapshot(
            days: days,
            sections: sections,
            generatedAt: Date()
        )

        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: "nj.widget.goal_journal.snapshot.v1")
        WidgetCenter.shared.reloadTimelines(ofKind: "NJGoalJournalWidget")
    }

    private func scheduleTimeSlotWidgetRefresh(delayMs: UInt64) {
        timeSlotWidgetSnapshotTask?.cancel()
        timeSlotWidgetSnapshotTask = Task { [weak self] in
            guard let self else { return }
            if delayMs > 0 {
                try? await Task.sleep(nanoseconds: delayMs * 1_000_000)
            }
            await MainActor.run {
                self.publishTimeSlotWidgetSnapshot()
            }
        }
    }

    func publishTimeSlotWidgetSnapshot(now: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: "group.com.CYC.NotionJournal") else { return }

        let slots = notes.listTimeSlots(ownerScope: "ME")
            .filter { $0.deleted == 0 }
            .map { row in
                NJWidgetTimeSlot(
                    id: row.timeSlotID,
                    title: row.title,
                    category: row.category,
                    startDate: Date(timeIntervalSince1970: TimeInterval(row.startAtMs) / 1000.0),
                    endDate: Date(timeIntervalSince1970: TimeInterval(row.endAtMs) / 1000.0),
                    notes: row.notes
                )
            }
            .sorted { a, b in
                if a.startDate == b.startDate { return a.id > b.id }
                return a.startDate < b.startDate
            }

        guard let slotData = try? JSONEncoder().encode(slots) else { return }
        defaults.set(slotData, forKey: "nj_time_module_slots_v1")

        let habitSnapshot = buildHabitWidgetSnapshot(now: now, slots: slots)
        if let habitData = try? JSONEncoder().encode(habitSnapshot) {
            defaults.set(habitData, forKey: "nj.widget.habit.snapshot.v1")
        }

        WidgetCenter.shared.reloadTimelines(ofKind: "NJComplicationWidget")
        WidgetCenter.shared.reloadTimelines(ofKind: "NJHabitWidget")
    }

    func publishTrainingWeekSnapshotToWidget(referenceDate: Date = Date()) {
        guard let shared = UserDefaults(suiteName: widgetAppGroupID) else { return }
        let cal = Calendar.current
        guard let week = cal.dateInterval(of: .weekOfYear, for: referenceDate) else {
            shared.removeObject(forKey: widgetTrainingWeekKey)
            return
        }

        let keyFormatter = DateFormatter()
        keyFormatter.locale = Locale(identifier: "en_US_POSIX")
        keyFormatter.dateFormat = "yyyy-MM-dd"

        let startKey = keyFormatter.string(from: week.start)
        let endKey = keyFormatter.string(from: cal.date(byAdding: .day, value: 6, to: week.start) ?? week.start)
        let plans = notes.listPlannedExercises(startKey: startKey, endKey: endKey)
            .filter { $0.deleted == 0 }
            .sorted {
                if $0.dateKey == $1.dateKey {
                    return $0.updatedAtMs > $1.updatedAtMs
                }
                return $0.dateKey < $1.dateKey
            }

        let payload = NJTrainingWeekWidgetSnapshot(
            weekOf: startKey,
            generatedAtMs: DBNoteRepository.nowMs(),
            sessions: plans.map {
                NJTrainingWeekWidgetSession(
                    id: $0.planID,
                    dateKey: $0.dateKey,
                    title: $0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? $0.sport : $0.title,
                    sport: $0.sport,
                    category: $0.category,
                    sessionType: $0.sessionType.isEmpty ? nil : $0.sessionType,
                    durationMin: $0.targetDurationMin,
                    distanceKm: $0.targetDistanceKm,
                    notes: $0.notes.isEmpty ? nil : $0.notes,
                    goals: decodeTrainingField($0.goalJSON, as: [NJTrainingGoalFile].self),
                    cueRules: decodeTrainingField($0.cueJSON, as: [NJTrainingCueRuleFile].self),
                    blocks: decodeTrainingField($0.blockJSON, as: [NJTrainingBlockFile].self)
                )
            }
        )

        if let data = try? JSONEncoder().encode(payload) {
            shared.set(data, forKey: widgetTrainingWeekKey)
        } else {
            shared.removeObject(forKey: widgetTrainingWeekKey)
        }
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func decodeTrainingField<T: Decodable>(_ raw: String, as _: T.Type) -> T? {
        guard let data = raw.data(using: .utf8), !data.isEmpty else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    private func buildHabitWidgetSnapshot(now: Date, slots: [NJWidgetTimeSlot]) -> NJWidgetHabitSnapshot {
        let days = buildHabitWidgetDays(now: now)
        let dayKeySet = Set(days.map(\.key))
        struct HabitAggregate {
            var name: String
            var category: String
            var totalSeconds: TimeInterval
            var daySeconds: [String: TimeInterval]
        }

        var grouped: [String: HabitAggregate] = [:]

        for slot in slots {
            let grouping = widgetHabitGrouping(for: slot.title, category: slot.category)
            let duration = max(0, slot.endDate.timeIntervalSince(slot.startDate))
            let dayKey = DBNoteRepository.dateKey(slot.startDate)

            var agg = grouped[grouping.key] ?? HabitAggregate(
                name: grouping.name,
                category: grouping.categoryLabel,
                totalSeconds: 0,
                daySeconds: [:]
            )
            agg.totalSeconds += duration
            if dayKeySet.contains(dayKey) {
                agg.daySeconds[dayKey, default: 0] += duration
            }
            grouped[grouping.key] = agg
        }

        for workout in weeklyFitnessHabitRows(now: now) {
            let groupKey = "\(workout.name.lowercased())|fitness"
            var agg = grouped[groupKey] ?? HabitAggregate(
                name: workout.name,
                category: "Fitness",
                totalSeconds: 0,
                daySeconds: [:]
            )
            agg.totalSeconds += workout.totalSeconds
            for (dayKey, seconds) in workout.daySeconds where dayKeySet.contains(dayKey) {
                agg.daySeconds[dayKey, default: 0] += seconds
            }
            grouped[groupKey] = agg
        }

        let rows = grouped.map { key, agg in
            NJWidgetHabitRow(
                id: key,
                name: agg.name,
                subtitle: habitDurationSubtitle(totalSeconds: agg.totalSeconds, category: agg.category),
                dayMinutes: Dictionary(uniqueKeysWithValues: agg.daySeconds.map { dayKey, seconds in
                    (dayKey, max(0, Int(seconds.rounded() / 60.0)))
                })
            )
        }
        .sorted {
            let lhsSeconds = habitDurationSortValue(from: $0.subtitle)
            let rhsSeconds = habitDurationSortValue(from: $1.subtitle)
            if lhsSeconds == rhsSeconds {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return lhsSeconds > rhsSeconds
        }

        return NJWidgetHabitSnapshot(days: days, rows: rows, generatedAt: now)
    }

    private func widgetHabitGrouping(for rawTitle: String, category rawCategory: String) -> (key: String, name: String, categoryLabel: String) {
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let category = rawCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowerTitle = title.lowercased()
        let lowerCategory = category.lowercased()

        if lowerCategory == "piano" {
            return ("piano|piano", "Piano", "Piano")
        }

        if lowerCategory == "programming" || lowerTitle.hasPrefix("codex:") || lowerTitle == "programming" {
            return ("coding|programming", "Coding", "Programming")
        }

        if lowerTitle == "reflection" || lowerTitle.hasPrefix("reflection:") || lowerTitle.hasPrefix("reflection -") {
            return ("reflection|personal", "Reflection", "Personal")
        }

        let displayName = title.isEmpty ? (category.isEmpty ? "Untitled" : category.capitalized) : title
        let categoryLabel = category.isEmpty ? "" : category.capitalized
        return ("\(displayName.lowercased())|\(lowerCategory)", displayName, categoryLabel)
    }

    private func buildHabitWidgetDays(now: Date) -> [NJWidgetHabitDay] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "E"

        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -delta, to: today) ?? today

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return NJWidgetHabitDay(
                key: DBNoteRepository.dateKey(date),
                shortLabel: formatter.string(from: date)
            )
        }
    }

    private func habitDurationSubtitle(totalSeconds: TimeInterval, category: String) -> String {
        let totalMinutes = max(0, Int(totalSeconds.rounded() / 60.0))
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        let timeText: String
        if hours > 0 && minutes > 0 {
            timeText = "\(hours)h \(minutes)m"
        } else if hours > 0 {
            timeText = "\(hours)h"
        } else {
            timeText = "\(minutes)m"
        }
        if category.isEmpty {
            return "Week: \(timeText)"
        }
        return "\(category) • Week: \(timeText)"
    }

    private func habitDurationSortValue(from subtitle: String) -> Int {
        let parts = subtitle.components(separatedBy: "•")
        let timePart = (parts.last ?? subtitle).trimmingCharacters(in: .whitespacesAndNewlines)
        var total = 0
        let comps = timePart.replacingOccurrences(of: "total", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
        for comp in comps {
            if comp.hasSuffix("h"), let hours = Int(comp.dropLast()) {
                total += hours * 3600
            } else if comp.hasSuffix("m"), let mins = Int(comp.dropLast()) {
                total += mins * 60
            }
        }
        return total
    }

    private func weeklyFitnessHabitRows(now: Date) -> [(name: String, totalSeconds: TimeInterval, daySeconds: [String: TimeInterval])] {
        var calendar = Calendar.current
        calendar.firstWeekday = 1
        let today = calendar.startOfDay(for: now)
        let weekday = calendar.component(.weekday, from: today)
        let delta = (weekday - calendar.firstWeekday + 7) % 7
        let weekStart = calendar.date(byAdding: .day, value: -delta, to: today) ?? today
        let weekEnd = calendar.date(byAdding: .day, value: 7, to: weekStart) ?? now
        let startMs = Int64(weekStart.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(weekEnd.timeIntervalSince1970 * 1000.0)

        let sql = """
        SELECT start_ms, value_num, value_str, metadata_json
        FROM health_samples
        WHERE type = 'workout'
          AND start_ms >= \(startMs)
          AND start_ms < \(endMs)
        ORDER BY start_ms ASC;
        """
        let rows = db.queryRows(sql)

        struct WorkoutAggregate {
            var name: String
            var totalSeconds: TimeInterval
            var daySeconds: [String: TimeInterval]
        }

        var grouped: [String: WorkoutAggregate] = [:]
        for row in rows {
            let rawName = row["value_str"] ?? ""
            let metadata = parseWidgetMetadataJSON(row["metadata_json"] ?? "")
            let name = widgetWorkoutName(valueStr: rawName, metadata: metadata)
            let seconds = max(0, Double(row["value_num"] ?? "") ?? 0)
            let startMsRow = Int64(row["start_ms"] ?? "") ?? 0
            let dayKey = DBNoteRepository.dateKey(Date(timeIntervalSince1970: TimeInterval(startMsRow) / 1000.0))
            var agg = grouped[name.lowercased()] ?? WorkoutAggregate(name: name, totalSeconds: 0, daySeconds: [:])
            agg.totalSeconds += seconds
            agg.daySeconds[dayKey, default: 0] += seconds
            grouped[name.lowercased()] = agg
        }

        return grouped.values.map { ($0.name, $0.totalSeconds, $0.daySeconds) }
    }

    private func parseWidgetMetadataJSON(_ raw: String) -> [String: Any] {
        guard let data = raw.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        return obj
    }

    private func widgetWorkoutName(valueStr: String, metadata: [String: Any]) -> String {
        let lower = valueStr.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let raw = metadata["activity_type"] as? NSNumber {
            switch raw.intValue {
            case 37: return "Outdoor Jog"
            case 13: return "Outdoor Cycling"
            case 52: return "Outdoor Walk"
            case 71: return "Hiking"
            default: break
            }
        }
        if lower.contains("run") || lower.contains("jog") {
            return "Outdoor Jog"
        }
        if lower.contains("cycl") || lower.contains("bike") {
            return "Outdoor Cycling"
        }
        if lower.contains("walk") {
            return "Outdoor Walk"
        }
        if lower.contains("hik") {
            return "Hiking"
        }
        if lower.contains("swim") {
            return "Swimming"
        }
        if lower.contains("tennis") {
            return "Tennis"
        }
        if lower.contains("strength") {
            return "Strength"
        }
        let cleaned = valueStr
            .replacingOccurrences(of: "HKWorkoutActivityType.", with: "")
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? "Workout" : cleaned.capitalized
    }

    func syncTimeSlotOverrunNotifications(now: Date = Date()) {
        NJTimeSlotReminderScheduler.reschedule(
            slots: notes.listTimeSlots(ownerScope: "ME").filter { $0.deleted == 0 },
            now: now
        )
    }

    private func buildGoalJournalDays(now: Date) -> [NJWidgetGoalJournalDay] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let formatter = DateFormatter()
        formatter.locale = Locale.current
        formatter.dateFormat = "E"

        return (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -(6 - offset), to: today) else { return nil }
            return NJWidgetGoalJournalDay(
                key: DBNoteRepository.dateKey(date),
                shortLabel: formatter.string(from: date)
            )
        }
    }

    private func goalJournalDate(from key: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key)
    }

    private func isGoalJournalActive(_ goal: NJGoalSummary) -> Bool {
        let tag = goal.goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tag.isEmpty else { return false }
        guard tag.lowercased().hasPrefix("g.") else { return false }
        let status = goal.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !["archive", "archived", "done", "closed"].contains(status)
    }

    private func goalJournalOwnerLabel(domainTagsJSON: String) -> String {
        let domains: [String] = {
            guard let data = domainTagsJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String] else {
                return []
            }
            return arr
        }()

        for preferred in ["ME", "MM", "ZZ", "DEV"] {
            if domains.contains(where: { topGoalJournalOwner(for: $0) == preferred }) {
                return preferred
            }
        }
        if let first = domains.map(topGoalJournalOwner(for:)).first(where: { !$0.isEmpty }) {
            return first
        }
        return "OTHER"
    }

    private func topGoalJournalOwner(for domain: String) -> String {
        domain
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ".", maxSplits: 1, omittingEmptySubsequences: true)
            .first
            .map { String($0).uppercased() } ?? ""
    }

    private func preferredGoalJournalOwnerOrder(available: Set<String>) -> [String] {
        let preferred = ["ME", "MM", "ZZ", "DEV", "OTHER"]
        return preferred.filter { available.contains($0) } + available.subtracting(preferred).sorted()
    }

    private func repairKnownMissingCloudBlocksIfNeeded() {
        if UserDefaults.standard.bool(forKey: blockRepushRepairKey) { return }
        let localCount = knownBlockRepushIDs.filter { notes.hasBlock(blockID: $0) }.count
        guard localCount > 0 else { return }
        let repushed = repushBlocksToCloud(blockIDs: knownBlockRepushIDs)
        if repushed == localCount {
            UserDefaults.standard.set(true, forKey: blockRepushRepairKey)
        }
    }

    private func repairOutlineAttachedBlocksIfNeeded() {
        let key = "nj_outline_attached_block_repair_done_v1"
        if appKVValue(key) == "1" {
            UserDefaults.standard.set(true, forKey: key)
            return
        }
        if UserDefaults.standard.bool(forKey: key) {
            setAppKVValue(key, "1")
            return
        }

        let refRepairCount = notes.repairOutlineAttachedBlockRefs()
        let attachedBlockIDs = Array(notes.listOutlineAttachedBlockIDs()).sorted()
        let liveAttachedBlockIDs = attachedBlockIDs.filter { notes.hasBlock(blockID: $0) }
        let outlineBackfillCount = runStartupOutlineBackfillIfNeeded()
        let repushed = repushBlocksToCloud(blockIDs: liveAttachedBlockIDs)

        print("NJ_OUTLINE_ATTACH_REPAIR attached=\(attachedBlockIDs.count) live=\(liveAttachedBlockIDs.count) ref_repair=\(refRepairCount) outline_backfill=\(outlineBackfillCount) repushed=\(repushed)")

        if repushed == liveAttachedBlockIDs.count {
            UserDefaults.standard.set(true, forKey: key)
            setAppKVValue(key, "1")
        }
    }

    private func runOneTimeBlockCursorRepairIfNeeded() {
        let key = "nj_one_time_block_cursor_repair_after_hydrate_fix_v1"
        if UserDefaults.standard.bool(forKey: key) { return }
        db.resetCloudKitCursors(entities: ["block", "note_block"])
        UserDefaults.standard.set(true, forKey: key)
        print("NJ_CK_ONE_TIME_BLOCK_CURSOR_REPAIR applied=1 entities=[block,note_block]")
    }

}

private struct NJTrainingWeekWidgetSnapshot: Codable {
    var weekOf: String
    var generatedAtMs: Int64
    var sessions: [NJTrainingWeekWidgetSession]
}

private struct NJTrainingWeekWidgetSession: Codable {
    var id: String
    var dateKey: String
    var title: String
    var sport: String
    var category: String
    var sessionType: String?
    var durationMin: Double
    var distanceKm: Double
    var notes: String?
    var goals: [NJTrainingGoalFile]?
    var cueRules: [NJTrainingCueRuleFile]?
    var blocks: [NJTrainingBlockFile]?
}

enum NJUIModule: String, CaseIterable {
    case note
    case goal
    case outline
    case time
    case investment
    case planning
}
