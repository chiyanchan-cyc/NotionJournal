import SwiftUI
import Combine
import UIKit
import SQLite3
import PDFKit
import PhotosUI

import os

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")


private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJNoteEditorContainerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    let noteID: NJNoteID

    @StateObject var persistence = NJNoteEditorContainerPersistence()

    @State var loaded = false
    @State var pendingFocusID: UUID? = nil
    @State var pendingFocusToStart: Bool = false
    @State var editMode: EditMode = .inactive
    @State var lastBreakAtMs: Int64 = 0
    @State var lastSplitSig: (UUID, Int, Int, Int)? = nil
    @State var lastSplitSigAtMs: Int64 = 0
    @State var blockBus = NJBlockEventBus()
    @State private var showClipboardInbox = false


    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(persistence.tab.isEmpty ? "" : persistence.tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                TextField("Title", text: $persistence.title)
                    .font(.title2)
                    .textFieldStyle(.roundedBorder)
            }
            
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            List {
                ForEach(persistence.blocks, id: \.id) { b in
                    let id = b.id
                    let h = b.protonHandle

                    let collapsedBinding = Binding(
                        get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
                        set: { v in
                            if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                                persistence.blocks[i].isCollapsed = v
                                persistence.saveCollapsed(blockID: persistence.blocks[i].blockID, collapsed: v)
                            }
                        }
                    )

                    let rowIndex = (persistence.blocks.firstIndex(where: { $0.id == id }) ?? 0) + 1

                    NJBlockHostView(
                        index: rowIndex,
                        createdAtMs: b.createdAtMs,
                        domainPreview: b.domainPreview,
                        onEditTags: { },
                        goalPreview: nil,
                        onAddGoal: { },
                        hasClipPDF: false,
                        onOpenClipPDF: { },
                        protonHandle: h,
                        isCollapsed: collapsedBinding,
                        isFocused: id == persistence.focusedBlockID,
                        attr: bindingAttr(id),
                        sel: bindingSel(id),
                        onFocus: {
                            let prev = persistence.focusedBlockID
                            if let prev, prev != id {
                                persistence.forceEndEditingAndCommitNow(prev)
                            }
                            persistence.focusedBlockID = id
                            h.focus()
                            blockBus.focus(id)
                        },
                        onCtrlReturn: { blockBus.ctrlReturn(id) },
                        onDelete: { blockBus.delete(id) },
                        onHydrateProton: { persistence.hydrateProton(id) },
                        onCommitProton: {
                            persistence.markDirty(id)
                            persistence.scheduleCommit(id)
                        }
                    )
                    .id(id)
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .listRowSeparator(.hidden)
                    .onAppear {
                        if pendingFocusID == id {
                            if pendingFocusToStart, let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                                persistence.blocks[i].sel = NSRange(location: 0, length: 0)
                            }
                            persistence.focusedBlockID = id
                            pendingFocusID = nil
                            pendingFocusToStart = false
                            h.focus()
                        }
                    }
                }
                .onMove(perform: moveBlocks)
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
        }
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
//        .overlay(NJContainerKeyCommands(getHandle: { focusedHandle() })
//            .frame(width: 0, height: 0)
//            .allowsHitTesting(false)
//        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let h = focusedHandle() {
                NJProtonFloatingFormatBar(handle: h)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                
                Button {
                    if let id = persistence.focusedBlockID {
                        persistence.forceEndEditingAndCommitNow(id)
                    }
                    showClipboardInbox = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }

                Button {
                    editMode = (editMode == .active) ? .inactive : .active
                } label: {
                    Image(systemName: editMode == .active ? "checkmark.circle" : "arrow.up.arrow.down")
                }

                Button {
                    addBlock(after: persistence.focusedBlockID)
                } label: {
                    Image(systemName: persistence.focusedBlockID == nil ? "plus.square" : "square.on.square")
                }

                Button(role: .destructive) {
                    if let id = persistence.focusedBlockID { deleteBlock(id) }
                } label: {
                    Image(systemName: "trash")
                }

                Button(role: .destructive) {
                    deleteWholeNote()
                } label: {
                    Image(systemName: "trash.fill")
                }
            }
        }
        
        .sheet(isPresented: $showClipboardInbox) {
            NJClipboardInboxView(
                noteID: noteID.raw,
                onImported: {
                    persistence.reload(makeHandle: makeWiredHandle)
                }
            )
            .environmentObject(store)
        }

        .task {
            if loaded { return }
            loaded = true
            persistence.configure(store: store, noteID: noteID)
            blockBus.setHandler { e in handleBlockEvent(e) }
            persistence.reload(makeHandle: makeWiredHandle)
        }
        .onDisappear {
            if let id = persistence.focusedBlockID {
                persistence.forceEndEditingAndCommitNow(id)
            }
        }
    }

    private func focusedHandle() -> NJProtonEditorHandle? {
        guard let id = persistence.focusedBlockID else { return nil }
        return persistence.blocks.first(where: { $0.id == id })?.protonHandle
    }

    func bindingAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? makeEmptyBlockAttr() },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    if persistence.focusedBlockID != persistence.blocks[i].id {
                        persistence.focusedBlockID = persistence.blocks[i].id
                    }
                    if !persistence.blocks[i].attr.isEqual(to: v) {
                        persistence.blocks[i].attr = v
                    }

                }
            }
        )
    }

    func bindingSel(_ id: UUID) -> Binding<NSRange> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    persistence.blocks[i].sel = v
                }
            }
        )
    }
}
private struct NJContainerKeyCommands: UIViewControllerRepresentable {
    let getHandle: () -> NJProtonEditorHandle?

