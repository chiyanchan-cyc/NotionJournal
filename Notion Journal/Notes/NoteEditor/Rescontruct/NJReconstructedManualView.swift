//
//  NJReconstructedManualView.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/26.
//


//
//  NJReconstructedManualView.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/23.
//

import SwiftUI
import Combine
import UIKit
import Proton
import SQLite3

// MARK: - 1. The View (UI)
struct NJReconstructedManualView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    // State for the inputs at the top
    @State private var tagInput: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var useDateRange: Bool = false
    
    // State for the persistence layer
    @StateObject private var persistence: NJReconstructedManualPersistence

    // UI State
    @State private var pendingFocusID: UUID? = nil

    init() {
        // Initialize with a default spec that matches nothing initially, or defaults to last 30 days
        let defaultSpec = NJReconstructedSpec.tagPrefix("", startMs: nil, endMs: nil)
        _persistence = StateObject(wrappedValue: NJReconstructedManualPersistence(spec: defaultSpec))
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top Control Bar
            topControls()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGroupedBackground))
            
            Divider()
            
            // List of Blocks
            List {
                ForEach(persistence.blocks, id: \.id) { b in
                    row(b)
                }
            }
            .listStyle(.plain)
        }
        .toolbar { toolbar() }
        .onAppear {
            persistence.configure(store: store)
            // Load initial data
            performSearch()
        }
        .onDisappear {
            forceCommitFocusedIfAny()
        }
        // Allow resizing/popup behavior on iPad
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Top Controls
    @ViewBuilder
    private func topControls() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            
            // Tag Input
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                
                TextField("Enter tag (e.g., #meeting or work)", text: $tagInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        performSearch()
                    }
            }
            
            // Date Toggles
            HStack {
                Toggle("Filter by Date Range", isOn: $useDateRange.animation())
                
                Spacer()
                
                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
                .disabled(tagInput.isEmpty && !useDateRange)
            }
            
            // Date Pickers
            if useDateRange {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Start").font(.caption2).foregroundColor(.secondary)
                        DatePicker("", selection: $startDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .leading) {
                        Text("End").font(.caption2).foregroundColor(.secondary)
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Row View (Same as original, adapted)
    private func row(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
        let rowIndex = (persistence.blocks.firstIndex(where: { $0.id == id }) ?? 0) + 1

        return NJBlockHostView(
            index: rowIndex,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: { },
            goalPreview: nil,
            onAddGoal: { },
            hasClipPDF: false,
            onOpenClipPDF: { },
            protonHandle: h,
            isCollapsed: bindingCollapsed(id),
            isFocused: id == persistence.focusedBlockID,
            attr: bindingAttr(id),
            sel: bindingSel(id),
            onFocus: {
                let prev = persistence.focusedBlockID
                if let prev, prev != id {
                    persistence.forceEndEditingAndCommitNow(prev)
                }
                persistence.focusedBlockID = id
                persistence.hydrateProton(id)
                h.focus()
            },
            onCtrlReturn: {
                persistence.forceEndEditingAndCommitNow(id)
            },
            onDelete: { },
            onHydrateProton: { persistence.hydrateProton(id) },
            onCommitProton: {
                persistence.markDirty(id)
                persistence.scheduleCommit(id)
            }
        )
        .id(id)
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(persistence.rowBackgroundColor(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear {
            persistence.hydrateProton(id)
        }
    }

    // MARK: - Helpers
    private func performSearch() {
        let startMs = useDateRange ? Int64(startDate.timeIntervalSince1970 * 1000) : nil
        let endMs = useDateRange ? Int64(endDate.timeIntervalSince1970 * 1000) : nil
        
        let cleanedTag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        let newSpec: NJReconstructedSpec
        if cleanedTag.isEmpty {
            // If tag is empty, just search by date (or show all if no date)
            // We use .prefix("") to match anything if we wanted, but typically tag queries require a tag.
            // For this demo, let's assume we need a tag. If no tag, we create a dummy spec that loads nothing or just date.
            // To make it useful, let's allow empty tag to act as "All" if date is set.
            newSpec = NJReconstructedSpec.tagPrefix("", startMs: startMs, endMs: endMs, limit: 500)
        } else {
            // Heuristic: if input is a single word/short, use prefix, else exact? 
            // Let's stick to Prefix for flexibility (e.g., typing "work" finds "#work").
            newSpec = NJReconstructedSpec.tagPrefix(cleanedTag, startMs: startMs, endMs: endMs, limit: 500)
        }
        
        persistence.updateSpec(newSpec)
        persistence.reload(makeHandle: { NJProtonEditorHandle() })
    }

    @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                forceCommitFocusedIfAny()
                dismiss()
            } label: {
                Image(systemName: "xmark")
            }
        }
        
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                forceCommitFocusedIfAny()
                performSearch() // Reload
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }
    
    private func forceCommitFocusedIfAny() {
        if let id = persistence.focusedBlockID {
            persistence.forceEndEditingAndCommitNow(id)
        }
    }

    private func bindingCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    arr[i].isCollapsed = v
                    persistence.blocks = arr
                }
            }
        )
    }

    private func bindingAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? NSAttributedString(string: "\u{200B}") },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    if persistence.focusedBlockID != arr[i].id {
                        persistence.focusedBlockID = arr[i].id
                    }
                    arr[i].attr = v
                    persistence.blocks = arr
                    persistence.markDirty(id)
                    persistence.scheduleCommit(id)
                }
            }
        )
    }

    private func bindingSel(_ id: UUID) -> Binding<NSRange> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    arr[i].sel = v
                    persistence.blocks = arr
                }
            }
        )
    }
}

