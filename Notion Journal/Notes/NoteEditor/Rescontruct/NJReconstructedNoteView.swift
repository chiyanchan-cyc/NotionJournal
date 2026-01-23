import SwiftUI
import UIKit

struct NJReconstructedNoteView: View {
    @EnvironmentObject var store: AppStore

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

            Divider()

            List {
                ForEach(persistence.blocks, id: \.id) { b in
                    let id = b.id
                    let h = b.protonHandle

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
                        isCollapsed: .constant(false),
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
                        },
                        onCtrlReturn: { },
                        onDelete: { },
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
            }
            .listStyle(.plain)
        }
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
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
                    persistence.reload(makeHandle: makeWiredHandle)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task {
            if loaded { return }
            loaded = true
            persistence.configure(store: store)
            persistence.updateSpec(spec)
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

    private func bindingAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? NSAttributedString(string: "\u{200B}") },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    if persistence.focusedBlockID != persistence.blocks[i].id {
                        persistence.focusedBlockID = persistence.blocks[i].id
                    }
                    persistence.blocks[i].attr = v
                }
            }
        )
    }

    private func bindingSel(_ id: UUID) -> Binding<NSRange> {
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
