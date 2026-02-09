import SwiftUI
import Combine
import UIKit
import Proton
import SQLite3
import CryptoKit

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private func NJStableUUID(_ s: String) -> UUID {
    let d = Data(s.utf8)
    let h = SHA256.hash(data: d)
    var b = [UInt8](h.prefix(16))
    b[6] = (b[6] & 0x0F) | 0x50
    b[8] = (b[8] & 0x3F) | 0x80
    let u = uuid_t(b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15])
    return UUID(uuid: u)
}

enum NJGoalBlockSource {
    case progress
    case mentioned
}

struct NJGoalBlockItem: Identifiable {
    let blockID: String
    let createdAtMs: Int64
    let source: NJGoalBlockSource
    var id: String { blockID }
}

final class NJGoalDetailPersistence: ObservableObject {
    @Published var goalName: String = ""
    @Published var goalTag: String = ""
    @Published var status: String = "seedling"
    @Published var domainTags: [String] = []
    @Published var goalComment: String = ""
    @Published var createdAtMs: Int64 = 0
    @Published var updatedAtMs: Int64 = 0
    @Published var progressBlocks: [NJNoteEditorContainerPersistence.BlockState] = []
    @Published var timelineBlocks: [NJNoteEditorContainerPersistence.BlockState] = []
    @Published var combinedBlocks: [NJGoalBlockItem] = []
    @Published var focusedProgressID: UUID? = nil
    @Published var focusedTimelineID: UUID? = nil

    var focusedHandle: NJProtonEditorHandle? {
        if let id = focusedProgressID {
            if let h = progressBlocks.first(where: { $0.id == id })?.protonHandle { return h }
        }
        if let id = focusedTimelineID {
            if let h = timelineBlocks.first(where: { $0.id == id })?.protonHandle { return h }
        }
        return nil
    }

    private var store: AppStore? = nil
    private var goalID: String = ""
    private var didConfigure = false
    private var progressIndexByBlockID: [String: Int] = [:]
    private var timelineIndexByBlockID: [String: Int] = [:]

    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var commitWorkTimeline: [UUID: DispatchWorkItem] = [:]

    func configure(store: AppStore, goalID: String) {
        self.store = store
        self.goalID = goalID
        didConfigure = true
        loadGoalMeta()
    }

    func updateStatus(_ newStatus: String) {
        guard let store else { return }
        store.notes.updateGoalStatus(goalID: goalID, status: newStatus)
        loadGoalMeta()
    }

    func updateGoalTag(_ tag: String) {
        guard let store else { return }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        store.notes.updateGoalTag(goalID: goalID, goalTag: trimmed, setInProgress: !trimmed.isEmpty)
        loadGoalMeta()
        rebuildCombined()
    }

    func canUseGoalTag(_ tag: String) -> Bool {
        guard let store else { return false }
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        return !store.notes.goalTable.goalTagExists(trimmed, excludingGoalID: goalID)
    }

    func archiveGoal() {
        updateStatus("archive")
    }

