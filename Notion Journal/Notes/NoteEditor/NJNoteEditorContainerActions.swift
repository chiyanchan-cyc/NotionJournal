import SwiftUI

extension NJNoteEditorContainerView {

    func makeWiredHandle() -> NJProtonEditorHandle {
        let handle = NJProtonEditorHandle()

        handle.onUserTyped = { [weak p = persistence, weak handle] _, _ in
            guard let p, let id = handle?.ownerBlockUUID else { return }
            p.markDirty(id)
            p.scheduleCommit(id)
        }

        handle.onSnapshot = { [weak p = persistence, weak handle] _, _ in
            guard let p, let id = handle?.ownerBlockUUID else { return }
            p.markDirty(id)
        }

        return handle
    }

    func handleBlockEvent(_ e: NJBlockEvent) {
        switch e {
        case .focus(let id):
            persistence.focusedBlockID = id
        case .ctrlReturn(let id):
            splitBlock(id)
        case .delete(let id):
            deleteBlock(id)
        }
    }

    func deleteWholeNote() {
        store.notes.deleteNote(noteID)
        store.sync.schedulePush(debounceMs: 0)
        dismiss()
    }

    func addBlock(after id: UUID?) {
        let newID = UUID()
        let handle = makeWiredHandle()
        handle.ownerBlockUUID = newID

        let new = NJNoteEditorContainerPersistence.BlockState(
            id: newID,
            blockID: UUID().uuidString,
            instanceID: "",
            orderKey: 0,
            attr: makeEmptyBlockAttr(),
            sel: NSRange(location: 0, length: 0),
            isCollapsed: false,
            protonHandle: handle,
            isDirty: true
        )

        if let id, let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
            persistence.blocks.insert(new, at: i + 1)
        } else {
            persistence.blocks.append(new)
        }

        pendingFocusID = new.id
        pendingFocusToStart = true

        persistence.scheduleCommit(new.id)
    }

    func deleteBlock(_ id: UUID) {
        guard let i = persistence.blocks.firstIndex(where: { $0.id == id }) else { return }
        persistence.blocks.remove(at: i)

        if persistence.blocks.isEmpty {
            let newID = UUID()
            let handle = makeWiredHandle()
            handle.ownerBlockUUID = newID

            let b = NJNoteEditorContainerPersistence.BlockState(
                id: newID,
                blockID: UUID().uuidString,
                instanceID: "",
                orderKey: 1000,
                attr: makeEmptyBlockAttr(),
                sel: NSRange(location: 0, length: 0),
                isCollapsed: false,
                protonHandle: handle,
                isDirty: true
            )
            persistence.blocks = [b]
            persistence.focusedBlockID = b.id
            persistence.scheduleCommit(b.id)
            return
        }

        let nextID = persistence.blocks[min(i, persistence.blocks.count - 1)].id
        persistence.focusedBlockID = nextID
        persistence.markDirty(nextID)
        persistence.scheduleCommit(nextID)
    }

    func splitBlock(_ id: UUID) {
        let now = DBNoteRepository.nowMs()

        NJTextRTFBlockBehavior.split(
            nowMs: now,
            blocks: &persistence.blocks,
            targetID: id,
            lastBreakAtMs: &lastBreakAtMs,
            lastSplitSig: &lastSplitSig,
            lastSplitSigAtMs: &lastSplitSigAtMs,
            pendingFocusID: &pendingFocusID,
            pendingFocusToStart: &pendingFocusToStart,
            ensureNonEmptyTyped: ensureNonEmptyTyped,
            stripZWSP: stripZWSP,
            makeHandle: makeWiredHandle
        )


        for i in persistence.blocks.indices {
            persistence.blocks[i].protonHandle.ownerBlockUUID = persistence.blocks[i].id
        }

        if let fid = persistence.focusedBlockID {
            persistence.markDirty(fid)
            persistence.scheduleCommit(fid)
        }

    }

    func moveBlocks(from source: IndexSet, to destination: Int) {
        let moved = source.compactMap { idx in
            (idx >= 0 && idx < persistence.blocks.count) ? persistence.blocks[idx] : nil
        }

        persistence.blocks.move(fromOffsets: source, toOffset: destination)

        for m in moved {
            guard let i = persistence.blocks.firstIndex(where: { $0.id == m.id }) else { continue }

            let prev = (i > 0) ? persistence.blocks[i - 1].orderKey : 0
            let next = (i + 1 < persistence.blocks.count) ? persistence.blocks[i + 1].orderKey : 0

            var newKey: Double = 1000
            if prev > 0 && next > 0 {
                newKey = (prev + next) / 2.0
            } else if prev > 0 {
                newKey = prev + 1000
            } else if next > 0 {
                newKey = max(1000, next - 1000)
            } else {
                newKey = 1000
            }

            persistence.blocks[i].orderKey = newKey

            let instanceID = persistence.blocks[i].instanceID
            if !instanceID.isEmpty {
                store.notes.updateNoteBlockOrderKey(instanceID: instanceID, orderKey: newKey)
            }
        }
    }
}
