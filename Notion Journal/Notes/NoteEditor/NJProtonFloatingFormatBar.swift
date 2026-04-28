import SwiftUI
import PhotosUI
import UIKit

private enum NJProtonTextColorChoice: String, CaseIterable, Identifiable {
    case black
    case blue
    case red

    var id: String { rawValue }

    var uiColor: UIColor {
        switch self {
        case .black: UIColor.label
        case .blue: UIColor.systemBlue
        case .red: UIColor.systemRed
        }
    }

    var swatchColor: Color {
        switch self {
        case .black: .primary
        case .blue: .blue
        case .red: .red
        }
    }
}

private enum NJInternalLinkComposerTarget: String, Identifiable {
    case note
    case view

    var id: String { rawValue }
}

struct NJProtonFloatingFormatBar: View {
    @EnvironmentObject var store: AppStore
    let handle: NJProtonEditorHandle
    let currentHandle: (() -> NJProtonEditorHandle?)?
    @Binding var pickedPhotoItem: PhotosPickerItem?
    @State private var isPhotoPickerPresented: Bool = false
    @State private var photoTargetHandle: NJProtonEditorHandle? = nil
    @State private var externalLinkPickerKind: NJExternalFileLinkKind? = nil
    @State private var pendingExternalLinkURL: URL? = nil
    @State private var pendingExternalLinkTitle: String = ""
    @State private var showExternalLinkNamePrompt: Bool = false
    @State private var internalComposerTarget: NJInternalLinkComposerTarget? = nil
    @State private var selectedTextColor: NJProtonTextColorChoice = .black
    @State private var showsTextColorPicker: Bool = false

    init(
        handle: NJProtonEditorHandle,
        pickedPhotoItem: Binding<PhotosPickerItem?>,
        currentHandle: (() -> NJProtonEditorHandle?)? = nil
    ) {
        self.handle = handle
        self._pickedPhotoItem = pickedPhotoItem
        self.currentHandle = currentHandle
    }

    private func resolvedHandle() -> NJProtonEditorHandle? {
        NJProtonEditorHandle.firstResponderHandle() ?? currentHandle?() ?? NJProtonEditorHandle.activeHandle() ?? handle
    }

    private func withHandle(_ action: (NJProtonEditorHandle) -> Void) {
        guard let h = resolvedHandle() else { return }
        print("NJ_PHOTO_BAR_HANDLE owner=\(String(describing: h.ownerBlockUUID))")
        action(h)
    }

    private func withFormattingAction(
        sectionAction: NJCollapsibleAttachmentView.BodyFormatAction,
        handleAction: @escaping (NJProtonEditorHandle) -> Void
    ) {
        if NJCollapsibleAttachmentView.performActionOnActiveBody(sectionAction) {
            return
        }
        withHandle {
            $0.isEditing = true
            handleAction($0)
            $0.snapshot(markUserEdit: true)
        }
    }

    private func queueExternalLinkNaming(url: URL, kind: NJExternalFileLinkKind) {
        pendingExternalLinkURL = url
        pendingExternalLinkTitle = NJExternalFileLinkSupport.defaultDisplayName(for: url, kind: kind)
        showExternalLinkNamePrompt = true
    }

    private func clearPendingExternalLink() {
        pendingExternalLinkURL = nil
        pendingExternalLinkTitle = ""
        showExternalLinkNamePrompt = false
    }

    private func commitExternalLink() {
        guard let url = pendingExternalLinkURL else { return }
        let title = pendingExternalLinkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        NJExternalFileLinkSupport.saveBookmark(for: url)
        insertLink(url: url, title: title)
        clearPendingExternalLink()
    }

    private func insertLink(url: URL, title: String) {
        if NJCollapsibleAttachmentView.insertLinkIntoActiveBody(url, title: title) {
            return
        }

        withHandle { handle in
            handle.isEditing = true
            handle.insertLink(url, title: title)
        }
    }

