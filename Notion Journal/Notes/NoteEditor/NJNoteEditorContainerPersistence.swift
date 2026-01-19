import SwiftUI
import Combine
import UIKit

final class NJNoteEditorContainerPersistence: ObservableObject {

    struct BlockState: Identifiable, Equatable {
        let id: UUID
        var blockID: String
        var instanceID: String
        var orderKey: Double
        var createdAtMs: Int64
        var domainPreview: String
        var attr: NSAttributedString
        var sel: NSRange
        var isCollapsed: Bool
        var protonHandle: NJProtonEditorHandle
        var isDirty: Bool
        var loadedUpdatedAtMs: Int64
        var loadedPayloadHash: String
        var protonJSON: String

        init(
            id: UUID = UUID(),
            blockID: String,
            instanceID: String,
            orderKey: Double,
            createdAtMs: Int64 = 0,
            domainPreview: String = "",
            attr: NSAttributedString,
            sel: NSRange = NSRange(location: 0, length: 0),
            isCollapsed: Bool = false,
            protonHandle: NJProtonEditorHandle = NJProtonEditorHandle(),
            isDirty: Bool = false,
            loadedUpdatedAtMs: Int64 = 0,
            loadedPayloadHash: String = "",
            protonJSON: String = ""
        ) {
            self.id = id
            self.blockID = blockID
            self.instanceID = instanceID
            self.orderKey = orderKey
            self.createdAtMs = createdAtMs
            self.domainPreview = domainPreview
            self.attr = attr
            self.sel = sel
            self.isCollapsed = isCollapsed
            self.protonHandle = protonHandle
            self.isDirty = isDirty
            self.loadedUpdatedAtMs = loadedUpdatedAtMs
            self.loadedPayloadHash = loadedPayloadHash
            self.protonJSON = protonJSON
        }

        static func == (lhs: BlockState, rhs: BlockState) -> Bool {
            lhs.id == rhs.id &&
            lhs.blockID == rhs.blockID &&
            lhs.instanceID == rhs.instanceID &&
            lhs.orderKey == rhs.orderKey &&
            lhs.createdAtMs == rhs.createdAtMs &&
            lhs.domainPreview == rhs.domainPreview &&
            lhs.attr.isEqual(to: rhs.attr) &&
            NSEqualRanges(lhs.sel, rhs.sel) &&
            lhs.isCollapsed == rhs.isCollapsed &&
            lhs.isDirty == rhs.isDirty &&
            lhs.loadedUpdatedAtMs == rhs.loadedUpdatedAtMs &&
            lhs.loadedPayloadHash == rhs.loadedPayloadHash &&
            lhs.protonJSON == rhs.protonJSON
        }
    }

    @Published var title: String = ""
    @Published var tab: String = ""
    @Published var blocks: [BlockState] = []
    @Published var focusedBlockID: UUID? = nil

    private var store: AppStore? = nil
    private var noteID: NJNoteID? = nil
    private var commitWork: [UUID: DispatchWorkItem] = [:]
    private var didConfigure = false

    init() { }

    func configure(store: AppStore, noteID: NJNoteID) {
        if didConfigure { return }
        self.store = store
        self.noteID = noteID
        self.didConfigure = true
    }

    private func collapseKey(blockID: String) -> String {
        let n = noteID?.raw ?? "no_note"
        return "nj.note.collapse.\(n).\(blockID)"
    }

    func loadCollapsed(blockID: String) -> Bool {
        UserDefaults.standard.bool(forKey: collapseKey(blockID: blockID))
    }

    func saveCollapsed(blockID: String, collapsed: Bool) {
        UserDefaults.standard.set(collapsed, forKey: collapseKey(blockID: blockID))
    }



