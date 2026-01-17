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

final class UIState: ObservableObject {
    @Published var showDBDebug = false
}

@MainActor
final class AppStore: ObservableObject {
    @Published var notebooks: [NJNotebook]
    @Published var tabs: [NJTab]
    @Published var selectedNotebookID: String?
    @Published var selectedTabID: String?
    @Published var showDBDebugPanel = false
    @Published var didFinishInitialPull = false
    @Published var initialPullError: String? = nil

    @StateObject var ui = UIState()

    let db: SQLiteDB
    let notes: DBNoteRepository
    let sync: CloudSyncEngine

    init() {
        let dbPath = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("notion_journal.sqlite")
            .path

        let db = SQLiteDB(path: dbPath, resetSchema: false)
        DBSchemaInstaller.ensureSchema(db: db)

        self.db = db
        self.notes = DBNoteRepository(db: db)

        let deviceID =
            UIDevice.current.identifierForVendor?.uuidString.lowercased()
            ?? UUID().uuidString.lowercased()

        self.sync = CloudSyncEngine(
            repo: self.notes,
            deviceID: deviceID,
            containerID: "iCloud.com.CYC.NotionJournal"
        )
        
        CKContainer.default().accountStatus { status, error in
            print("CK_PING status=", status.rawValue, "error=", String(describing: error))
        }

        self.notebooks = []
        self.tabs = []
        self.selectedNotebookID = nil
        self.selectedTabID = nil

        self.sync.start()
        Task { await runInitialPullGate() }
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

}