// MARK: - 2. The Persistence Logic
// This class duplicates the logic from NJReconstructedNotePersistence but is separate 
// so we can modify it for the manual view if needed in the future.
final class NJReconstructedManualPersistence: ObservableObject {
    @Published var title: String = ""
    @Published var tab: String = ""
    @Published var blocks: [NJNoteEditorContainerPersistence.BlockState] = []
    @Published var focusedBlockID: UUID? = nil
    @Published var blockMainDomainByBlockID: [String: String] = [:]

    private var store: AppStore? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var didConfigure = false

    private var spec: NJReconstructedSpec

    init(spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
    }

    func configure(store: AppStore) {
        if didConfigure { return }
        self.store = store
        self.didConfigure = true
    }

    func updateSpec(_ spec: NJReconstructedSpec) {
        self.spec = spec
        self.title = spec.title
        self.tab = spec.tab
    }
    
    // Note: For brevity, I am reusing the extension methods where possible, 
    // but typically you might extract the common logic into a base class.
    // Since I can't modify the original file structure, I will include the necessary DB logic here.
    
    private func mainDomainKey(_ s: String) -> String {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        let parts = t.split(separator: ".")
        if parts.count == 0 { return "" }
        if parts.first == "zz", parts.count >= 2 {
            return "\(parts[0]).\(parts[1])"
        }
        return String(parts[0])
    }

    private func pastelColorForMainDomain(_ key: String) -> Color {
        let baseHue: [String: Double] = [
            "me": 55,
            "zz.edu": 330,
            "zz.adhd": 28
        ]

        let hueDeg: Double = {
            if let h = baseHue[key] { return h }
            let v = abs(key.hashValue) % 360
            return Double(v)
        }()

        return Color(hue: hueDeg / 360.0, saturation: 0.30, brightness: 0.97)
    }

    func rowBackgroundColor(blockID: String) -> Color? {
        guard let key = blockMainDomainByBlockID[blockID], !key.isEmpty else { return nil }
        return pastelColorForMainDomain(key).opacity(0.22)
    }

    // Helper struct to mimic Row from original
    private struct Row {
        let blockID: String
        let protonJSON: String
        let createdAtMs: Int64
    }
    
