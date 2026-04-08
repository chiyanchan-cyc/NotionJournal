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
    let filledDayKeys: [String]
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
    @Published var selectedModule: NJUIModule = .note
    @Published var selectedGoalID: String? = nil
    @Published var selectedOutlineID: String? = nil
    @Published var selectedOutlineMainTabID: String? = "ME"
    @Published var selectedOutlineCategoryID: String? = nil
    @Published var selectedOutlineNodeID: String? = nil
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
        let recentNoteBlockRepushCount = bl.backfillDirtyForRecentlyUpdatedLiveNoteBlocks(windowHours: 72, limit: 6000)
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
        print("NJ_DIRTY_BACKFILL recent_note_block_repush=\(recentNoteBlockRepushCount)")
        print("NJ_LINK_REPAIR missing_note_block_from_attachment=\(noteBlockLinkRepairCount)")
        print("NJ_LINK_REPAIR missing_note_block_from_history=\(noteBlockHistoryRepairCount)")
        print("NJ_CALENDAR_PHOTO_REPAIR dirty_requeued=\(calendarPhotoRepairCount)")
        refreshQuickClipboardCount()
        repairOutlineAttachedBlocksIfNeeded()
        repairKnownMissingCloudBlocksIfNeeded()
        publishTrainingWeekSnapshotToWidget()

        self.sync.start()
        if outlineBackfillCount > 0 ||
            liveBlockDirtyBackfillCount > 0 ||
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
        if UserDefaults.standard.bool(forKey: seedVersion) { return }

        let now = DBNoteRepository.nowMs()
        for item in officialFinanceMacroSeed2026() {
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
        #if os(macOS) || targetEnvironment(macCatalyst)
        if audioTranscribeRunning { return }
        audioTranscribeRunning = true
        print("NJ_AUDIO_TRANSCRIBE trigger")
        Task.detached { [weak self] in
            guard let self else { return }
            await NJAudioTranscriber.runOnce(store: self)
            await MainActor.run {
                self.audioTranscribeRunning = false
                print("NJ_AUDIO_TRANSCRIBE done")
            }
        }
        #endif
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
            var filledDayKeys: Set<String>
        }

        var grouped: [String: HabitAggregate] = [:]

        for slot in slots {
            let rawTitle = slot.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let rawCategory = slot.category.trimmingCharacters(in: .whitespacesAndNewlines)
            let displayName = rawTitle.isEmpty ? (rawCategory.isEmpty ? "Untitled" : rawCategory.capitalized) : rawTitle
            let categoryLabel = rawCategory.isEmpty ? "" : rawCategory.capitalized
            let groupKey = "\(displayName.lowercased())|\(rawCategory.lowercased())"
            let duration = max(0, slot.endDate.timeIntervalSince(slot.startDate))
            let dayKey = DBNoteRepository.dateKey(slot.startDate)

            var agg = grouped[groupKey] ?? HabitAggregate(
                name: displayName,
                category: categoryLabel,
                totalSeconds: 0,
                filledDayKeys: []
            )
            agg.totalSeconds += duration
            if dayKeySet.contains(dayKey) {
                agg.filledDayKeys.insert(dayKey)
            }
            grouped[groupKey] = agg
        }

        let rows = grouped.map { key, agg in
            NJWidgetHabitRow(
                id: key,
                name: agg.name,
                subtitle: habitDurationSubtitle(totalSeconds: agg.totalSeconds, category: agg.category),
                filledDayKeys: Array(agg.filledDayKeys).sorted()
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

    private func buildHabitWidgetDays(now: Date) -> [NJWidgetHabitDay] {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
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
            return "\(timeText) total"
        }
        return "\(category) • \(timeText)"
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
    case planning
}
