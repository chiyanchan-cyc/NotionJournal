import SwiftUI
import UIKit
import WatchConnectivity

extension Notification.Name {
    static let njTimeSlotInboxDidChange = Notification.Name("nj_time_slot_inbox_did_change")
}

private extension NJTimeSlotCategory {
    static func fromWatchSync(_ raw: String) -> NJTimeSlotCategory? {
        let normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "piano": return .piano
        case "exercise": return .exercise
        case "personal": return .personal
        case "programming": return .programming
        case "video editing", "video_editing", "video-editing": return .videoEditing
        default: return nil
        }
    }
}

final class NJAppDelegate: NSObject, UIApplicationDelegate {
    func applicationWillTerminate(_ application: UIApplication) {
        // Ensure all multi-window scenes are destroyed on quit.
        for session in application.openSessions {
            application.requestSceneSessionDestruction(session, options: nil, errorHandler: nil)
        }
    }
}

final class NJPhoneWatchSyncManager: NSObject, WCSessionDelegate {
    static let shared = NJPhoneWatchSyncManager()

    private let slotKey = "nj_time_module_slots_v1"
    private let trainingWeekKey = "nj_training_week_snapshot_v1"
    private let groupID = NJTimeSlotStore.appGroupID
    private let reminderSyncNotification = Notification.Name("nj_time_slot_inbox_did_change")

    private override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) { session.activate() }

    func pushTrainingSnapshot(_ data: Data) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        if session.delegate !== self {
            session.delegate = self
        }
        guard session.activationState == .activated else {
            session.activate()
            return
        }
        try? session.updateApplicationContext([
            "kind": "NJTrainingWeekSnapshot",
            "data": data
        ])
    }

    func session(_ session: WCSession, didReceiveMessage message: [String : Any], replyHandler: @escaping ([String : Any]) -> Void) {
        guard let kind = message["kind"] as? String else {
            replyHandler([:])
            return
        }
        if kind == "NJRequestTrainingWeekSnapshot" {
            let defaults = UserDefaults(suiteName: groupID) ?? .standard
            let data = defaults.data(forKey: trainingWeekKey)
            replyHandler([
                "kind": "NJTrainingWeekSnapshot",
                "data": data as Any
            ])
            return
        }
        replyHandler([:])
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String : Any] = [:]) {
        guard let kind = userInfo["kind"] as? String else { return }
        guard kind == "NJTimeSlot" else { return }
        guard let id = userInfo["id"] as? String,
              let title = userInfo["title"] as? String,
              let category = userInfo["category"] as? String,
              let startTs = userInfo["start_ts"] as? TimeInterval,
              let endTs = userInfo["end_ts"] as? TimeInterval else { return }
        let notes = (userInfo["notes"] as? String) ?? ""

        let row = NJTimeSlot(
            id: id,
            title: title,
            category: NJTimeSlotCategory.fromWatchSync(category) ?? .personal,
            startDate: Date(timeIntervalSince1970: startTs),
            endDate: Date(timeIntervalSince1970: endTs),
            notes: notes
        )
        persistTimeSlotDirectly(row)
        appendInbox(row)
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let kind = applicationContext["kind"] as? String, kind == "NJTrainingWeekSnapshot",
              let data = applicationContext["data"] as? Data else { return }
        let defaults = UserDefaults(suiteName: groupID) ?? .standard
        defaults.set(data, forKey: trainingWeekKey)
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .njTimeSlotInboxDidChange, object: nil)
        }
    }

    private func persistTimeSlotDirectly(_ row: NJTimeSlot) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
        guard let docsURL = docs.first else { return }
        let dbPath = docsURL.appendingPathComponent("notion_journal.sqlite").path
        let db = SQLiteDB(path: dbPath, resetSchema: false)
        DBSchemaInstaller.ensureSchema(db: db)
        let repo = DBNoteRepository(db: db)
        let startMs = Int64(row.startDate.timeIntervalSince1970 * 1000.0)
        let endMs = Int64(row.endDate.timeIntervalSince1970 * 1000.0)
        let now = DBNoteRepository.nowMs()
        repo.upsertTimeSlot(
            NJTimeSlotRecord(
                timeSlotID: row.id,
                ownerScope: "ME",
                title: row.title,
                category: row.category.rawValue.lowercased(),
                startAtMs: startMs,
                endAtMs: max(endMs, startMs + 15 * 60 * 1000),
                notes: row.notes,
                createdAtMs: startMs > 0 ? startMs : now,
                updatedAtMs: now,
                deleted: 0
            )
        )
        NJTimeSlotReminderScheduler.reschedule(
            slots: repo.listTimeSlots(ownerScope: "ME").filter { $0.deleted == 0 },
            now: Date()
        )
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: self.reminderSyncNotification, object: nil)
        }
    }

    private func appendInbox(_ row: NJTimeSlot) {
        let defaults = UserDefaults(suiteName: groupID) ?? .standard
        var rows: [NJTimeSlot] = []
        if let data = defaults.data(forKey: slotKey),
           let decoded = try? JSONDecoder().decode([NJTimeSlot].self, from: data) {
            rows = decoded
        }
        rows.append(row)
        if let out = try? JSONEncoder().encode(rows) {
            defaults.set(out, forKey: slotKey)
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: self.reminderSyncNotification, object: nil)
        }
    }

}