    // We need to include the SQL generation logic here because it depends on the Spec
    private func sqlWhereForSpec() -> (whereSQL: String, binder: (OpaquePointer?) -> Void) {
        let startMs = spec.startMs
        let endMs = spec.endMs

        let timeExpr: String = {
            switch spec.timeField {
            case .blockCreatedAtMs: return "b.created_at_ms"
            case .tagCreatedAtMs: return "t.created_at_ms"
            }
        }()

        switch spec.match {
        case .exact(let tagRaw):
            let tagA = tagRaw
            let tagB: String = {
                if tagRaw.hasPrefix("#") { return String(tagRaw.dropFirst()) }
                return "#\(tagRaw)"
            }()
            var whereParts: [String] = []
            
            // Handle empty tag (search all)
            if tagA.isEmpty {
                // No tag constraint
            } else {
                whereParts.append("(lower(t.tag)=lower(?) OR lower(t.tag)=lower(?))")
            }
            
            if startMs != nil { whereParts.append("\(timeExpr) >= ?") }
            if endMs != nil { whereParts.append("\(timeExpr) <= ?") }
            
            let whereSQL = whereParts.isEmpty ? "1=1" : whereParts.joined(separator: " AND ")
            
            let binder: (OpaquePointer?) -> Void = { stmt in
                guard let stmt else { return }
                var i: Int32 = 1
                if !tagA.isEmpty {
                    sqlite3_bind_text(stmt, i, tagA, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)); i += 1
                    sqlite3_bind_text(stmt, i, tagB, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)); i += 1
                }
                if let startMs {
                    sqlite3_bind_int64(stmt, i, startMs); i += 1
                }
                if let endMs {
                    sqlite3_bind_int64(stmt, i, endMs); i += 1
                }
            }
            return (whereSQL, binder)

        case .prefix(let prefixRaw):
            let p = prefixRaw.lowercased()
            
            var whereParts: [String] = []
            
            // Handle empty tag (search all)
            if p.isEmpty {
                // No tag constraint
            } else {
                let like1 = p + "%"
                let pHash = p.hasPrefix("#") ? String(p.dropFirst()) : "#"+p
                let like2 = pHash + "%"
                whereParts.append("(lower(t.tag) LIKE ? OR lower(t.tag) LIKE ?)")
            }

            if startMs != nil { whereParts.append("\(timeExpr) >= ?") }
            if endMs != nil { whereParts.append("\(timeExpr) <= ?") }
            
            let whereSQL = whereParts.isEmpty ? "1=1" : whereParts.joined(separator: " AND ")
            
