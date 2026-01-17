import Foundation
import UIKit

enum NJTextRTFBlockBehavior {
    static func split(
        nowMs: Int64,
        blocks: inout [NJNoteEditorContainerPersistence.BlockState],
        targetID: UUID,
        lastBreakAtMs: inout Int64,
        lastSplitSig: inout (UUID, Int, Int, Int)?,
        lastSplitSigAtMs: inout Int64,
        pendingFocusID: inout UUID?,
        pendingFocusToStart: inout Bool,
        ensureNonEmptyTyped: (NSAttributedString) -> NSAttributedString,
        stripZWSP: (NSAttributedString) -> NSAttributedString,
        makeHandle: () -> NJProtonEditorHandle
    ) {
        guard let i = blocks.firstIndex(where: { $0.id == targetID }) else { return }

        let a0 = ensureNonEmptyTyped(blocks[i].attr)
        let sel0 = blocks[i].sel
        let cursor = max(0, min(sel0.location, a0.length))

        let sig = (targetID, sel0.location, sel0.length, stripZWSP(a0).string.hashValue)
        if let last = lastSplitSig, last.0 == sig.0, last.1 == sig.1, last.2 == sig.2, last.3 == sig.3 {
            if nowMs - lastSplitSigAtMs < 1500 { return }
        }
        lastSplitSig = sig
        lastSplitSigAtMs = nowMs

        if nowMs - lastBreakAtMs < 250 { return }
        lastBreakAtMs = nowMs

        let raw = stripZWSP(a0).string
        let isEffectivelyEmpty = raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if cursor == 0 && isEffectivelyEmpty { return }

        let left = a0.attributedSubstring(from: NSRange(location: 0, length: cursor))
        let right = a0.attributedSubstring(from: NSRange(location: cursor, length: a0.length - cursor))

        blocks[i].attr = ensureNonEmptyTyped(stripZWSP(left))
        blocks[i].sel = NSRange(location: blocks[i].attr.length, length: 0)
        blocks[i].isDirty = true

        let nextOrder = (i + 1 < blocks.count) ? blocks[i + 1].orderKey : (blocks[i].orderKey + 1000)
        let newOrder = (blocks[i].orderKey + nextOrder) / 2.0

        let new = NJNoteEditorContainerPersistence.BlockState(
            id: UUID(),
            blockID: UUID().uuidString,
            instanceID: "",
            orderKey: newOrder,
            attr: ensureNonEmptyTyped(stripZWSP(right)),
            sel: NSRange(location: 0, length: 0),
            isCollapsed: false,
            protonHandle: makeHandle(),
            isDirty: true
        )

        blocks.insert(new, at: i + 1)

        pendingFocusID = new.id
        pendingFocusToStart = true
    }
}
