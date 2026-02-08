//
//  NJReconstructedManualView.swift
//  Notion Journal
//

import SwiftUI
import UIKit
import Proton
import os
import PhotosUI

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")

struct NJReconstructedManualView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    // Reuse the existing Persistence class!
    @StateObject private var persistence: NJReconstructedNotePersistence

    // Inputs
    @State private var tagInput: String = ""
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var useDateRange: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil

    init() {
        let initialTag = "#REMIND"
        let initialSpec = NJReconstructedSpec.tagPrefix(initialTag)
        _persistence = StateObject(wrappedValue: NJReconstructedNotePersistence(spec: initialSpec))
        
        // You need to initialize the state variable here
        _tagInput = State(initialValue: initialTag)
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Control Bar (The new part)
            controlPanel()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGroupedBackground))

            Divider()

            // 2. The List (Reused from NJReconstructedNoteView)
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
        .onAppear {
            if !store.sync.initialPullCompleted { return }
            persistence.configure(store: store)
            NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
            performSearch() // Load initial data
        }
        .onChange(of: store.sync.initialPullCompleted) { _ in
            if !store.sync.initialPullCompleted { return }
            persistence.configure(store: store)
            NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
            performSearch()
        }
        .onDisappear {
            // Commit any pending changes
            if let id = persistence.focusedBlockID {
                persistence.forceEndEditingAndCommitNow(id)
            }
        }
        // Reuse the presentation style
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - UI Helpers
    private func controlPanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag Input
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                TextField("Tag (e.g. #meeting or work)", text: $tagInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit { performSearch() }
            }

            // Date Toggle
            HStack {
                Toggle("Filter by Date", isOn: $useDateRange.animation())
                Spacer()
                Button {
                    performSearch()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Button("Search") {
                    performSearch()
                }
                .buttonStyle(.borderedProminent)
            }

            // Date Pickers
            if useDateRange {
                HStack {
                    VStack(alignment: .leading) {
                        Text("Start").font(.caption2).foregroundColor(.secondary)
                        DatePicker("", selection: $startDate, displayedComponents: .date).labelsHidden()
                    }
                    Spacer()
                    VStack(alignment: .leading) {
                        Text("End").font(.caption2).foregroundColor(.secondary)
                        DatePicker("", selection: $endDate, in: startDate..., displayedComponents: .date).labelsHidden()
                    }
                }
            }
        }
    }

    // Reuse the exact List logic from NJReconstructedNoteView
    private func list() -> some View {
        List {
            ForEach(persistence.blocks, id: \.id) { b in
                // We can reuse the row logic from the other file, but for clarity I'll put it here
                row(b)
            }
        }
        .listStyle(.plain)
    }

    // Copy of the row logic from NJReconstructedNoteView
    private func row(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
        return NJBlockHostView(
            index: 1, // Simplified index
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
            attr: Binding(
                get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? NSAttributedString(string: "\u{200B}") },
                set: { v in
                    if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                        var arr = persistence.blocks
                        if persistence.focusedBlockID != arr[i].id { persistence.focusedBlockID = arr[i].id }
                        arr[i].attr = v
                        persistence.blocks = arr
                        persistence.markDirty(id)
                        persistence.scheduleCommit(id)
                    }
                }
            ),
            sel: Binding(
                get: { persistence.blocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
                set: { v in
                    if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                        var arr = persistence.blocks
                        arr[i].sel = v
                        persistence.blocks = arr
                    }
                }
            ),
            onFocus: {
                let prev = persistence.focusedBlockID
                if let prev, prev != id { persistence.forceEndEditingAndCommitNow(prev) }
                persistence.focusedBlockID = id
                persistence.hydrateProton(id)
                h.focus()
            },
            onCtrlReturn: { persistence.forceEndEditingAndCommitNow(id) },
            onDelete: { },
            onHydrateProton: { persistence.hydrateProton(id) },
            onCommitProton: {
                persistence.markDirty(id)
                persistence.scheduleCommit(id)
            }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(persistence.rowBackgroundColor(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear { persistence.hydrateProton(id) }
    }

    // Logic to bridge UI inputs to the Spec
    private func performSearch() {
        let (startMs, endMs): (Int64?, Int64?) = {
            guard useDateRange else { return (nil, nil) }
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = .current
            let start = cal.startOfDay(for: startDate)
            let endStart = cal.startOfDay(for: endDate)
            let endExclusive = cal.date(byAdding: .day, value: 1, to: endStart) ?? endStart
            let s = Int64(start.timeIntervalSince1970 * 1000)
            let e = Int64(endExclusive.timeIntervalSince1970 * 1000) - 1
            return (s, e)
        }()
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let newSpec = NJReconstructedSpec.tagPrefix(
            tag,
            startMs: startMs,
            endMs: endMs,
            timeField: .blockCreatedAtMs,
            limit: 500
        )

        // Update the title shown in the header
        persistence.updateSpec(newSpec)
        // Trigger the reload using the existing Persistence logic
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

    @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark") }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button { performSearch() } label: { Image(systemName: "arrow.clockwise") }
        }
    }
    
    private func focusedHandle() -> NJProtonEditorHandle? {
        guard let id = persistence.focusedBlockID else { return nil }
        return persistence.blocks.first(where: { $0.id == id })?.protonHandle
    }

    private func bindingCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { v in
                persistence.setCollapsed(id: id, collapsed: v)
            }
        )
    }

}

private struct NJProtonFloatingFormatBar: View {
    let handle: NJProtonEditorHandle
    @Binding var pickedPhotoItem: PhotosPickerItem?

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

                PhotosPicker(selection: $pickedPhotoItem, matching: .images, photoLibrary: .shared()) {
                    Image(systemName: "photo")
                }

                Button {
                    handle.insertTableAttachment()
                    handle.snapshot()
                } label: {
                    Image(systemName: "tablecells")
                }

                Divider().frame(height: 18)

                Button { handle.outdent(); handle.snapshot() } label: { Image(systemName: "decrease.indent") }
                Button { handle.indent(); handle.snapshot() } label: { Image(systemName: "increase.indent") }
            }
            .buttonStyle(.borderless)
            .labelStyle(.iconOnly)
            .font(.system(size: 16, weight: .semibold))
            .padding(.horizontal, 8)
        }
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let fullRef = newItem.itemIdentifier ?? ""
                if let img = await NJPhotoPickerHelper.loadImage(
                    itemIdentifier: newItem.itemIdentifier,
                    loadData: { try? await newItem.loadTransferable(type: Data.self) }
                ) {
                    handle.insertPhotoAttachment(img, fullPhotoRef: fullRef)
                    handle.snapshot()
                }
                await MainActor.run { pickedPhotoItem = nil }
            }
        }
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