    private func applyTextColor(_ choice: NJProtonTextColorChoice) {
        selectedTextColor = choice
        showsTextColorPicker = false
        withFormattingAction(
            sectionAction: .applyTextColor(choice.uiColor),
            handleAction: { $0.setTextColor(choice.uiColor) }
        )
    }

    @ViewBuilder
    private func textColorButton() -> some View {
        Button {
            showsTextColorPicker.toggle()
        } label: {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(Color.black)
                .frame(width: 18, height: 18)
                .padding(5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: 28, height: 28)
        .accessibilityLabel(Text("Text color"))
    }

    @ViewBuilder
    private func textColorPopup() -> some View {
        VStack(spacing: 8) {
            ForEach(NJProtonTextColorChoice.allCases) { choice in
                Button {
                    applyTextColor(choice)
                } label: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(choice.swatchColor)
                            .frame(width: 28, height: 28)
                        if selectedTextColor == choice {
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .stroke(Color.white, lineWidth: 2)
                                .frame(width: 28, height: 28)
                        }
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text(choice.rawValue.capitalized))
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.white.opacity(0.4), lineWidth: 1)
        )
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    Button { withFormattingAction(sectionAction: .decreaseFont) { $0.decreaseFont() } } label: { Image(systemName: "textformat.size.smaller") }
                    Button { withFormattingAction(sectionAction: .increaseFont) { $0.increaseFont() } } label: { Image(systemName: "textformat.size.larger") }

                    Divider().frame(height: 18)

                    Button { withFormattingAction(sectionAction: .toggleBold) { $0.toggleBold() } } label: { Image(systemName: "bold") }
                    Button { withFormattingAction(sectionAction: .toggleItalic) { $0.toggleItalic() } } label: { Image(systemName: "italic") }
                    Button { withFormattingAction(sectionAction: .toggleUnderline) { $0.toggleUnderline() } } label: { Image(systemName: "underline") }
                    Button { withFormattingAction(sectionAction: .toggleStrike) { $0.toggleStrike() } } label: { Image(systemName: "strikethrough") }
                    textColorButton()

                    Divider().frame(height: 18)

                    Button {
                        withHandle {
                            $0.isEditing = true
                            $0.insertTagLine()
                            $0.snapshot(markUserEdit: true)
                        }
                    } label: {
                        Image(systemName: "tag")
                    }

                    Menu {
                        Button {
                            externalLinkPickerKind = .file
                        } label: {
                            Label("Link to File", systemImage: "doc")
                        }

                        Button {
                            externalLinkPickerKind = .folder
                        } label: {
                            Label("Link to Folder", systemImage: "folder")
                        }

                        Button {
                            internalComposerTarget = .note
                        } label: {
                            Label("Link to Note", systemImage: "note.text")
                        }

                        Button {
                            internalComposerTarget = .view
                        } label: {
                            Label("Link to View", systemImage: "line.3.horizontal.decrease.circle")
                        }
                    } label: {
                        Image(systemName: "link")
                    }

                    Button {
                        photoTargetHandle = resolvedHandle()
                        print("NJ_PHOTO_TARGET_CAPTURED owner=\(String(describing: photoTargetHandle?.ownerBlockUUID))")
                        isPhotoPickerPresented = true
                    } label: {
                        Image(systemName: "photo")
                    }
                    .photosPicker(
                        isPresented: $isPhotoPickerPresented,
                        selection: $pickedPhotoItem,
                        matching: .images,
                        photoLibrary: .shared()
                    )

                    Button {
                        withHandle {
                            $0.isEditing = true
                            $0.insertTableAttachment()
                            $0.snapshot(markUserEdit: true)
                        }
                    } label: {
                        Image(systemName: "tablecells")
                    }

                    Button {
                        withHandle {
                            $0.convertSelectionToCollapsibleSection()
                            $0.snapshot(markUserEdit: true)
                        }
                    } label: {
                        Image(systemName: "chevron.down.square")
                    }

                    Button {
                        withHandle {
                            $0.removeNearestCollapsibleSection()
                            $0.snapshot(markUserEdit: true)
                        }
                    } label: {
                        Image(systemName: "minus.square")
                    }

                    Button { withHandle { $0.isEditing = true; $0.outdent(); $0.snapshot(markUserEdit: true) } } label: { Image(systemName: "decrease.indent") }
                    Button { withHandle { $0.isEditing = true; $0.indent(); $0.snapshot(markUserEdit: true) } } label: { Image(systemName: "increase.indent") }
                }
                .padding(.horizontal, 8)
            }

            if showsTextColorPicker {
                textColorPopup()
                    .offset(x: 168, y: -12)
                    .zIndex(10)
            }
        }
        .buttonStyle(.borderless)
        .labelStyle(.iconOnly)
        .font(.system(size: 16, weight: .semibold))
        .sheet(item: $externalLinkPickerKind) { kind in
            NJExternalLinkDocumentPicker(
                kind: kind,
                onPick: { url in
                    externalLinkPickerKind = nil
                    queueExternalLinkNaming(url: url, kind: kind)
                },
                onCancel: {
                    externalLinkPickerKind = nil
                }
            )
        }
        .sheet(item: $internalComposerTarget) { target in
            switch target {
            case .note:
                NJInternalNoteLinkPickerSheet(
                    notes: scopedNotes(),
                    onCancel: {
                        internalComposerTarget = nil
                    },
                    onInsert: { note, title in
                        internalComposerTarget = nil
                        guard let url = NJExternalFileLinkSupport.noteURL(noteID: note.id.raw) else { return }
                        insertLink(url: url, title: title)
                    }
                )
            case .view:
                NJInternalViewLinkComposerSheet(
                    suggestedDomain: suggestedCurrentDomain(),
                    onCancel: {
                        internalComposerTarget = nil
                    },
                    onInsert: { config, title in
                        internalComposerTarget = nil
                        guard let url = NJExternalFileLinkSupport.viewURL(config: config) else { return }
                        insertLink(url: url, title: title)
                    }
                )
            }
        }
        .alert("Name Link", isPresented: $showExternalLinkNamePrompt) {
            TextField("Link title", text: $pendingExternalLinkTitle)
            Button("Cancel", role: .cancel) {
                clearPendingExternalLink()
            }
            Button("Insert") {
                commitExternalLink()
            }
        } message: {
            Text("Choose the name you want to show in the note.")
        }
        .onChange(of: pickedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task {
                let fullRef = newItem.itemIdentifier ?? ""
                if let img = await NJPhotoPickerHelper.loadImage(
                    itemIdentifier: newItem.itemIdentifier,
                    loadData: { try? await newItem.loadTransferable(type: Data.self) }
                ) {
                    await MainActor.run {
                        if NJCollapsibleAttachmentView.insertImageIntoActiveBody(img) {
                            pickedPhotoItem = nil
                            photoTargetHandle = nil
                            isPhotoPickerPresented = false
                            return
                        }
                        let h = photoTargetHandle ?? resolvedHandle()
                        guard let h else { return }
                        print("NJ_PHOTO_PICKER_HANDLE owner=\(String(describing: h.ownerBlockUUID))")
                        h.isEditing = true
                        h.insertPhotoAttachment(img, fullPhotoRef: fullRef)
                        h.snapshot(markUserEdit: true)
                    }
                }
                await MainActor.run {
                    pickedPhotoItem = nil
                    photoTargetHandle = nil
                    isPhotoPickerPresented = false
                }
            }
        }
    }

    private func scopedNotes() -> [NJNote] {
        var seen = Set<String>()
        var out: [NJNote] = []

        let domainKeys = Array(Set(store.tabs.map { $0.domainKey }))
        for domainKey in domainKeys {
            let notes = store.notes.listNotes(tabDomainKey: domainKey)
            for note in notes where note.deleted == 0 {
                if seen.insert(note.id.raw).inserted {
                    out.append(note)
                }
            }
        }

        return out.sorted {
            if $0.updatedAtMs != $1.updatedAtMs { return $0.updatedAtMs > $1.updatedAtMs }
            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
        }
    }

    private func suggestedCurrentDomain() -> String {
        guard let tabID = store.selectedTabID,
              let tab = store.tabs.first(where: { $0.tabID == tabID }) else {
            return ""
        }
        return tab.domainKey
    }
}

private struct NJInternalNoteLinkPickerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let notes: [NJNote]
    let onCancel: () -> Void
    let onInsert: (NJNote, String) -> Void

    @State private var searchText: String = ""
    @State private var linkTitle: String = ""
    @State private var selectedNoteID: String? = nil

    private var filteredNotes: [NJNote] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return notes }
        return notes.filter {
            $0.title.localizedCaseInsensitiveContains(q) ||
            $0.tabDomain.localizedCaseInsensitiveContains(q) ||
            $0.notebook.localizedCaseInsensitiveContains(q)
        }
    }

    var body: some View {
        NavigationStack {
            List(filteredNotes) { note in
                Button {
                    selectedNoteID = note.id.raw
                    if linkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        linkTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Linked Note" : note.title
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Untitled" : note.title)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Text("\(note.notebook) • \(note.tabDomain)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .navigationTitle("Link to Note")
            .searchable(text: $searchText, prompt: "Search notes")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 12) {
                    TextField("Link title", text: $linkTitle)
                        .textFieldStyle(.roundedBorder)
                    HStack {
                        Button("Cancel") {
                            onCancel()
                            dismiss()
                        }
                        .buttonStyle(.bordered)
                        Spacer()
                        Button("Insert") {
                            guard let selected = notes.first(where: { $0.id.raw == selectedNoteID }) else { return }
                            let title = linkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? (selected.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Linked Note" : selected.title)
                                : linkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                            onInsert(selected, title)
                            dismiss()
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedNoteID == nil)
                    }
                }
                .padding(12)
                .background(.ultraThinMaterial)
            }
        }
    }
}

