import SwiftUI
import PhotosUI

struct NJGoalDetailWorkspaceView: View {
    @EnvironmentObject var store: AppStore
    let goalID: String

    @StateObject private var persistence = NJGoalDetailPersistence()
    @State private var loaded = false
    @State private var showClipboardAttach = false
    @State private var headerExpanded = false
    @State private var goalTagDraft = ""
    @State private var commentDraft = ""
    @State private var showArchiveConfirm = false
    @State private var showTagConflict = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var focusedHandle: NJProtonEditorHandle? = nil
    @State private var allGoalTags: [String] = []
    @State private var goalTagSuggestions: [String] = []

    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            content()
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let h = focusedHandle ?? persistence.focusedHandle {
                NJProtonFloatingFormatBar(handle: h, pickedPhotoItem: $pickedPhotoItem)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
            }
        }
        .onAppear { onLoadOnce() }
        .onChange(of: goalID) { _, _ in onLoadOnce(force: true) }
        .onChange(of: persistence.goalTag) { _, newValue in
            if !headerExpanded {
                goalTagDraft = newValue
            }
        }
        .onChange(of: goalTagDraft) { _, _ in
            refreshGoalTagSuggestions()
        }
        .onChange(of: persistence.goalComment) { _, newValue in
            if !headerExpanded {
                commentDraft = newValue
            }
        }
        .sheet(isPresented: $showClipboardAttach) {
            NavigationStack {
                NJGoalClipboardAttachSheet(goalID: goalID)
                    .environmentObject(store)
            }
        }
        .alert("Archive Goal?", isPresented: $showArchiveConfirm) {
            Button("Archive", role: .destructive) {
                persistence.archiveGoal()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will move the goal to Archive.")
        }
        .alert("Goal Tag Already Exists", isPresented: $showTagConflict) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Please choose a unique goal tag.")
        }
    }

    private func header() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(persistence.goalName.isEmpty ? "Untitled" : persistence.goalName)
                    .font(.title3)
                    .fontWeight(.semibold)
                Spacer()
                Button {
                    persistence.reload(makeHandle: makeHandle)
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                Button {
                    persistence.addProgressBlock(makeHandle: makeHandle)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.bordered)
                Button {
                    showClipboardAttach = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                }
                .buttonStyle(.bordered)
                Button(role: .destructive) {
                    if let id = persistence.focusedProgressID {
                        persistence.deleteProgressBlock(id)
                    }
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.bordered)
            }

            HStack(alignment: .center, spacing: 12) {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        headerExpanded.toggle()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: headerExpanded ? "chevron.down" : "chevron.right")
                        Text(statusText())
                            .font(.caption)
                    }
                }
                .buttonStyle(.bordered)

                if !persistence.goalTag.isEmpty {
                    Text(persistence.goalTag)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else {
                    Text("No goal tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Button(role: .destructive) {
                    showArchiveConfirm = true
                } label: {
                    Text("Archive")
                }
                .buttonStyle(.bordered)
            }

            if headerExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        TextField("Set goal tag (e.g. g.zz.adhd.efinitiation)", text: $goalTagDraft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled(true)
                            .textFieldStyle(.roundedBorder)

                        Button("Save") {
                            let trimmed = goalTagDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !persistence.canUseGoalTag(trimmed) {
                                showTagConflict = true
                                return
                            }
                            persistence.updateGoalTag(trimmed)
                        }
                        .buttonStyle(.bordered)
                    }
                    if !goalTagSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(goalTagSuggestions, id: \.self) { t in
                                Button {
                                    goalTagDraft = t
                                    goalTagSuggestions = []
                                } label: {
                                    Text(t)
                                        .font(.caption)
                                        .foregroundStyle(.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 6)
                                        .padding(.horizontal, 8)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(UIColor.secondarySystemBackground))
                        )
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Comment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextEditor(text: $commentDraft)
                            .frame(minHeight: 90)
                            .padding(6)
                            .background(Color(UIColor.secondarySystemBackground))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color(UIColor.separator), lineWidth: 0.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        HStack {
                            Spacer()
                            Button("Save Comment") {
                                persistence.updateGoalComment(commentDraft)
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    if !persistence.domainTags.isEmpty {
                        Text("Domains: \(persistence.domainTags.joined(separator: ", "))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }

                    Text("Created \(dateString(persistence.createdAtMs)) · Updated \(dateString(persistence.updatedAtMs))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .onAppear {
            if goalTagDraft.isEmpty {
                goalTagDraft = persistence.goalTag
            }
            if commentDraft.isEmpty {
                commentDraft = persistence.goalComment
            }
        }
    }

    private func content() -> some View {
        List {
            ForEach(persistence.combinedBlocks) { item in
                if item.source == .progress {
                    progressRow(blockID: item.blockID)
                } else {
                    timelineRow(blockID: item.blockID)
                }
            }
        }
        .listStyle(.plain)
    }

    private func progressRow(blockID: String) -> some View {
        guard let i = persistence.progressIndex(for: blockID) else { return AnyView(EmptyView()) }
        let b = persistence.progressBlocks[i]
        let id = b.id
        let h = b.protonHandle
        let inherited = inheritedGoalTags()

        let view = NJBlockHostView(
            index: (persistence.progressBlocks.firstIndex(where: { $0.id == id }) ?? 0) + 1,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: nil,
            goalPreview: b.goalPreview,
            onAddGoal: { },
            hasClipPDF: false,
            onOpenClipPDF: { },
            protonHandle: h,
            isCollapsed: persistence.bindingProgressCollapsed(id),
            isFocused: id == persistence.focusedProgressID,
            attr: persistence.bindingProgressAttr(id),
            sel: persistence.bindingProgressSel(id),
            onFocus: {
                persistence.focusProgress(id)
                focusedHandle = h
            },
            onCtrlReturn: { persistence.forceCommitProgress(id) },
            onDelete: { persistence.deleteProgressBlock(id) },
            onHydrateProton: { persistence.hydrateProgress(id) },
            onCommitProton: { persistence.commitProgress(id) },
            inheritedTags: inherited,
            editableTags: [],
            tagJSON: b.tagJSON,
            onSaveTagJSON: { json in
                let merged = mergeTagJSONWithGoal(json: json, goalTag: persistence.goalTag)
                persistence.setProgressTagJSON(blockID: b.blockID, tagJSON: merged)
            }
        )
        .id(id)
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(Color.green.opacity(0.08))
        .listRowSeparator(.hidden)
        .onAppear { persistence.hydrateProgress(id) }
        return AnyView(view)
    }

    private func timelineRow(blockID: String) -> some View {
        guard let i = persistence.timelineIndex(for: blockID) else { return AnyView(EmptyView()) }
        let b = persistence.timelineBlocks[i]
        let id = b.id
        let h = b.protonHandle
        let inherited = inheritedGoalTags()

        let view = NJBlockHostView(
            index: (persistence.timelineBlocks.firstIndex(where: { $0.id == id }) ?? 0) + 1,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: nil,
            goalPreview: b.goalPreview,
            onAddGoal: { },
            hasClipPDF: false,
            onOpenClipPDF: { },
            protonHandle: h,
            isCollapsed: persistence.bindingTimelineCollapsed(id),
            isFocused: id == persistence.focusedTimelineID,
            attr: persistence.bindingTimelineAttr(id),
            sel: persistence.bindingTimelineSel(id),
            onFocus: {
                persistence.focusTimeline(id)
                focusedHandle = h
            },
            onCtrlReturn: { persistence.forceCommitTimeline(id) },
            onDelete: { },
            onHydrateProton: { persistence.hydrateTimeline(id) },
            onCommitProton: { persistence.commitTimeline(id) },
            inheritedTags: inherited,
            editableTags: [],
            tagJSON: b.tagJSON,
            onSaveTagJSON: { json in
                let merged = mergeTagJSONWithGoal(json: json, goalTag: persistence.goalTag)
                persistence.setTimelineTagJSON(blockID: b.blockID, tagJSON: merged)
            }
        )
        .id(id)
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowBackground(Color.blue.opacity(0.08))
        .listRowSeparator(.hidden)
        .onAppear { persistence.hydrateTimeline(id) }
        return AnyView(view)
    }

    private func makeHandle() -> NJProtonEditorHandle {
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
            guard let persistence, let id = h?.ownerBlockUUID else { return }
            if persistence.progressBlocks.contains(where: { $0.id == id }) {
                persistence.markProgressDirty(id)
            } else if persistence.timelineBlocks.contains(where: { $0.id == id }) {
                persistence.markTimelineDirty(id)
            }
        }
        h.onSnapshot = { [weak persistence, weak h] _, _ in
            guard let persistence, let id = h?.ownerBlockUUID else { return }
            if persistence.progressBlocks.contains(where: { $0.id == id }) {
                persistence.markProgressDirty(id, schedule: false)
            } else if persistence.timelineBlocks.contains(where: { $0.id == id }) {
                persistence.markTimelineDirty(id, schedule: false)
            }
        }
        return h
    }

    private func onLoadOnce(force: Bool = false) {
        if loaded && !force { return }
        loaded = true
        headerExpanded = false
        persistence.configure(store: store, goalID: goalID)
        persistence.reload(makeHandle: makeHandle)
        goalTagDraft = persistence.goalTag
        commentDraft = persistence.goalComment
        allGoalTags = loadActiveGoalTags()
        refreshGoalTagSuggestions()
        if focusedHandle == nil {
            if let first = persistence.progressBlocks.first {
                persistence.focusProgress(first.id)
                focusedHandle = first.protonHandle
            } else if let first = persistence.timelineBlocks.first {
                persistence.focusTimeline(first.id)
                focusedHandle = first.protonHandle
            }
        }
    }

    private func dateString(_ ms: Int64) -> String {
        if ms <= 0 { return "-" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func loadActiveGoalTags() -> [String] {
        let goals = store.notes.listGoalSummaries()
        var set = Set<String>()
        for g in goals {
            let t = g.goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
            if t.isEmpty { continue }
            let s = g.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            if ["archive", "archived", "done", "closed"].contains(s) { continue }
            set.insert(t)
        }
        return Array(set).sorted()
    }

    private func refreshGoalTagSuggestions() {
        let q = goalTagDraft.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty {
            goalTagSuggestions = []
            return
        }
        let filtered = allGoalTags.filter { $0.lowercased().hasPrefix(q) }
        goalTagSuggestions = Array(filtered.prefix(6))
    }

    private func inheritedGoalTags() -> [String] {
        let t = persistence.goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? [] : [t]
    }

    private func mergeTagJSONWithGoal(json: String, goalTag: String) -> String {
        let trimmedGoal = goalTag.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedGoal.isEmpty { return json }
        let decoded: [String] = {
            guard let data = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()
        var merged = decoded
        if !merged.contains(where: { $0.caseInsensitiveCompare(trimmedGoal) == .orderedSame }) {
            merged.append(trimmedGoal)
        }
        if let data = try? JSONSerialization.data(withJSONObject: merged),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return json
    }
    private func statusText() -> String {
        let s = persistence.status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["archive", "archived", "done", "closed"].contains(s) { return "Archive" }
        if persistence.goalTag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Seedling" }
        return "In Progress"
    }
}