            let binder: (OpaquePointer?) -> Void = { stmt in
                guard let stmt else { return }
                var i: Int32 = 1
                if !p.isEmpty {
                    sqlite3_bind_text(stmt, i, (p + "%").cString(using: .utf8), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)); i += 1
                    let pHash = p.hasPrefix("#") ? String(p.dropFirst()) : "#"+p
                    sqlite3_bind_text(stmt, i, (pHash + "%").cString(using: .utf8), -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)); i += 1
                }
                if let startMs {
                    sqlite3_bind_int64(stmt, i, startMs); i += 1
                }
                if let endMs {
                    sqlite3_bind_int64(stmt, i, endMs); i += 1
                }
            }
            return (whereSQL, binder)
        }
    }

    private func dbLoadBlockIDsBySpec() -> [String] {
        guard let store else { return [] }
        return store.notes.db.withDB { dbp in
            var out: [String] = []
            var stmt: OpaquePointer?

            let (whereSQL, binder) = sqlWhereForSpec()
            let orderSQL = spec.newestFirst ? "DESC" : "ASC"

            let timeExpr: String = {
                switch spec.timeField {
                case .blockCreatedAtMs: return "b.created_at_ms"
                case .tagCreatedAtMs: return "t.created_at_ms"
                }
            }()

            let sql = """
            SELECT t.block_id
            FROM nj_block_tag t
            LEFT JOIN nj_block b
              ON b.block_id = t.block_id COLLATE NOCASE
            WHERE \(whereSQL)
            GROUP BY t.block_id
            ORDER BY \(timeExpr) \(orderSQL)
            LIMIT ?;
            """

            let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
            if rc0 != SQLITE_OK {
                print("NJ_MANUAL IDS_PREP_FAIL rc=\(rc0)")
                return []
            }
            defer { sqlite3_finalize(stmt) }

            binder(stmt)

            let n = sqlite3_bind_parameter_count(stmt)
            sqlite3_bind_int(stmt, n, Int32(max(1, spec.limit)))

            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { out.append(s) }
                }
            }
            return out
        }
    }
    
    // Duplicate the DB helper methods needed
    private func dbLoadProtonJSONAny(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            let candidates = [
                "proton_json", "protonJSON", "proton_json_str", "proton_json_text",
                "payload_json", "payload_json_str", "payload", "payload_str", "payload_text",
                "rtf_payload", "content_json", "content"
            ]

            for col in candidates {
                var stmt: OpaquePointer?
                let sql = "SELECT \(col) FROM nj_block WHERE block_id = ? LIMIT 1;"
                let rc0 = sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil)
                if rc0 != SQLITE_OK { continue }
                defer { sqlite3_finalize(stmt) }

                sqlite3_bind_text(stmt, 1, blockID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if sqlite3_step(stmt) != SQLITE_ROW { continue }

                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let s = String(cString: c)
                if s.isEmpty { continue }
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
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return 0 }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                out = sqlite3_column_int64(stmt, 0)
            }
            return out
        }
    }

    private func dbLoadNoteDomainForBlockID(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            let candidates = ["tab_domain", "domain", "domain_tag"]
            for col in candidates {
                var stmt: OpaquePointer?
                let sql = """
                SELECT n.\(col)
                FROM nj_note n
                JOIN nj_note_block nb ON nb.note_id = n.note_id
                WHERE nb.block_id = ? COLLATE NOCASE
                  AND (n.deleted IS NULL OR n.deleted = 0)
                ORDER BY n.updated_at_ms DESC
                LIMIT 1;
                """
                if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { continue }
                defer { sqlite3_finalize(stmt) }
                sqlite3_bind_text(stmt, 1, blockID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
                if sqlite3_step(stmt) == SQLITE_ROW {
                    if let c = sqlite3_column_text(stmt, 0) {
                        let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { return s }
                    }
                }
            }
            return ""
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
            sqlite3_bind_text(stmt, 1, blockID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            while sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) {
                    let s = String(cString: c).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !s.isEmpty { tags.append(s) }
                }
            }
            return tags.joined(separator: ", ")
        }
    }

    private func dbLoadBlockTagJSON(_ blockID: String) -> String {
        guard let store else { return "" }
        return store.notes.db.withDB { dbp in
            var out = ""
            var stmt: OpaquePointer?
            let sql = "SELECT tag_json FROM nj_block WHERE block_id = ? LIMIT 1;"
            if sqlite3_prepare_v2(dbp, sql, -1, &stmt, nil) != SQLITE_OK { return "" }
            defer { sqlite3_finalize(stmt) }
            sqlite3_bind_text(stmt, 1, blockID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            if sqlite3_step(stmt) == SQLITE_ROW {
                if let c = sqlite3_column_text(stmt, 0) { out = String(cString: c) }
            }
            return out
        }
    }

    private func dbLoadRows() -> [Row] {
        let ids = dbLoadBlockIDsBySpec()
        if ids.isEmpty { return [] }

        var out: [Row] = []
        out.reserveCapacity(ids.count)

        for bid in ids {
            let createdAtMs = dbLoadCreatedAtMs(bid)
            let protonJSON = dbLoadProtonJSONAny(bid)
            out.append(Row(blockID: bid, protonJSON: protonJSON, createdAtMs: createdAtMs))
        }

        return out
    }

    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
        blockMainDomainByBlockID = [:]

        let rows = dbLoadRows()
        if rows.isEmpty {
            blocks = []
            focusedBlockID = nil
            return
        }

        var out: [NJNoteEditorContainerPersistence.BlockState] = []
        out.reserveCapacity(rows.count)

        var ok: Double = 1000

        for r in rows {
            let noteDomain = dbLoadNoteDomainForBlockID(r.blockID)
            let mainKey = mainDomainKey(noteDomain)
            if !mainKey.isEmpty {
                blockMainDomainByBlockID[r.blockID] = mainKey
            }

            let id = UUID()
            let h = makeHandle()
            h.ownerBlockUUID = id

            let attr: NSAttributedString = {
                if !r.protonJSON.isEmpty {
                    let first = h.previewFirstLineFromProtonJSON(r.protonJSON)
                    return NSAttributedString(string: first.isEmpty ? "\u{200B}" : first)
                }
                return NSAttributedString(string: "\u{200B}")
            }()

            let domainPreview = dbLoadDomainPreview3FromBlockTag(r.blockID)
            let tagJSON = dbLoadBlockTagJSON(r.blockID)

            out.append(
                NJNoteEditorContainerPersistence.BlockState(
                    id: id,
                    blockID: r.blockID,
                    instanceID: "",
                    orderKey: ok,
                    createdAtMs: r.createdAtMs,
                    domainPreview: domainPreview,
                    attr: attr,
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: false,
                    protonHandle: h,
                    isDirty: false,
                    loadedUpdatedAtMs: 0,
                    loadedPayloadHash: "",
                    protonJSON: r.protonJSON,
                    tagJSON: tagJSON
                )
            )

            ok += 1
        }

        blocks = out
        focusedBlockID = blocks.first?.id
    }

    func hydrateProton(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        let json = blocks[i].protonJSON
        if json.isEmpty { return }
        blocks[i].protonHandle.hydrateFromProtonJSONString(json)
    }

    func markDirty(_ id: UUID) {
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty { blocks[i].isDirty = true }
    }

    func scheduleCommit(_ id: UUID, debounce: Double = 0.9) {
        commitWork[id]?.cancel()
        let w = DispatchWorkItem { [weak self] in self?.commitBlockNow(id) }
        commitWork[id] = w
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: w)
    }

    func forceEndEditingAndCommitNow(_ id: UUID) {
        commitWork[id]?.cancel()
        commitWork[id] = nil
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        blocks[i].protonHandle.isEditing = false
        markDirty(id)
        commitBlockNow(id, force: true)
    }

    func commitBlockNow(_ id: UUID, force: Bool = false) {
        guard let store else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }
        if !blocks[i].isDirty { return }

        if !force && blocks[i].protonHandle.isEditing {
            scheduleCommit(id, debounce: 0.6)
            return
        }

        var b = blocks[i]

        guard let editor = b.protonHandle.editor else {
            let protonJSON = b.protonHandle.exportProtonJSONString()
            b.protonJSON = protonJSON
            blocks[i].protonJSON = protonJSON
            store.notes.saveSingleProtonBlock(
                blockID: b.blockID,
                protonJSON: protonJSON,
                tagJSON: b.tagJSON
            )
            b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
            b.isDirty = false
            blocks[i] = b
            return
        }

        let liveAttr = editor.attributedText
        let tagRes = NJTagExtraction.extract(from: liveAttr)
        let tags = tagRes?.tags ?? []

        if let tagRes {
            NotificationCenter.default.post(
                name: Notification.Name("NJ_BLOCK_TAGS_EXTRACTED"),
                object: nil,
                userInfo: [
                    "block_id": b.blockID,
                    "tags": tagRes.tags
                ]
            )
        }

        let tagJSON: String = {
            guard !tags.isEmpty,
                  let data = try? JSONSerialization.data(withJSONObject: tags),
                  let s = String(data: data, encoding: .utf8)
            else { return "" }
            return s
        }()

        if !tagJSON.isEmpty {
            b.tagJSON = tagJSON
            blocks[i].tagJSON = tagJSON
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
        blocks[i].protonJSON = protonJSON

        let tagJSONToSave = tagJSON.isEmpty ? b.tagJSON : tagJSON

        store.notes.saveSingleProtonBlock(
            blockID: b.blockID,
            protonJSON: protonJSON,
            tagJSON: tagJSONToSave
        )

        b.loadedUpdatedAtMs = DBNoteRepository.nowMs()
        b.isDirty = false
        blocks[i] = b
    }
}