    func updateGoalComment(_ text: String) {
        guard let store else { return }
        store.notes.updateGoalComment(goalID: goalID, commentPlainText: text)
        loadGoalMeta()
    }

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
        if !didConfigure { return }
        loadGoalMeta()
        progressBlocks = buildBlocks(blockIDs: dbLoadProgressBlockIDs(), makeHandle: makeHandle)
        timelineBlocks = buildBlocks(blockIDs: dbLoadTimelineBlockIDs(), makeHandle: makeHandle, newestFirst: false)
        rebuildCombined()
        focusedProgressID = progressBlocks.first?.id
    }

    func addProgressBlock(makeHandle: @escaping () -> NJProtonEditorHandle) {
        let newID = UUID()
        let h = makeHandle()
        h.ownerBlockUUID = newID

        let new = NJNoteEditorContainerPersistence.BlockState(
            id: newID,
            blockID: UUID().uuidString,
            instanceID: "",
            orderKey: nextProgressOrderKey(),
            createdAtMs: DBNoteRepository.nowMs(),
            domainPreview: "",
            goalPreview: "",
            attr: makeEmptyBlockAttr(),
            sel: NSRange(location: 0, length: 0),
            isCollapsed: false,
            protonHandle: h,
            isDirty: true,
            loadedUpdatedAtMs: 0,
            loadedPayloadHash: "",
            protonJSON: "",
            tagJSON: ""
        )

        progressBlocks.append(new)
        rebuildCombined()
        focusedProgressID = new.id
        scheduleCommit(new.id)
    }

    func rebuildCombined() {
        progressIndexByBlockID = [:]
        timelineIndexByBlockID = [:]

        for (i, b) in progressBlocks.enumerated() {
            progressIndexByBlockID[b.blockID] = i
        }
        for (i, b) in timelineBlocks.enumerated() {
            timelineIndexByBlockID[b.blockID] = i
        }

        var items: [NJGoalBlockItem] = []
        items.reserveCapacity(progressBlocks.count + timelineBlocks.count)

        for b in progressBlocks {
            items.append(NJGoalBlockItem(blockID: b.blockID, createdAtMs: b.createdAtMs, source: .progress))
        }
        for b in timelineBlocks {
            items.append(NJGoalBlockItem(blockID: b.blockID, createdAtMs: b.createdAtMs, source: .mentioned))
        }

        items.sort { $0.createdAtMs > $1.createdAtMs }
        combinedBlocks = items
    }

    func bindingProgressCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.progressBlocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { v in
                if let i = self.progressBlocks.firstIndex(where: { $0.id == id }) {
                    self.progressBlocks[i].isCollapsed = v
                    self.saveCollapsed(blockID: self.progressBlocks[i].blockID, collapsed: v)
                }
            }
        )
    }

    func bindingTimelineCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { self.timelineBlocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { v in
                if let i = self.timelineBlocks.firstIndex(where: { $0.id == id }) {
                    self.timelineBlocks[i].isCollapsed = v
                    self.saveCollapsed(blockID: self.timelineBlocks[i].blockID, collapsed: v)
                }
            }
        )
    }

    func progressIndex(for blockID: String) -> Int? {
        progressIndexByBlockID[blockID]
    }

    func timelineIndex(for blockID: String) -> Int? {
        timelineIndexByBlockID[blockID]
    }

    func bindingProgressAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { self.progressBlocks.first(where: { $0.id == id })?.attr ?? makeEmptyBlockAttr() },
            set: { v in
                if let i = self.progressBlocks.firstIndex(where: { $0.id == id }) {
                    self.progressBlocks[i].attr = v
                    self.progressBlocks[i].isDirty = true
                }
            }
        )
    }

    func bindingProgressSel(_ id: UUID) -> Binding<NSRange> {
        Binding(
            get: { self.progressBlocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
            set: { v in
                if let i = self.progressBlocks.firstIndex(where: { $0.id == id }) {
                    self.progressBlocks[i].sel = v
                }
            }
        )
    }

    func bindingTimelineAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { self.timelineBlocks.first(where: { $0.id == id })?.attr ?? makeEmptyBlockAttr() },
            set: { v in
                if let i = self.timelineBlocks.firstIndex(where: { $0.id == id }) {
                    self.timelineBlocks[i].attr = v
                    self.timelineBlocks[i].isDirty = true
                }
            }
        )
    }

    func bindingTimelineSel(_ id: UUID) -> Binding<NSRange> {
        Binding(
            get: { self.timelineBlocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
            set: { v in
                if let i = self.timelineBlocks.firstIndex(where: { $0.id == id }) {
                    self.timelineBlocks[i].sel = v
                }
            }
        )
    }

    func focusProgress(_ id: UUID) {
        let prev = focusedProgressID
        if let prev, prev != id {
            forceCommitProgress(prev)
        }
        focusedProgressID = id
        progressBlocks.first(where: { $0.id == id })?.protonHandle.focus()
    }

    func focusTimeline(_ id: UUID) {
        let prev = focusedTimelineID
        if let prev, prev != id {
            forceCommitTimeline(prev)
        }
        focusedTimelineID = id
        timelineBlocks.first(where: { $0.id == id })?.protonHandle.focus()
    }

    func hydrateProgress(_ id: UUID) {
        guard let i = progressBlocks.firstIndex(where: { $0.id == id }) else { return }
        let json = progressBlocks[i].protonJSON
        if json.isEmpty { return }
        progressBlocks[i].protonHandle.hydrateFromProtonJSONString(json)
    }

    func hydrateTimeline(_ id: UUID) {
        guard let i = timelineBlocks.firstIndex(where: { $0.id == id }) else { return }
        let json = timelineBlocks[i].protonJSON
        if json.isEmpty { return }
        timelineBlocks[i].protonHandle.hydrateFromProtonJSONString(json)
    }

    func commitProgress(_ id: UUID) {
        scheduleCommit(id)
    }

    func forceCommitProgress(_ id: UUID) {
        commitWork[id]?.cancel()
        commitWork[id] = nil
        guard let i = progressBlocks.firstIndex(where: { $0.id == id }) else { return }
        progressBlocks[i].protonHandle.isEditing = false
        progressBlocks[i].isDirty = true
        commitBlockNow(id, force: true)
    }

    func markProgressDirty(_ id: UUID, schedule: Bool = true) {
        if let i = progressBlocks.firstIndex(where: { $0.id == id }) {
            progressBlocks[i].isDirty = true
        }
        if schedule { scheduleCommit(id) }
    }

    func commitTimeline(_ id: UUID) {
        scheduleCommitTimeline(id)
    }

    func forceCommitTimeline(_ id: UUID) {
        commitWorkTimeline[id]?.cancel()
        commitWorkTimeline[id] = nil
        guard let i = timelineBlocks.firstIndex(where: { $0.id == id }) else { return }
        timelineBlocks[i].protonHandle.isEditing = false
        timelineBlocks[i].isDirty = true
        commitTimelineBlockNow(id, force: true)
    }

    func markTimelineDirty(_ id: UUID, schedule: Bool = true) {
        if let i = timelineBlocks.firstIndex(where: { $0.id == id }) {
            timelineBlocks[i].isDirty = true
        }
        if schedule { scheduleCommitTimeline(id) }
    }

    func deleteProgressBlock(_ id: UUID) {
        guard let store else { return }
        guard let i = progressBlocks.firstIndex(where: { $0.id == id }) else { return }
        let blockID = progressBlocks[i].blockID
        store.notes.markBlockDeleted(blockID: blockID)
        progressBlocks.remove(at: i)
        rebuildCombined()
        if focusedProgressID == id {
            focusedProgressID = progressBlocks.first?.id
        }
    }

    func setProgressTagJSON(blockID: String, tagJSON: String) {
        guard let i = progressIndexByBlockID[blockID] else { return }
        progressBlocks[i].tagJSON = tagJSON
        progressBlocks[i].isDirty = true
        scheduleCommit(progressBlocks[i].id)
    }

    func setTimelineTagJSON(blockID: String, tagJSON: String) {
        guard let i = timelineIndexByBlockID[blockID] else { return }
        timelineBlocks[i].tagJSON = tagJSON
        timelineBlocks[i].isDirty = true
        scheduleCommitTimeline(timelineBlocks[i].id)
    }

    private func scheduleCommit(_ id: UUID, debounce: Double = 0.9) {
        commitWork[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitBlockNow(id) }
        commitWork[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    private func scheduleCommitTimeline(_ id: UUID, debounce: Double = 0.9) {
        commitWorkTimeline[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitTimelineBlockNow(id) }
        commitWorkTimeline[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    private func commitBlockNow(_ id: UUID, force: Bool = false) {
        guard let store else { return }
        guard let i = progressBlocks.firstIndex(where: { $0.id == id }) else { return }
        if !progressBlocks[i].isDirty { return }

        if !force && progressBlocks[i].protonHandle.isEditing {
            scheduleCommit(id, debounce: 0.6)
            return
        }

        var b = progressBlocks[i]

        guard let editor = b.protonHandle.editor else {
            if b.protonJSON.isEmpty {
                b.isDirty = false
                progressBlocks[i] = b
                return
            }
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: b.protonJSON,
                tagJSON: b.tagJSON,
                goalID: goalID
            )
            b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
            b.isDirty = false
            progressBlocks[i] = b
            return
        }

        let liveAttr = editor.attributedText

        let existingTags: [String] = {
            guard !b.tagJSON.isEmpty,
                  let data = b.tagJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()

        let tagRes = NJTagExtraction.extract(from: liveAttr, existingTags: existingTags)
        let mergedTags = tagRes?.tags ?? existingTags

        let mergedTagJSON: String = {
            guard !mergedTags.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: mergedTags),
                  let s = String(data: data, encoding: .utf8)
            else { return "" }
            return s
        }()

        if !mergedTagJSON.isEmpty {
            b.tagJSON = mergedTagJSON
            progressBlocks[i].tagJSON = mergedTagJSON
        }

        let originalAttr = editor.attributedText
        let originalSel  = editor.selectedRange

        if let cleaned = tagRes?.cleaned {
            editor.attributedText = cleaned
        }

        let protonJSON = b.protonHandle.exportProtonJSONString()

        editor.attributedText = originalAttr
        editor.selectedRange = originalSel

        b.protonJSON = protonJSON
        progressBlocks[i].protonJSON = protonJSON

        let nowMs = DBNoteRepository.nowMs()
        store.notes.saveSingleProtonBlock(
            blockID: b.blockID,
            protonJSON: protonJSON,
            tagJSON: b.tagJSON,
            goalID: goalID
        )

        b.loadedUpdatedAtMs = nowMs
        b.isDirty = false
        progressBlocks[i] = b
    }

    private func commitTimelineBlockNow(_ id: UUID, force: Bool = false) {
        guard let store else { return }
        guard let i = timelineBlocks.firstIndex(where: { $0.id == id }) else { return }
        if !timelineBlocks[i].isDirty { return }

        if !force && timelineBlocks[i].protonHandle.isEditing {
            scheduleCommitTimeline(id, debounce: 0.6)
            return
        }

        var b = timelineBlocks[i]

        guard let editor = b.protonHandle.editor else {
            if b.protonJSON.isEmpty {
                b.isDirty = false
                timelineBlocks[i] = b
                return
            }
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: b.protonJSON,
                tagJSON: b.tagJSON
            )
            b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
            b.isDirty = false
            timelineBlocks[i] = b
            return
        }

        let liveAttr = editor.attributedText

        let existingTags: [String] = {
            guard !b.tagJSON.isEmpty,
                  let data = b.tagJSON.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()

        let tagRes = NJTagExtraction.extract(from: liveAttr, existingTags: existingTags)
        let mergedTags = tagRes?.tags ?? existingTags

        let tagJSON: String = {
            guard !mergedTags.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: mergedTags),
                  let s = String(data: data, encoding: .utf8)
            else { return "" }
            return s
        }()

        if !tagJSON.isEmpty {
            b.tagJSON = tagJSON
            timelineBlocks[i].tagJSON = tagJSON
        }

        let originalAttr = editor.attributedText
        let originalSel  = editor.selectedRange

        if let cleaned = tagRes?.cleaned {
            editor.attributedText = cleaned
        }

        let protonJSON = b.protonHandle.exportProtonJSONString()

        editor.attributedText = originalAttr
        editor.selectedRange = originalSel

        b.protonJSON = protonJSON
        timelineBlocks[i].protonJSON = protonJSON

        let nowMs = DBNoteRepository.nowMs()
        store.notes.saveSingleProtonBlock(
            blockID: b.blockID,
            protonJSON: protonJSON,
            tagJSON: tagJSON.isEmpty ? b.tagJSON : tagJSON
        )

        b.loadedUpdatedAtMs = nowMs
        b.isDirty = false
        timelineBlocks[i] = b
    }

    private func loadGoalMeta() {
        guard let store else { return }
        guard let g = store.notes.goalTable.loadNJGoal(goalID: goalID) else {
            goalName = ""
            goalTag = ""
            status = "seedling"
            domainTags = []
            goalComment = ""
            createdAtMs = 0
            updatedAtMs = 0
            return
        }
        let payloadJSON = (g["payload_json"] as? String) ?? ""
        goalName = decodeGoalName(payloadJSON: payloadJSON)
        goalComment = decodeGoalComment(payloadJSON: payloadJSON)
        goalTag = (g["goal_tag"] as? String) ?? ""
        let domainTagsJSON = (g["domain_tags_json"] as? String) ?? ""
        domainTags = decodeDomainTags(json: domainTagsJSON)
        let st = (g["status"] as? String) ?? ""
        status = st.isEmpty ? "seedling" : st
        createdAtMs = (g["created_at_ms"] as? Int64) ?? Int64((g["created_at_ms"] as? Int) ?? 0)
        updatedAtMs = (g["updated_at_ms"] as? Int64) ?? Int64((g["updated_at_ms"] as? Int) ?? 0)
    }

    private func decodeGoalName(payloadJSON: String) -> String {
        if let data = payloadJSON.data(using: .utf8),
           let payload = try? JSONDecoder().decode(NJGoalPayloadV1.self, from: data) {
            return payload.name
        }
        if let data = payloadJSON.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let name = obj["name"] as? String {
            return name
        }
        return ""
    }

    private func decodeGoalComment(payloadJSON: String) -> String {
        guard let data = payloadJSON.data(using: .utf8) else { return "" }
        if let payload = try? JSONDecoder().decode(NJGoalPayloadV1.self, from: data) {
            if let rtfData = Data(base64Encoded: payload.rtf64),
               let attr = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
                return attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            return ""
        }
        if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let rtf64 = obj["rtf64"] as? String,
           let rtfData = Data(base64Encoded: rtf64),
           let attr = try? NSAttributedString(data: rtfData, options: [.documentType: NSAttributedString.DocumentType.rtf], documentAttributes: nil) {
            return attr.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return ""
    }

    private func decodeDomainTags(json: String) -> [String] {
        guard let data = json.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
        else { return [] }
        return arr.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    private func nextProgressOrderKey() -> Double {
        let maxKey = progressBlocks.map { $0.orderKey }.max() ?? 0
        return maxKey + 1000
    }

    private func dbLoadProgressBlockIDs() -> [String] {
        guard let store else { return [] }
        if goalID.isEmpty { return [] }
        return store.notes.db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT block_id
            FROM nj_block
            WHERE goal_id = ? AND deleted = 0
            ORDER BY created_at_ms DESC;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, goalID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { out.append(s) }
                }
            }
            return out
        }
    }

    private func dbLoadTimelineBlockIDs() -> [String] {
        guard let store else { return [] }
        if goalTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return [] }
        return store.notes.db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT DISTINCT b.block_id
            FROM nj_block_tag t
            JOIN nj_block b
              ON b.block_id = t.block_id
            WHERE t.tag = ? COLLATE NOCASE
              AND b.deleted = 0
            ORDER BY b.created_at_ms DESC;
            """
            let rc = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc != SQLITE_OK { return [] }
            defer { sqlite3_finalize(stmt) }

            sqlite3_bind_text(stmt, 1, goalTag, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { out.append(s) }
                }
            }
            return out
        }
    }

    private func buildBlocks(blockIDs: [String], makeHandle: @escaping () -> NJProtonEditorHandle, newestFirst: Bool = true) -> [NJNoteEditorContainerPersistence.BlockState] {
        if blockIDs.isEmpty { return [] }
        var out: [NJNoteEditorContainerPersistence.BlockState] = []
        out.reserveCapacity(blockIDs.count)

        var ok: Double = 1000
        for bid in blockIDs {
            let createdAtMs = dbLoadCreatedAtMs(bid)
            let protonJSON = dbLoadProtonJSONAny(bid)

            let stableID = UUID(uuidString: bid) ?? NJStableUUID("goal|\(goalID)|\(bid)|")
            let h = makeHandle()
            h.ownerBlockUUID = stableID

            let attr: NSAttributedString = {
                if !protonJSON.isEmpty {
                    let first = h.previewFirstLineFromProtonJSON(protonJSON)
                    return makeTypedFromPlain(first)
                }
                return makeTypedFromPlain("")
            }()

            let domainPreview = dbLoadDomainPreview3FromBlockTag(bid)
            let tagJSON = dbLoadBlockTagJSON(bid)

            out.append(
                NJNoteEditorContainerPersistence.BlockState(
                    id: stableID,
                    blockID: bid,
                    instanceID: "",
                    orderKey: ok,
                    createdAtMs: createdAtMs,
                    domainPreview: domainPreview,
                    goalPreview: "",
                    attr: attr,
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: loadCollapsed(blockID: bid),
                    protonHandle: h,
                    isDirty: false,
                    loadedUpdatedAtMs: 0,
                    loadedPayloadHash: "",
                    protonJSON: protonJSON,
                    tagJSON: tagJSON
                )
            )

            ok += 1
        }

        if newestFirst {
            out.sort { $0.createdAtMs > $1.createdAtMs }
        }

        return out
    }

    private func collapseKey(blockID: String) -> String {
        let g = goalID.isEmpty ? "no_goal" : goalID
        return "nj.goal.collapse.\(g).\(blockID)"
    }

    private func loadCollapsed(blockID: String) -> Bool {
        UserDefaults.standard.bool(forKey: collapseKey(blockID: blockID))
    }

    private func saveCollapsed(blockID: String, collapsed: Bool) {
        UserDefaults.standard.set(collapsed, forKey: collapseKey(blockID: blockID))
    }

    private func makeTypedFromPlain(_ s: String) -> NSAttributedString {
        let cleaned = s.isEmpty ? "\u{200B}" : s
        return NSAttributedString(string: cleaned)
    }

    private func dbLoadBlockTagJSON(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = "SELECT tag_json FROM nj_block WHERE block_id = ? LIMIT 1;"
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { out = String(cString: c) }
            }
            return out
        }
    }

    private func dbLoadDomainPreview3FromBlockTag(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var tags: [String] = []
            var stmt: OpaquePointer?
            let sql = """
            SELECT tag
            FROM nj_block_tag
            WHERE block_id = ? COLLATE NOCASE
            ORDER BY created_at_ms ASC
            LIMIT 3;
            """
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { tags.append(s) }
                }
            }
            return tags.joined(separator: ", ")
        }
    }

    private func dbExtractProtonJSONFromPayload(_ payload: String) -> String? {
        guard
            let data = payload.data(using: .utf8),
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let sections = root["sections"] as? [String: Any],
            let proton1 = sections["proton1"] as? [String: Any],
            let dataNode = proton1["data"] as? [String: Any],
            let pj = dataNode["proton_json"] as? String
        else { return nil }
        return pj
    }

    private func dbLoadProtonJSONAny(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            let candidates = [
                "proton_json",
                "protonJSON",
                "proton_json_str",
                "proton_json_text",
                "payload_json",
                "payload_json_str",
                "payload",
                "payload_str",
                "payload_text",
                "rtf_payload",
                "content_json",
                "content"
            ]

            for col in candidates {
                var stmt: OpaquePointer?
                let sql = "SELECT \(col) FROM nj_block WHERE block_id = ? LIMIT 1;"
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { continue }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
                if sqlite3_step(stmt) != SQLITE_ROW { continue }

                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                if s.isEmpty { continue }

                if s.first == "{" {
                    if let extracted = dbExtractProtonJSONFromPayload(s) {
                        return extracted
                    }
                }

                return s
            }
            return ""
        }
    }

    private func dbLoadCreatedAtMs(_ blockID: String) -> Int64 {
        guard let store else { return 0 }
        return store.notes.db.withDB { dbp in
            var out: Int64 = 0
            var stmt: OpaquePointer?
            let sql = "SELECT created_at_ms FROM nj_block WHERE block_id = ? LIMIT 1;"
            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, SQLITE_TRANSIENT)
            if sqlite3_step(stmt) == SQLITE_ROW {
                out = sqlite3_column_int64(stmt, 0)
            }
            return out
        }
    }
}