    func reload(makeHandle: @escaping () -> NJProtonEditorHandle) {
            guard let store, let noteID else { return }

            if let note = store.notes.getNote(noteID) {
                title = note.title
                tab = note.tabDomain
            } else {
                let now = DBNoteRepository.nowMs()
                let note = NJNote(
                    id: noteID,
                    createdAtMs: now,
                    updatedAtMs: now,
                    notebook: "default",
                    tabDomain: "default",
                    title: "Untitled",
                    rtfData: DBNoteRepository.emptyRTF(),
                    deleted: 0
                )
                store.notes.upsertNote(note)
                title = note.title
                tab = note.tabDomain
            }

            let rows = store.notes.loadAllTextBlocksRTFWithPlacement(noteID: noteID.raw)

            if rows.isEmpty {
                let id = UUID()
                let h = makeHandle()
                h.ownerBlockUUID = id

                let newBlockID = UUID().uuidString
                let b = BlockState(
                    id: id,
                    blockID: UUID().uuidString,
                    instanceID: "",
                    orderKey: 1000,
                    attr: makeEmptyBlockAttr(),
                    sel: NSRange(location: 0, length: 0),
                    isCollapsed: loadCollapsed(blockID: newBlockID),
                    protonHandle: h,
                    isDirty: false,
                    loadedUpdatedAtMs: 0,
                    loadedPayloadHash: "",
                    protonJSON: ""
                )
                blocks = [b]
                focusedBlockID = b.id
                return
            }

            var out: [BlockState] = []
            out.reserveCapacity(rows.count)

            for row in rows {
                let id = UUID()
                let h = makeHandle()
                h.ownerBlockUUID = id

                let protonJSON = row.protonJSON

                let attr: NSAttributedString = {
                    if !protonJSON.isEmpty {
                        let first = h.previewFirstLineFromProtonJSON(protonJSON)
                        return ensureNonEmptyTyped(stripZWSP(NSAttributedString(string: first)))
                    }
                    let s = (try? NSAttributedString(
                        data: row.rtfData,
                        options: [.documentType: NSAttributedString.DocumentType.rtf],
                        documentAttributes: nil
                    )) ?? makeEmptyBlockAttr()
                    return ensureNonEmptyTyped(stripZWSP(s))
                }()

                out.append(
                    BlockState(
                        id: id,
                        blockID: row.blockID,
                        instanceID: row.instanceID,
                        orderKey: row.orderKey,
                        attr: attr,
                        sel: NSRange(location: 0, length: 0),
                        isCollapsed: loadCollapsed(blockID: row.blockID),
                        protonHandle: h,
                        isDirty: false,
                        loadedUpdatedAtMs: 0,
                        loadedPayloadHash: "",
                        protonJSON: protonJSON
                    )
                )

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

    func commitNoteMetaNow() {
        guard let store, let noteID else { return }
        let now = DBNoteRepository.nowMs()
        let safeTitle = title.isEmpty ? "Untitled" : title
        let safeTab = tab.isEmpty ? "default" : tab
        if var n = store.notes.getNote(noteID) {
            n.title = safeTitle
            n.tabDomain = safeTab
            n.updatedAtMs = now
            store.notes.upsertNote(n)
        }
    }


    func commitBlockNow(_ id: UUID) {
        guard let store, let noteID else { return }
        guard let i = blocks.firstIndex(where: { $0.id == id }) else { return }

        if !blocks[i].isDirty { return }

        if blocks[i].protonHandle.isEditing {
            scheduleCommit(id, debounce: 0.6)
            return
        }

        var b = blocks[i]

        commitNoteMetaNow()

        let protonJSON = b.protonHandle.exportProtonJSONString()

        store.notes.saveSingleProtonBlock(
            blockID: b.blockID,
            protonJSON: protonJSON
        )

        let now = DBNoteRepository.nowMs()
        b.loadedUpdatedAtMs = now
        b.isDirty = false
        blocks[i] = b
    }
    
}
#imageLiteral(resourceName: "20260105_Compressed_Word_A9D3BB12.pdf")
