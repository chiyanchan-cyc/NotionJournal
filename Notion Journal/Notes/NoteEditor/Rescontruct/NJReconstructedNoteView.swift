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

struct NJReconstructedNoteView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    let spec: NJReconstructedSpec

    @StateObject private var persistence: NJReconstructedNotePersistence

    @State private var loaded = false
    @State private var pendingFocusID: UUID? = nil
    @State private var pendingFocusToStart: Bool = false

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
        .toolbar { toolbar() }
        .task { onLoadOnce() }
        .onDisappear { forceCommitFocusedIfAny() }
    }

    private func header() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(persistence.tab.isEmpty ? "" : persistence.tab)
                .font(.caption)
                .foregroundStyle(.secondary)
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
                persistence.reload(makeHandle: { NJProtonEditorHandle() })
            } label: {
                Image(systemName: "arrow.clockwise")
            }
        }
    }

    private func onLoadOnce() {
        if loaded { return }
        loaded = true
        persistence.configure(store: store)
        persistence.updateSpec(spec)
        persistence.reload(makeHandle: { NJProtonEditorHandle() })
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
