//
//  NJReconstructedManualView.swift
//  Notion Journal
//

import SwiftUI
import UIKit
import Proton

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
        .toolbar { toolbar() }
        .onAppear {
            persistence.configure(store: store)
            performSearch() // Load initial data
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
            goalPreview: nil,
            onAddGoal: { },
            hasClipPDF: false,
            onOpenClipPDF: { },
            protonHandle: h,
            isCollapsed: Binding(
                get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
                set: { v in
                    if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                        var arr = persistence.blocks
                        arr[i].isCollapsed = v
                        persistence.blocks = arr
                    }
                }
            ),
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
        let startMs = useDateRange ? Int64(startDate.timeIntervalSince1970 * 1000) : nil
        let endMs = useDateRange ? Int64(endDate.timeIntervalSince1970 * 1000) : nil
        let tag = tagInput.trimmingCharacters(in: .whitespacesAndNewlines)

        let newSpec = NJReconstructedSpec.tagPrefix(
            tag,
            startMs: startMs,
            endMs: endMs,
            limit: 500
        )

        // Update the title shown in the header
        persistence.updateSpec(newSpec)
        // Trigger the reload using the existing Persistence logic
        persistence.reload(makeHandle: { NJProtonEditorHandle() })
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
}