private struct NJInternalViewLinkComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let suggestedDomain: String
    let onCancel: () -> Void
    let onInsert: (NJInternalLinkedViewConfig, String) -> Void

    @State private var linkTitle: String = ""
    @State private var filterText: String = ""
    @State private var matchMode: NJInternalLinkedViewMatchMode = .all
    @State private var useDateRange: Bool = false
    @State private var startDate: Date = Date()
    @State private var endDate: Date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Link") {
                    TextField("Link title", text: $linkTitle)
                    TextField("Filters (comma separated)", text: $filterText)
                    Picker("Match", selection: $matchMode) {
                        ForEach(NJInternalLinkedViewMatchMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("Date") {
                    Toggle("Filter by date", isOn: $useDateRange)
                    if useDateRange {
                        DatePicker("Start", selection: $startDate, displayedComponents: .date)
                        DatePicker("End", selection: $endDate, in: startDate..., displayedComponents: .date)
                    }
                }
            }
            .navigationTitle("Link to View")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onCancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        let trimmedTitle = linkTitle.trimmingCharacters(in: .whitespacesAndNewlines)
                        let trimmedFilter = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
                        let title = trimmedTitle.isEmpty ? (trimmedFilter.isEmpty ? "Filtered Blocks" : trimmedFilter) : trimmedTitle
                        let config = NJInternalLinkedViewConfig(
                            kind: .reconstructedManual,
                            title: title,
                            filterText: trimmedFilter,
                            matchMode: matchMode,
                            startMs: useDateRange ? startOfDayMs(startDate) : nil,
                            endMs: useDateRange ? endOfDayMs(endDate) : nil
                        )
                        onInsert(config, title)
                        dismiss()
                    }
                    .disabled(filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if filterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    filterText = suggestedDomain
                }
                if linkTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                   !suggestedDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    linkTitle = suggestedDomain
                }
            }
        }
    }

    private func startOfDayMs(_ date: Date) -> Int64 {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: date)
        return Int64(start.timeIntervalSince1970 * 1000.0)
    }

    private func endOfDayMs(_ date: Date) -> Int64 {
        let calendar = Calendar(identifier: .gregorian)
        let start = calendar.startOfDay(for: date)
        let endExclusive = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        return Int64(endExclusive.timeIntervalSince1970 * 1000.0) - 1
    }
}
