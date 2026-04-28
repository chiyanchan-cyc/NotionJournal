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
    @Environment(\.scenePhase) private var scenePhase

    // Reuse the existing Persistence class!
    @StateObject private var persistence: NJReconstructedNotePersistence

    // Inputs
    @State private var filterInput: String = ""
    @State private var includeMode: NJReconstructedIncludeMode = .any
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()
    @State private var useDateRange: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil

    private let onTitleChange: ((String) -> Void)?
    private let onFilterChange: ((String) -> Void)?
    private let showsDismiss: Bool

    init(
        initialTag: String = "#REMIND",
        initialConfig: NJInternalLinkedViewConfig? = nil,
        showsDismiss: Bool = true,
        onTitleChange: ((String) -> Void)? = nil,
        onTagChange: ((String) -> Void)? = nil
    ) {
        let effectiveConfig = initialConfig ?? NJInternalLinkedViewConfig(
            kind: .reconstructedManual,
            title: initialTag,
            filterText: initialTag,
            matchMode: .any,
            startMs: nil,
            endMs: nil
        )
        let initialSpec = NJReconstructedSpec.all(
            startMs: effectiveConfig.startMs,
            endMs: effectiveConfig.endMs,
            limit: 500,
            newestFirst: true,
            includeTags: [],
            includeMode: effectiveConfig.matchMode == .all ? .all : .any,
            excludeTags: []
        )
        _persistence = StateObject(wrappedValue: NJReconstructedNotePersistence(spec: initialSpec))
        _filterInput = State(initialValue: effectiveConfig.filterText)
        _includeMode = State(initialValue: effectiveConfig.matchMode == .all ? .all : .any)
        if let startMs = effectiveConfig.startMs {
            _startDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(startMs) / 1000.0))
        }
        if let endMs = effectiveConfig.endMs {
            _endDate = State(initialValue: Date(timeIntervalSince1970: TimeInterval(endMs) / 1000.0))
        }
        _useDateRange = State(initialValue: effectiveConfig.startMs != nil || effectiveConfig.endMs != nil)
        self.onTitleChange = onTitleChange
        self.onFilterChange = onTagChange
        self.showsDismiss = showsDismiss
    }

    private func makeWiredHandle() -> NJProtonEditorHandle {
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
        h.onUserTyped = { [weak persistence, weak h] _, _ in
            guard let persistence, let handle = h, let id = handle.ownerBlockUUID else { return }
            if handle.isRunningProgrammaticUpdate { return }
            persistence.enqueueEditorChange(id, source: "recon.manual.onUserTyped.\(handle.userEditSourceHint)")
        }
        h.onSnapshot = { _, _ in
            // Passive snapshots can be emitted by layout/hydration on idle devices.
            // Only explicit user edits should enqueue a save.
        }
        return h
    }

    var body: some View {
        VStack(spacing: 0) {
            // 1. Top Control Bar (The new part)
            controlPanel()
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.systemGroupedBackground))

            Divider()
            if persistence.hasPendingRemoteRefresh {
                remoteRefreshStrip()
            }

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
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .inactive || phase == .background {
                persistence.forceEndEditingAndCommitAllDirtyNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        // Reuse the presentation style
        .presentationDetents([.height(600), .large])
        .presentationDragIndicator(.visible)
    }

    private func remoteRefreshStrip() -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.trianglebadge.exclamationmark")
            Text("Remote update detected. This device will not save over it until you reload.")
                .lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: 8)
            Button {
                performSearch()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
        }
        .font(.caption2)
        .foregroundStyle(.orange)
        .padding(.horizontal, 12)
        .frame(height: 26)
        .background(.ultraThinMaterial)
    }

    // MARK: - UI Helpers
    private func controlPanel() -> some View {
        VStack(alignment: .leading, spacing: 12) {
            // Tag Input
            HStack {
                Image(systemName: "tag.fill")
                    .foregroundColor(.accentColor)
                    .frame(width: 20)
                TextField("Filters (e.g. zz.edu, #remind)", text: $filterInput)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit { performSearch() }
            }

            HStack {
                Text("Match")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Picker("Match", selection: $includeMode) {
                    Text("Any").tag(NJReconstructedIncludeMode.any)
                    Text("All").tag(NJReconstructedIncludeMode.all)
                }
                .pickerStyle(.segmented)
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

            NJBlockListBottomRunwayRow()
        }
        .listStyle(.plain)
    }

    // Copy of the row logic from NJReconstructedNoteView
    private func row(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
        let collapsedBinding = bindingCollapsed(id)
        let liveTagJSON: String? = persistence.blocks.first(where: { $0.id == id })?.tagJSON

        let onSaveTags: (String) -> Void = { newJSON in
            if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                var arr = persistence.blocks
                arr[i].tagJSON = newJSON
                persistence.blocks = arr
            }
            persistence.markDirty(id, source: "recon.manual.saveTags")
            persistence.scheduleCommit(id, source: "recon.manual.saveTags")
        }
        return NJBlockHostView(
            index: 1, // Simplified index
            blockID: b.blockID,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: { },
            goalPreview: b.goalPreview,
            onAddGoal: { },
            hasClipPDF: false,
            onOpenClipPDF: { },
            protonHandle: h,
            isCollapsed: collapsedBinding,
            isFocused: id == persistence.focusedBlockID,
            attr: Binding(
                get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? NSAttributedString(string: "\u{200B}") },
                set: { v in
                    if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                        var arr = persistence.blocks
                        if persistence.focusedBlockID != arr[i].id { persistence.focusedBlockID = arr[i].id }
                        arr[i].attr = v
                        persistence.blocks = arr
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
                if persistence.blocks.first(where: { $0.id == id })?.isDirty == true {
                    persistence.scheduleCommit(id, source: "recon.manual.onCommitProton.alreadyDirty")
                }
            },
            onMoveToClipboard: nil,
            inheritedTags: [],
            editableTags: [],
            tagJSON: liveTagJSON,
            onSaveTagJSON: onSaveTags,
            tagSuggestionsProvider: { prefix, limit in
                store.notes.listTagSuggestions(prefix: prefix, limit: limit)
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(persistence.rowBackgroundColor(blockID: b.blockID))
        .listRowSeparator(.hidden)
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
        let filterText = filterInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let terms = filterText
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let newSpec: NJReconstructedSpec = {
            if terms.isEmpty {
                return NJReconstructedSpec.all(
                    startMs: startMs,
                    endMs: endMs,
                    limit: 500,
                    newestFirst: true,
                    includeMode: includeMode,
                    excludeTags: []
                )
            }

            if terms.count > 1 {
                return NJReconstructedSpec.all(
                    startMs: startMs,
                    endMs: endMs,
                    limit: 500,
                    newestFirst: true,
                    includeTags: terms,
                    includeMode: includeMode,
                    excludeTags: []
                )
            }

            let term = terms[0]

            if term.hasPrefix("#") {
                return NJReconstructedSpec.tagExact(
                    term,
                    startMs: startMs,
                    endMs: endMs,
                    timeField: .blockCreatedAtMs,
                    limit: 500
                )
            }

            if term.contains("*") {
                let prefix = term.replacingOccurrences(of: "*", with: "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if prefix.isEmpty {
                    return NJReconstructedSpec.all(
                        startMs: startMs,
                        endMs: endMs,
                        limit: 500,
                        newestFirst: true,
                        includeMode: includeMode,
                        excludeTags: []
                    )
                }
                return NJReconstructedSpec.tagPrefix(
                    prefix,
                    startMs: startMs,
                    endMs: endMs,
                    timeField: .blockCreatedAtMs,
                    limit: 500
                )
            }

            return NJReconstructedSpec.tagExact(
                term,
                startMs: startMs,
                endMs: endMs,
                timeField: .blockCreatedAtMs,
                limit: 500
            )
        }()

        // Update the title shown in the header
        persistence.updateSpec(newSpec)
        let title = filterText.isEmpty ? "ALL" : filterText
        onTitleChange?(title)
        onFilterChange?(filterText)
        // Trigger the reload using the existing Persistence logic
        persistence.reload(makeHandle: makeWiredHandle)
    }

    @ToolbarContentBuilder
    private func toolbar() -> some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if showsDismiss {
                Button { dismiss() } label: { Image(systemName: "xmark") }
            }
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
        h.snapshot(markUserEdit: true)
    }

}