private enum NJAppURLAction {
    static func handle(_ url: URL, store: AppStore) -> Bool {
        if NJAudioShareReceiver.handleIncomingURL(url) != nil {
            store.runAudioIngestIfNeeded()
            return true
        }

        guard let scheme = url.scheme?.lowercased(), scheme == "notionjournal" else {
            return false
        }

        let host = url.host?.lowercased() ?? ""
        let path = url.path.lowercased()

        switch (host, path) {
        case ("sync-now", _), ("sync", "/now"):
            store.forceSyncNow()
            return true
        case ("pull-now", _), ("pull", "/now"):
            store.forcePullNow(forceSinceZero: false)
            return true
        case ("recover-cloud", _), ("cloud", "/recover"):
            store.recoverFromCloudNow()
            return true
        default:
            return false
        }
    }
}

@main
struct Notion_JournalApp: App {
    @UIApplicationDelegateAdaptor(NJAppDelegate.self) private var appDelegate
    @StateObject private var store = AppStore()
    // Ensure GPS logger is initialized at app launch so background logging starts
    @StateObject private var gpsLogger = NJGPSLogger.shared
    // Ensure Health logger is initialized at app launch so sync can run
    @StateObject private var healthLogger = NJHealthLogger.shared
    private let phoneWatchSync = NJPhoneWatchSyncManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .onAppear {
                    store.publishTrainingWeekSnapshotToWidget(referenceDate: Date())
                }
                .onOpenURL { url in
                    _ = NJAppURLAction.handle(url, store: store)
                }
        }

        WindowGroup(id: "clip-pdf", for: URL.self) { url in
            NJClipPDFWindowPage(url: url.wrappedValue)
                .environmentObject(store)
        }

        WindowGroup(id: "reconstructed-weekly", for: String.self) { value in
            let _ = value.wrappedValue ?? "weekly"
            NJReconstructedNoteView(spec: .weekly())
                .environmentObject(store)
        }

        WindowGroup(id: "reconstructed-workspace") {
            NJReconstructedWorkspaceView()
                .environmentObject(store)
        }

        WindowGroup(id: "reconstructed-manual", for: String.self) { tag in
            if let value = tag.wrappedValue,
               let config = NJInternalLinkedViewConfig.fromWindowValue(value) {
                NJReconstructedManualView(initialTag: config.filterText, initialConfig: config)
                    .environmentObject(store)
            } else {
                NJReconstructedManualView(initialTag: tag.wrappedValue ?? "#REMIND")
                    .environmentObject(store)
            }
        }

        WindowGroup(id: "calendar") {
            NJCalendarView()
                .environmentObject(store)
        }

        WindowGroup(id: "chrono") {
            NJChronoNoteListView()
                .environmentObject(store)
        }

        WindowGroup(id: "goals") {
            NJGoalWorkspaceView()
                .environmentObject(store)
        }

        WindowGroup(id: "outline-detached", for: String.self) { outlineID in
            if let id = outlineID.wrappedValue {
                NJOutlineDetailView(outline: store.outline, outlineID: id)
                    .environmentObject(store)
            } else {
                ContentUnavailableView("Outline not found", systemImage: "exclamationmark.triangle")
            }
        }

        WindowGroup(id: "outline-node-detail", for: String.self) { nodeID in
            if let id = nodeID.wrappedValue {
                NJOutlineNodeDetailWindowView(outline: store.outline, nodeID: id)
                    .environmentObject(store)
            } else {
                ContentUnavailableView("Node not found", systemImage: "exclamationmark.triangle")
            }
        }

        WindowGroup(id: "photo-viewer", for: String.self) { id in
            NJPhotoWindow(localIdentifier: id.wrappedValue)
        }
    }
}