    func makeUIViewController(context: Context) -> VC {
        let vc = VC()
        vc.getHandle = getHandle
        return vc
    }

    func updateUIViewController(_ uiViewController: VC, context: Context) {
        uiViewController.getHandle = getHandle
        uiViewController.becomeFirstResponder()
    }

    final class VC: UIViewController {
        var getHandle: (() -> NJProtonEditorHandle?)? = nil

        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override var keyCommands: [UIKeyCommand]? {
            let mk: (String, UIKeyModifierFlags, Selector) -> UIKeyCommand = { input, flags, sel in
                let c = UIKeyCommand(input: input, modifierFlags: flags, action: sel)
                c.wantsPriorityOverSystemBehavior = true
                return c
            }

            return [
                mk("b", .command, #selector(cmdBold)),
                mk("i", .command, #selector(cmdItalic)),
                mk("u", .command, #selector(cmdUnderline)),
                mk("x", [.command, .shift], #selector(cmdStrike)),
                mk("\t", [], #selector(cmdTab)),
                mk("\t", [.shift], #selector(cmdShiftTab)),
                mk("]", .command, #selector(cmdIndent)),
                mk("[", .command, #selector(cmdOutdent)),
                mk("7", .command, #selector(cmdBullet)),
                mk("8", .command, #selector(cmdNumber))
            ]

        }

        @objc func cmdBold() { withHandle { $0.toggleBold() } }
        @objc func cmdItalic() { withHandle { $0.toggleItalic() } }
        @objc func cmdUnderline() { withHandle { $0.toggleUnderline() } }
        @objc func cmdStrike() { withHandle { $0.toggleStrike() } }
        @objc func cmdIndent() { withHandle { $0.indent() } }
        @objc func cmdOutdent() { withHandle { $0.outdent() } }
        @objc func cmdBullet() { withHandle { $0.toggleBullet() } }
        @objc func cmdNumber() { withHandle { $0.toggleNumber() } }
        @objc func cmdTab() { withHandle { $0.indent() } }
        @objc func cmdShiftTab() { withHandle { $0.outdent() } }


        private func withHandle(_ f: (NJProtonEditorHandle) -> Void) {
            guard let h = getHandle?() else { return }
            f(h)
            h.snapshot()
        }
    }
}

private struct NJProtonFloatingFormatBar: View {
    let handle: NJProtonEditorHandle

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                Button { handle.decreaseFont(); handle.snapshot() } label: { Image(systemName: "textformat.size.smaller") }
                Button { handle.increaseFont(); handle.snapshot() } label: { Image(systemName: "textformat.size.larger") }

                Divider().frame(height: 18)

                Button { handle.toggleBold(); handle.snapshot() } label: { Image(systemName: "bold") }
                Button { handle.toggleItalic(); handle.snapshot() } label: { Image(systemName: "italic") }
                Button { handle.toggleUnderline(); handle.snapshot() } label: { Image(systemName: "underline") }
                Button { handle.toggleStrike(); handle.snapshot() } label: { Image(systemName: "strikethrough") }

                Divider().frame(height: 18)

                Button { handle.toggleNumber(); handle.snapshot() } label: { Image(systemName: "list.number") }
                Button { handle.toggleBullet(); handle.snapshot() } label: { Image(systemName: "list.bullet") }

                Divider().frame(height: 18)

                Button { handle.outdent(); handle.snapshot() } label: { Image(systemName: "decrease.indent") }
                Button { handle.indent(); handle.snapshot() } label: { Image(systemName: "increase.indent") }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 8)
        }
    }
}

private func extractProtonJSON(_ payload: String) -> String? {
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


private struct NJHiddenShortcuts: View {
    let getHandle: () -> NJProtonEditorHandle?

    var body: some View {
        Group {
            Button("") { fire { $0.toggleBold() } }
                .keyboardShortcut("b", modifiers: .command)

            Button("") { fire { $0.toggleItalic() } }
                .keyboardShortcut("i", modifiers: .command)

            Button("") { fire { $0.toggleUnderline() } }
                .keyboardShortcut("u", modifiers: .command)

            Button("") { fire { $0.toggleStrike() } }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Button("") { fire { $0.toggleBullet() } }
                .keyboardShortcut("7", modifiers: .command)

            Button("") { fire { $0.toggleNumber() } }
                .keyboardShortcut("8", modifiers: .command)

            Button("") { fire { $0.indent() } }
                .keyboardShortcut("]", modifiers: .command)

            Button("") { fire { $0.outdent() } }
                .keyboardShortcut("[", modifiers: .command)
            Button("") {
                NJShortcutLog.info("SHORTCUT TEST CMD+K HIT")
            }
            .keyboardShortcut("k", modifiers: .command)

        }
        .opacity(0.001)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    private func fire(_ f: (NJProtonEditorHandle) -> Void) {
        NJShortcutLog.info("SHORTCUT HIT (SwiftUI layer)")

        guard let h = getHandle() else {
            NJShortcutLog.error("SHORTCUT: getHandle() returned nil")
            return
        }

        NJShortcutLog.info("SHORTCUT: has handle owner=\(String(describing: h.ownerBlockUUID)) editor_nil=\(h.editor == nil) tv_nil=\(h.textView == nil)")
        f(h)
        h.snapshot()
    }

}
