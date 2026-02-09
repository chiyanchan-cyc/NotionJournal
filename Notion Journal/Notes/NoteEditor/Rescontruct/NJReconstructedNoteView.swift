//
//  NJReconstructedNoteView.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/23.
//

import SwiftUI
import Combine
import UIKit
import Proton
import os
import PhotosUI

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")


struct NJReconstructedNoteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    
    let spec: NJReconstructedSpec
    
    @StateObject private var persistence: NJReconstructedNotePersistence
    
    @State private var loaded = false
    @State private var pendingFocusID: UUID? = nil
    @State private var pendingFocusToStart: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    
    init(spec: NJReconstructedSpec) {
        self.spec = spec
        _persistence = StateObject(wrappedValue: NJReconstructedNotePersistence(spec: spec))
    }
    
    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            list()
        }
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let h = focusedHandle() {
                NJProtonFloatingFormatBar(handle: h, pickedPhotoItem: $pickedPhotoItem)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar { toolbar() }
        .task { onLoadOnce() }
        .onChange(of: store.sync.initialPullCompleted) { _ in
            onLoadOnce()
        }
        .onDisappear { forceCommitFocusedIfAny() }
        // Add these lines to allow it to resize/popup on iPadOS
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
    }
    
    private func header() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center) {
                Text(persistence.tab.isEmpty ? "" : persistence.tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    reloadNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 10)

            Text(persistence.title)
                .font(.title2)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }
    
    private func list() -> some View {
        List {
            ForEach(persistence.blocks, id: \.id) { b in
                row(b)
            }
        }
        .listStyle(.plain)
    }
    
    private func row(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
        let rowIndex = (persistence.blocks.firstIndex(where: { $0.id == id }) ?? 0) + 1
        let liveTagJSON: String? = persistence.blocks.first(where: { $0.id == id })?.tagJSON

        let onSaveTags: (String) -> Void = { newJSON in
            if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                var arr = persistence.blocks
                arr[i].tagJSON = newJSON
                persistence.blocks = arr
            }
            persistence.markDirty(id)
            persistence.scheduleCommit(id)
        }
        
        return NJBlockHostView(
            index: rowIndex,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: { },
            goalPreview: b.goalPreview,
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
            },
            inheritedTags: [],
            editableTags: [],
            tagJSON: liveTagJSON,
            onSaveTagJSON: onSaveTags
        )
        .id(id)
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(persistence.rowBackgroundColor(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear {
            persistence.hydrateProton(id)
            if pendingFocusID == id {
                if pendingFocusToStart, let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    var arr = persistence.blocks
                    arr[i].sel = NSRange(location: 0, length: 0)
                    persistence.blocks = arr
                }
                persistence.focusedBlockID = id
                pendingFocusID = nil
                pendingFocusToStart = false
                h.focus()
            }
        }
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
        
        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                forceCommitFocusedIfAny()
                reloadNow()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private func reloadNow() {
        forceCommitFocusedIfAny()
        persistence.reload(makeHandle: {
            let h = NJProtonEditorHandle()
            h.attachmentResolver = { [weak store] id in
                store?.notes.attachmentByID(id)
            }
            h.attachmentThumbPathCleaner = { [weak store] id in
                store?.notes.clearAttachmentThumbPath(attachmentID: id, nowMs: DBNoteRepository.nowMs())
            }
            h.onOpenFullPhoto = { id in
                NJPhotoLibraryPresenter.presentFullPhoto(localIdentifier: id)
            }
            return h
        })
    }
    
    private func onLoadOnce() {
        if loaded { return }
        if !store.sync.initialPullCompleted { return }
        loaded = true
        persistence.configure(store: store)
        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
        persistence.updateSpec(spec)
        persistence.reload(makeHandle: {
            let h = NJProtonEditorHandle()
            h.attachmentResolver = { [weak store] id in
                store?.notes.attachmentByID(id)
            }
            h.attachmentThumbPathCleaner = { [weak store] id in
                store?.notes.clearAttachmentThumbPath(attachmentID: id, nowMs: DBNoteRepository.nowMs())
            }
            h.onOpenFullPhoto = { id in
                NJPhotoLibraryPresenter.presentFullPhoto(localIdentifier: id)
            }
            return h
        })
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
                persistence.setCollapsed(id: id, collapsed: v)
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

    private func focusedHandle() -> NJProtonEditorHandle? {
        guard let id = persistence.focusedBlockID else { return nil }
        return persistence.blocks.first(where: { $0.id == id })?.protonHandle
    }

    
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
