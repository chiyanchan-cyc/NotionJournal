import Foundation
import SwiftUI
import UIKit
import Combine
import CloudKit

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

final class UIState: ObservableObject {
    @Published var showDBDebug = false
}

@MainActor
final class AppStore: ObservableObject {
    @Published var notebooks: [NJNotebook]
    @Published var tabs: [NJTab]
    @Published var selectedNotebookID: String?
    @Published var selectedTabID: String?
    @Published var selectedModule: NJUIModule = .note
    @Published var selectedGoalID: String? = nil
    @Published var selectedOutlineID: String? = nil
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
        refreshQuickClipboardCount()

        self.sync.start()
        Task { await runInitialPullGate() }

        NotificationCenter.default.addObserver(
            forName: .njPullCompleted,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            let bl = NJLocalBLRunner(db: self.db)
            bl.markBlocksMissingTagIndexDirty(limit: 8000)
            bl.run(.deriveBlockTagIndexAndDomainV1, limit: 2000)
            self.refreshQuickClipboardCount()
        }

        runGoalStatusMigrationIfNeeded()
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

    func createQuickNoteToClipboard(payloadJSON: String) {
        guard notes.createQuickNoteBlock(payloadJSON: payloadJSON) != nil else { return }
        refreshQuickClipboardCount()
        sync.schedulePush(debounceMs: 0)
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

}

enum NJUIModule: String, CaseIterable {
    case note
    case goal
    case outline
}
