import SwiftUI
import Proton
import PhotosUI

struct NJChronoNoteListView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var fromDate: Date = Date()
    @State private var toDate: Date = Date()
    @State private var newestFirst: Bool = true
    @State private var excludeTagsText: String = "#WEEKLY"

    @StateObject private var persistence: NJReconstructedNotePersistence

    @State private var loaded = false
    @State private var pendingFocusID: UUID? = nil
    @State private var pendingFocusToStart: Bool = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil

    init() {
        let spec = NJReconstructedSpec.all()
        _persistence = StateObject(wrappedValue: NJReconstructedNotePersistence(spec: spec))
    }

    var body: some View {
        VStack(spacing: 0) {
            filterBar()
            Divider()
            list()
        }
        .navigationTitle("Chrono Blocks")
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let h = focusedHandle() {
                NJProtonFloatingFormatBar(handle: h, pickedPhotoItem: $pickedPhotoItem)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Close") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    reloadNow()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .task { onLoadOnce() }
        .onChange(of: store.sync.initialPullCompleted) { _ in onLoadOnce() }
        .onChange(of: fromDate) { _, _ in reloadNow() }
        .onChange(of: toDate) { _, _ in reloadNow() }
        .onChange(of: newestFirst) { _, _ in reloadNow() }
        .onChange(of: excludeTagsText) { _, _ in reloadNow() }
        .onDisappear { forceCommitFocusedIfAny() }
        .presentationDetents([.height(650), .large])
        .presentationDragIndicator(.visible)
    }

    private func filterBar() -> some View {
        HStack(spacing: 12) {
            DatePicker("From", selection: $fromDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            DatePicker("To", selection: $toDate, displayedComponents: .date)
                .datePickerStyle(.compact)
            Toggle("Newest first", isOn: $newestFirst)
                .toggleStyle(.switch)
            TextField("Exclude tags (comma)", text: $excludeTagsText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func list() -> some View {
        List {
            if persistence.blocks.isEmpty {
                Text("No blocks in range")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(persistence.blocks, id: \.id) { b in
                    row(b)
                }
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
            onMoveToClipboard: nil,
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

    private func onLoadOnce() {
        if loaded { return }
        if !store.sync.initialPullCompleted { return }
        loaded = true
        let (start, end) = weekRange(for: Date())
        fromDate = start
        toDate = end
        persistence.configure(store: store)
        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
        reloadNow()
    }

    private func reloadNow() {
        if !loaded { return }
        forceCommitFocusedIfAny()
        let start = startOfDayMs(fromDate)
        let end = endOfDayMs(toDate)
        let excludeTags = parseExcludeTags(excludeTagsText)
        let spec = NJReconstructedSpec.all(
            startMs: start,
            endMs: end,
            limit: 3000,
            newestFirst: newestFirst,
            excludeTags: excludeTags
        )
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

    private func startOfDayMs(_ date: Date) -> Int64 {
        let cal = Calendar(identifier: .gregorian)
        let d = cal.startOfDay(for: date)
        return Int64(d.timeIntervalSince1970 * 1000.0)
    }

    private func endOfDayMs(_ date: Date) -> Int64 {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "en_US_POSIX")
        let start = cal.startOfDay(for: date)
        let next = cal.date(byAdding: .day, value: 1, to: start) ?? start
        let end = next.addingTimeInterval(-1)
        return Int64(end.timeIntervalSince1970 * 1000.0)
    }

    private func weekRange(for date: Date) -> (Date, Date) {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 1 // Sunday
        let startOfDay = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: startOfDay)
        let delta = weekday - cal.firstWeekday
        let start = cal.date(byAdding: .day, value: -delta, to: startOfDay) ?? startOfDay
        let end = cal.date(byAdding: .day, value: 6, to: start) ?? start
        return (start, end)
    }

    private func parseExcludeTags(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
        }
        .opacity(0.001)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    private func fire(_ f: (NJProtonEditorHandle) -> Void) {
        guard let h = getHandle() else { return }
        f(h)
        h.snapshot()
    }
}
