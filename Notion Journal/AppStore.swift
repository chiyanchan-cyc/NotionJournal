import Foundation
import SwiftUI
import UIKit
import Combine
import CloudKit
import WidgetKit

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
    private let blockRepushRepairKey = "nj_known_block_repush_v1"
    private let appActivationSyncDebounceMs: Int64 = 5_000
    private let knownBlockRepushIDs = [
        "5c787ede-d8cb-4242-baab-fd5534cce777",
        "43d59787-47ad-4b15-9d44-326c46e1b3f8",
        "6d72fca7-e9de-4fe2-a26b-770ac86b9118"
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
    @Published var selectedInvestmentTradeTab: NJInvestmentTradeTab = .saasOvershoot
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
        
        CKContainer.default().accountStatus { status, error in
            print("CK_PING status=", status.rawValue, "error=", String(describing: error))
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
        seedRenewalRegistryV1()
        runMeCommonInformationCleanupV1()
        runMeDatabaseCleanupV2()
        runMeDatabaseCleanupV3()
        mirrorPersonalIdentificationCards()
        ensurePersonalIdentificationDatabaseNote()
        notes.syncPersonalIdentificationCardsIntoDatabaseNote()
        let personalIDDuplicateCount = notes.cleanupDuplicatePersonalIdentificationDatabaseNotes()
        if personalIDDuplicateCount > 0 {
            print("NJ_PERSONAL_ID_DUPLICATE_CLEANUP deleted=\(personalIDDuplicateCount)")
        }
        enqueueCardDirtyBackfillIfNeeded()

        let outlineBackfillCount = notes.enqueueOutlineDirtyBackfillIfNeeded()
        let liveBlockDirtyBackfillKey = "nj_dirty_live_block_backfill_done_v1"
        let liveBlockDirtyBackfillCount: Int = {
            if UserDefaults.standard.bool(forKey: liveBlockDirtyBackfillKey) {
                return 0
            }
            let changed = NJLocalBLRunner(db: db).backfillMissingDirtyForLiveBlocks(limit: 20000)
            UserDefaults.standard.set(true, forKey: liveBlockDirtyBackfillKey)
            return changed
        }()
        let bl = NJLocalBLRunner(db: db)
        let duplicateNoteBlockRepairKey = "nj_note_block_duplicate_live_repair_done_v1"
        let duplicateNoteBlockRepairCount: Int = {
            if UserDefaults.standard.bool(forKey: duplicateNoteBlockRepairKey) {
                return 0
            }
            let changed = bl.dedupeDuplicateLiveNoteBlockLinks(limit: 8000)
            UserDefaults.standard.set(true, forKey: duplicateNoteBlockRepairKey)
            return changed
        }()
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
        print("NJ_LINK_REPAIR duplicate_live_note_block=\(duplicateNoteBlockRepairCount)")
        print("NJ_DIRTY_BACKFILL recent_note_block_repush=\(recentNoteBlockRepushCount)")
        print("NJ_LINK_REPAIR missing_note_block_from_attachment=\(noteBlockLinkRepairCount)")
        print("NJ_LINK_REPAIR missing_note_block_from_history=\(noteBlockHistoryRepairCount)")
        print("NJ_CALENDAR_PHOTO_REPAIR dirty_requeued=\(calendarPhotoRepairCount)")
        runOneTimeBlockCursorRepairIfNeeded()
        refreshQuickClipboardCount()
        repairOutlineAttachedBlocksIfNeeded()
        repairKnownMissingCloudBlocksIfNeeded()
        publishTrainingWeekSnapshotToWidget()

        self.sync.start()
        if outlineBackfillCount > 0 ||
            liveBlockDirtyBackfillCount > 0 ||
            duplicateNoteBlockRepairCount > 0 ||
            recentNoteBlockRepushCount > 0 ||
            noteBlockLinkRepairCount > 0 ||
            noteBlockHistoryRepairCount > 0 ||
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
        let seedVersion = "nj_investment_macro_seed_2026_v1"
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
            ("2026-04-27", "7173.91", "+0.12%")
        ]
        var existingIDs = Set(notes.listFinanceMacroEvents(startKey: "2026-01-01", endKey: "2026-12-31").map(\.eventID))
        let now = DBNoteRepository.nowMs()
        for row in spxRows {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: "market_snapshot.us.spx.\(row.dateKey)",
                    dateKey: row.dateKey,
                    title: "S&P \(row.close) \(row.change)",
                    category: "market_snapshot",
                    region: "US",
                    timeText: "Close",
                    impact: row.change.hasPrefix("-") ? "down" : "up",
                    source: row.dateKey == "2026-04-27" ? "AP / Xinhua US close recap" : "Countryeconomy S&P 500 historical chart",
                    notes: "S&P 500 close \(row.close), daily change \(row.change). Stored by US market session date, not by Asia/Shanghai heartbeat run date.",
                    createdAtMs: now,
                    updatedAtMs: now,
                    deleted: 0
                )
            )
            existingIDs.insert("market_snapshot.us.spx.\(row.dateKey)")
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
            ("2026-04-27", "4.30", "-1 bp vs Apr 24")
        ]
        for row in us10yRows {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: "market_snapshot.us.us10y.\(row.dateKey)",
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
            existingIDs.insert("market_snapshot.us.us10y.\(row.dateKey)")
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
            ("2026-04-24", "18.71", "-0.60 pts / -3.11%")
        ]
        for row in vixRows {
            notes.upsertFinanceMacroEvent(
                NJFinanceMacroEvent(
                    eventID: "market_snapshot.us.vix.\(row.dateKey)",
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
            existingIDs.insert("market_snapshot.us.vix.\(row.dateKey)")
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
        }

        UserDefaults.standard.set(true, forKey: spxSeedVersion)
        UserDefaults.standard.set(true, forKey: us10ySeedVersion)
        sync.schedulePush(debounceMs: 0)
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
                    documentNumberHint: "",
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

    private func renewalRegistrySeedV1() -> [(id: String, personName: String, documentName: String, documentType: String, jurisdiction: String, expiryDateKey: String, notes: String)] {
        [
            ("renewal.dad.hk-passport", "Dad", "HK Passport", "passport", "HK", "2035-08-30", ""),
            ("renewal.zz.hk-passport", "Zhou Zhou", "HK Passport", "passport", "HK", "2028-03-22", ""),
            ("renewal.dad.china-driver-license", "Dad", "China Driver License", "driver_license", "China", "2037-12-20", ""),
            ("renewal.zz.hkid", "Zhou Zhou", "HKID", "identity_card", "HK", "", "Expiry date not provided yet."),
            ("renewal.zz.home-return-permit", "Zhou Zhou", "回鄉証", "travel_permit", "China", "2028-05-10", ""),
            ("renewal.zz.re-entry-permit", "Zhou Zhou", "回港証", "travel_permit", "HK", "2028-03-20", ""),
            ("renewal.dad.home-return-permit", "Dad", "回鄉証", "travel_permit", "China", "2029-08-25", ""),
            ("renewal.dad.hk-driver-license", "Dad", "HK Driver License", "driver_license", "HK", "2030-11-23", ""),
            ("renewal.mm.home-return-permit", "Mushy Mushy", "回鄉証", "travel_permit", "China", "2029-04-06", ""),
            ("renewal.mm.us-passport", "Mushy Mushy", "US Passport", "passport", "US", "2029-04-28", ""),
            ("renewal.zz.us-passport", "Zhou Zhou", "US Passport", "passport", "US", "2023-08-14", "Already expired before seed date; needs review."),
            ("renewal.dad.us-passport", "Dad", "US Passport", "passport", "US", "2026-07-06", "")
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

    @MainActor
    func runInitialPullGate() async {
        if didFinishInitialPull { return }

        if sync.initialPullCompleted {
            reloadNotebooksTabsFromDB()
            didFinishInitialPull = true
            return
        }

        for await v in sync.$initialPullCompleted.values {
            if v {
                reloadNotebooksTabsFromDB()
                didFinishInitialPull = true
                break
            }
        }
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
        print("NJ_CLIP_INGEST trigger")
        Task {
            await NJClipIngestor.ingestAll(store: self)
            await MainActor.run {
                self.clipIngestRunning = false
                print("NJ_CLIP_INGEST done")
            }
        }
    }

    @MainActor
    func runAudioIngestIfNeeded() {
        if audioIngestRunning { return }
        audioIngestRunning = true
        print("NJ_AUDIO_INGEST trigger")
        Task {
            await NJAudioIngestor.ingestAll(store: self)
            await MainActor.run {
                self.audioIngestRunning = false
                print("NJ_AUDIO_INGEST done")
            }
        }
    }

    @MainActor
    func runAudioTranscribeIfNeeded() {
        if audioTranscribeRunning { return }
        audioTranscribeRunning = true
        print("NJ_AUDIO_TRANSCRIBE trigger")
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
                print("NJ_AUDIO_TRANSCRIBE done processed=\(totalProcessed)")
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

        let nbs: [NJNotebook] = notes.listNotebooks().map { row in
            let (id, title, colorHex, _, _, _) = row
            return NJNotebook(
                notebookID: id,
                title: title,
                colorHex: colorHex
            )
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
        guard sync.initialPullCompleted else { return }

        let now = DBNoteRepository.nowMs()
        if lastAppActivationSyncAtMs > 0,
           now - lastAppActivationSyncAtMs < appActivationSyncDebounceMs {
            return
        }
        lastAppActivationSyncAtMs = now

        Task {
            await sync.forceSyncNow()
            await MainActor.run {
                reloadNotebooksTabsFromDB()
                refreshQuickClipboardCount()
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
        if UserDefaults.standard.bool(forKey: key) { return }

        let refRepairCount = notes.repairOutlineAttachedBlockRefs()
        let attachedBlockIDs = Array(notes.listOutlineAttachedBlockIDs()).sorted()
        let liveAttachedBlockIDs = attachedBlockIDs.filter { notes.hasBlock(blockID: $0) }
        let outlineBackfillCount = notes.enqueueOutlineDirtyBackfillIfNeeded()
        let repushed = repushBlocksToCloud(blockIDs: liveAttachedBlockIDs)

        print("NJ_OUTLINE_ATTACH_REPAIR attached=\(attachedBlockIDs.count) live=\(liveAttachedBlockIDs.count) ref_repair=\(refRepairCount) outline_backfill=\(outlineBackfillCount) repushed=\(repushed)")

        if repushed == liveAttachedBlockIDs.count {
            UserDefaults.standard.set(true, forKey: key)
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
