import SwiftUI
import PhotosUI

struct NJOutlineDetailView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    let outlineID: String

    @State private var detailNodeID: String? = nil
    @State private var showDetailSheet = false
    @State private var showDeleteBlocked = false
    @State private var isReorderMode = false
    @FocusState private var focusedNodeID: String?

    private var rows: [NJOutlineNodeRow] {
        outline.nodeRows(outlineID: outlineID)
    }

    private var effectiveSelectedNodeID: String? {
        if let focused = focusedNodeID,
           rows.contains(where: { $0.node.nodeID == focused }) {
            return focused
        }
        if let selected = store.selectedOutlineNodeID,
           rows.contains(where: { $0.node.nodeID == selected }) {
            return selected
        }
        return rows.first?.node.nodeID
    }

    private var outlineTitle: String {
        let t = outline.outlines.first(where: { $0.outlineID == outlineID })?.title ?? ""
        let trimmed = t.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Outline" : trimmed
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar()
            Divider()
            if rows.isEmpty {
                ContentUnavailableView("No nodes", systemImage: "list.bullet")
            } else {
                List {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, row in
                        nodeRow(row)
                            .font(.system(size: 12))
                            .listRowInsets(EdgeInsets(top: 0, leading: 6, bottom: 0, trailing: 6))
                            .listRowBackground(idx.isMultiple(of: 2) ? Color.white : Color(UIColor.systemGray6))
                    }
                    .onMove(perform: moveRows)
                }
                .listStyle(.plain)
                .environment(\.defaultMinListRowHeight, 28)
                .environment(\.editMode, .constant(isReorderMode ? .active : .inactive))
            }
        }
        .onAppear {
            outline.loadNodes(outlineID: outlineID)
        }
        .onChange(of: outline.nodes) { _, _ in
            guard store.selectedOutlineNodeID == nil else { return }
            if let first = rows.first?.node.nodeID {
                store.selectedOutlineNodeID = first
            }
        }
        .onChange(of: focusedNodeID) { _, newID in
            guard let newID else { return }
            store.selectedOutlineNodeID = newID
        }
        .sheet(isPresented: $showDetailSheet) {
            NJOutlineNodeDetailSheet(outline: outline, nodeID: detailNodeID ?? "")
                .environmentObject(store)
        }
        .alert("Cannot Delete Node", isPresented: $showDeleteBlocked) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("This node has dependencies. Remove child nodes/references first.")
        }
    }

    private func topBar() -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(outlineTitle)
                .font(.headline)
                .lineLimit(1)

            HStack(spacing: 8) {
                iconButton("plus") {
                    let n = outline.createRootNode(outlineID: outlineID)
                    store.selectedOutlineNodeID = n.nodeID
                }

            if let nodeID = effectiveSelectedNodeID {
                iconButton("plus.square.on.square") {
                    if let n = outline.createSiblingNode(nodeID: nodeID) {
                        store.selectedOutlineNodeID = n.nodeID
                    }
                    }
                    iconButton("point.down.left.to.point.up.right.curvepath") {
                        if let n = outline.createChildNode(nodeID: nodeID) {
                            store.selectedOutlineNodeID = n.nodeID
                        }
                    }
                    iconButton("arrow.up.left") {
                        outline.promote(nodeID: nodeID)
                    }
                    iconButton("arrow.down.right") {
                        outline.demote(nodeID: nodeID)
                    }
                    iconButton("trash") {
                        if outline.canDeleteNode(nodeID: nodeID) {
                            outline.deleteNode(nodeID: nodeID)
                            if store.selectedOutlineNodeID == nodeID {
                                store.selectedOutlineNodeID = nil
                            }
                        } else {
                            showDeleteBlocked = true
                        }
                    }
                }

                iconButton(isReorderMode ? "checkmark" : "line.3.horizontal") {
                    isReorderMode.toggle()
                }

                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color(UIColor.systemBackground))
    }

    private func iconButton(_ systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 12, weight: .semibold))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    private func nodeRow(_ row: NJOutlineNodeRow) -> some View {
        let n = row.node
        return HStack(spacing: 0) {
            Button {
                if n.isChecklist {
                    outline.toggleChecked(nodeID: n.nodeID)
                } else {
                    outline.toggleChecklist(nodeID: n.nodeID)
                }
            } label: {
                Image(systemName: n.isChecklist ? (n.isChecked ? "checkmark.circle.fill" : "circle") : "circle")
                    .foregroundColor(n.isChecked ? .accentColor : .secondary)
                    .frame(width: 18)
            }
            .buttonStyle(.plain)

            Color.clear.frame(width: CGFloat(row.depth) * 14)

            Group {
                if hasChildren(n.nodeID) {
                    Button {
                        outline.toggleCollapsed(nodeID: n.nodeID)
                    } label: {
                        Image(systemName: n.isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                } else {
                    Color.clear
                }
            }
            .frame(width: 14)

            TextField(
                "Untitled",
                text: Binding(
                    get: { n.title },
                    set: {
                        store.selectedOutlineNodeID = n.nodeID
                        outline.updateNodeTitle(nodeID: n.nodeID, title: $0)
                    }
                )
            )
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .padding(.leading, 4)
            .focused($focusedNodeID, equals: n.nodeID)

            Spacer(minLength: 0)

            if !n.domainTag.isEmpty {
                Text(n.domainTag)
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedOutlineNodeID = n.nodeID
            focusedNodeID = n.nodeID
        }
        .onTapGesture(count: 2) {
            store.selectedOutlineNodeID = n.nodeID
            focusedNodeID = n.nodeID
            detailNodeID = n.nodeID
            showDetailSheet = true
        }
        .padding(.vertical, 0)
    }

    private func hasChildren(_ nodeID: String) -> Bool {
        outline.nodes.contains(where: { $0.parentNodeID == nodeID })
    }

    private func moveRows(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first,
              sourceIndex >= 0,
              sourceIndex < rows.count else { return }

        let moving = rows[sourceIndex].node
        var reordered = rows
        reordered.move(fromOffsets: source, toOffset: destination)
        guard let movedIndex = reordered.firstIndex(where: { $0.node.nodeID == moving.nodeID }) else { return }

        let sameParent = reordered.filter { $0.node.parentNodeID == moving.parentNodeID }
        guard let siblingIndex = sameParent.firstIndex(where: { $0.node.nodeID == moving.nodeID }) else { return }

        outline.reorderNodeWithinParent(nodeID: moving.nodeID, toSiblingIndex: siblingIndex)
        store.selectedOutlineNodeID = moving.nodeID
        focusedNodeID = moving.nodeID
    }
}

private struct NJOutlineNodeDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    let nodeID: String

    @StateObject private var persistence = NJReconstructedNotePersistence(spec: .all(limit: 1))

    @State private var titleDraft: String = ""
    @State private var commentDraft: String = ""
    @State private var domainDraft: String = ""

    @State private var metaExpanded = true
    @State private var commentDomainExpanded = true
    @State private var filterExpanded = true

    @State private var filterOp: String = "AND"
    @State private var rules: [NJOutlineFilterRule] = []
    @State private var fromEnabled = false
    @State private var toEnabled = false
    @State private var fromDate = Date()
    @State private var toDate = Date()

    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var focusedHandle: NJProtonEditorHandle? = nil

    private var node: NJOutlineNodeRecord? { outline.node(nodeID) }
    private var hasAnyFilter: Bool {
        let hasRules = rules.contains { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return hasRules || fromEnabled || toEnabled
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if node != nil {
                    metadataSection()
                    Divider()
                    filterSection()
                    Divider()
                    reconstructedList()
                } else {
                    ContentUnavailableView("Node not found", systemImage: "exclamationmark.triangle")
                }
            }
            .font(.system(size: 12))
            .navigationTitle(titleDraft.isEmpty ? "Node" : titleDraft)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let h = focusedHandle ?? persistence.blocks.first(where: { $0.id == persistence.focusedBlockID })?.protonHandle {
                    NJProtonFloatingFormatBar(handle: h, pickedPhotoItem: $pickedPhotoItem)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { saveAll() } label: {
                        Image(systemName: "checkmark")
                    }
                }
            }
            .onAppear {
                persistence.configure(store: store)
                syncDrafts()
                loadFilterFromNode()
                refreshReconstructed()
            }
            .onDisappear {
                if let id = persistence.focusedBlockID {
                    persistence.forceEndEditingAndCommitNow(id)
                }
            }
        }
    }

    private func metadataSection() -> some View {
        VStack(spacing: 6) {
            HStack {
                Button {
                    metaExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: metaExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Node")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if metaExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Title", text: $titleDraft)
                        .textFieldStyle(.roundedBorder)

                    VStack(spacing: 6) {
                        HStack {
                            Button {
                                commentDomainExpanded.toggle()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: commentDomainExpanded ? "chevron.down" : "chevron.right")
                                        .font(.system(size: 10, weight: .semibold))
                                    Text("Comment & Domain")
                                        .font(.system(size: 12, weight: .semibold))
                                }
                            }
                            .buttonStyle(.plain)
                            Spacer()
                        }

                        if commentDomainExpanded {
                            TextField("Domain", text: $domainDraft)
                                .textFieldStyle(.roundedBorder)
                            TextEditor(text: $commentDraft)
                                .font(.system(size: 12))
                                .frame(minHeight: 80)
                                .padding(6)
                                .background(Color(UIColor.secondarySystemBackground))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color(UIColor.separator), lineWidth: 0.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func filterSection() -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    filterExpanded.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: filterExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                        Text("Filters")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .buttonStyle(.plain)

                Spacer()

                Button {
                    rules.append(NJOutlineFilterRule(field: .domain, value: ""))
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(.plain)

                Button {
                    refreshReconstructed()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.top, 8)

            if filterExpanded {
                VStack(spacing: 8) {
                    Picker("Logic", selection: $filterOp) {
                        Text("AND").tag("AND")
                        Text("OR").tag("OR")
                    }
                    .pickerStyle(.segmented)

                    ForEach(Array(rules.enumerated()), id: \.element.id) { idx, _ in
                        HStack(spacing: 8) {
                            Picker(
                                "Field",
                                selection: Binding(
                                    get: { rules[idx].field },
                                    set: { rules[idx].field = $0 }
                                )
                            ) {
                                ForEach(NJOutlineFilterRule.Field.allCases, id: \.self) { field in
                                    Text(field.label).tag(field)
                                }
                            }
                            .frame(width: 110)

                            TextField(
                                rules[idx].field == .domain ? "Domain contains" : "Tag contains",
                                text: Binding(
                                    get: { rules[idx].value },
                                    set: { rules[idx].value = $0 }
                                )
                            )
                            .textFieldStyle(.roundedBorder)

                            Button {
                                rules.remove(at: idx)
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    HStack(spacing: 10) {
                        Toggle("From", isOn: $fromEnabled)
                            .font(.system(size: 12))
                        if fromEnabled {
                            DatePicker("", selection: $fromDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }

                    HStack(spacing: 10) {
                        Toggle("To", isOn: $toEnabled)
                            .font(.system(size: 12))
                        if toEnabled {
                            DatePicker("", selection: $toDate, displayedComponents: .date)
                                .labelsHidden()
                        }
                        Spacer()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
        }
    }

    private func reconstructedList() -> some View {
        List {
            if !hasAnyFilter {
                Text("Add at least one filter to load results")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else if persistence.blocks.isEmpty {
                Text("No matches")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            } else {
                ForEach(persistence.blocks, id: \.id) { b in
                    reconstructedRow(b)
                }
            }
        }
        .listStyle(.plain)
    }

    private func reconstructedRow(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let id = b.id
        let h = b.protonHandle
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
            index: 1,
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
                focusedHandle = h
                h.focus()
            },
            onCtrlReturn: { persistence.forceEndEditingAndCommitNow(id) },
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
            onSaveTagJSON: onSaveTags,
            tagSuggestionsProvider: { prefix, limit in
                store.notes.listTagSuggestions(prefix: prefix, limit: limit)
            }
        )
        .listRowInsets(EdgeInsets(top: 2, leading: 10, bottom: 2, trailing: 10))
        .listRowBackground(reconstructedBackground(blockID: b.blockID))
        .listRowSeparator(.hidden)
        .onAppear { persistence.hydrateProton(id) }
    }

    private func reconstructedBackground(blockID: String) -> Color {
        if let domainColor = persistence.rowBackgroundColor(blockID: blockID) {
            return domainColor
        }
        return Color(red: 0.90, green: 0.95, blue: 1.0)
    }

    private func bindingCollapsed(_ id: UUID) -> Binding<Bool> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { persistence.setCollapsed(id: id, collapsed: $0) }
        )
    }

    private func refreshReconstructed() {
        let cleanRules = rules.filter { !$0.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        if cleanRules.isEmpty && !fromEnabled && !toEnabled {
            persistence.updateSpec(.custom(title: titleDraft.isEmpty ? "Node" : titleDraft, ids: [], limit: 1, newestFirst: true))
            persistence.reload(makeHandle: { NJProtonEditorHandle() })
            return
        }

        let ids = outline.reconstructedBlockIDs(
            rules: cleanRules,
            op: filterOp,
            startMs: fromEnabled ? startOfDayMs(fromDate) : nil,
            endMs: toEnabled ? endOfDayMs(toDate) : nil,
            limit: 300
        )
        persistence.updateSpec(.custom(title: titleDraft.isEmpty ? "Node" : titleDraft, ids: ids, limit: max(ids.count, 1), newestFirst: true))
        persistence.reload(makeHandle: { NJProtonEditorHandle() })
    }

    private func saveAll() {
        outline.updateNodeTitle(nodeID: nodeID, title: titleDraft)
        outline.updateNodeDomain(nodeID: nodeID, domainTag: domainDraft)
        outline.updateNodeComment(nodeID: nodeID, comment: commentDraft)
        outline.setNodeFilter(nodeID: nodeID, filter: makeFilterObject())
        dismiss()
    }

    private func syncDrafts() {
        guard let n = node else { return }
        titleDraft = n.title
        commentDraft = n.comment
        domainDraft = n.domainTag
    }

    private func loadFilterFromNode() {
        let f = outline.nodeFilter(nodeID: nodeID)
        filterOp = ((f["op"] as? String) ?? "AND").uppercased() == "OR" ? "OR" : "AND"

        if let arr = f["rules"] as? [[String: Any]] {
            let parsed = arr.compactMap { obj -> NJOutlineFilterRule? in
                guard let fieldRaw = obj["field"] as? String,
                      let field = NJOutlineFilterRule.Field(rawValue: fieldRaw),
                      let value = obj["value"] as? String else { return nil }
                return NJOutlineFilterRule(field: field, value: value)
            }
            rules = parsed
        } else {
            rules = []
            let legacyDomain = (f["domain"] as? String) ?? ""
            let legacyTagsCSV = (f["tags"] as? String) ?? ""
            if !legacyDomain.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                rules.append(NJOutlineFilterRule(field: .domain, value: legacyDomain))
            }
            let tags = legacyTagsCSV
                .split(separator: ",")
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            for t in tags {
                rules.append(NJOutlineFilterRule(field: .tag, value: t))
            }
        }

        if let from = asInt64(f["start_ms"]) {
            fromEnabled = true
            fromDate = Date(timeIntervalSince1970: TimeInterval(from) / 1000.0)
        } else {
            fromEnabled = false
        }
        if let to = asInt64(f["end_ms"]) {
            toEnabled = true
            toDate = Date(timeIntervalSince1970: TimeInterval(to) / 1000.0)
        } else {
            toEnabled = false
        }
    }

    private func makeFilterObject() -> [String: Any] {
        var out: [String: Any] = [
            "op": filterOp,
            "rules": rules.map { ["field": $0.field.rawValue, "value": $0.value] }
        ]
        if fromEnabled {
            out["start_ms"] = startOfDayMs(fromDate)
        }
        if toEnabled {
            out["end_ms"] = endOfDayMs(toDate)
        }
        return out
    }

    private func startOfDayMs(_ d: Date) -> Int64 {
        let day = Calendar.current.startOfDay(for: d)
        return Int64(day.timeIntervalSince1970 * 1000.0)
    }

    private func endOfDayMs(_ d: Date) -> Int64 {
        let start = Calendar.current.startOfDay(for: d)
        let next = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? d
        return Int64(next.timeIntervalSince1970 * 1000.0) - 1
    }

    private func asInt64(_ value: Any?) -> Int64? {
        if let n = value as? Int64 { return n }
        if let n = value as? Int { return Int64(n) }
        if let n = value as? Double { return Int64(n) }
        if let n = value as? NSNumber { return n.int64Value }
        return nil
    }
}
