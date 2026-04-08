import SwiftUI
import UIKit

struct NJBlockHostView: View {
    let index: Int

    let createdAtMs: Int64?
    let domainPreview: String?
    let onEditTags: (() -> Void)?
    let onSaveCreatedAtMs: ((Int64) -> Void)?

    let inheritedTags: [String]
    let editableTags: [String]
    let tagJSON: String?
    let onSaveTagJSON: ((String) -> Void)?
    let tagSuggestionsProvider: ((String, Int) -> [String])?


    let goalPreview: String?
    let onAddGoal: (() -> Void)?

    let hasClipPDF: Bool
    let onOpenClipPDF: (() -> Void)?

    let protonHandle: NJProtonEditorHandle
    let onHydrateProton: () -> Void
    let onCommitProton: () -> Void
    let onMoveToClipboard: (() -> Void)?
    let headerBadgeSymbolName: String?
    let headerBadgeText: String?

    @Binding var isCollapsed: Bool

    let isFocused: Bool
    @Binding var attr: NSAttributedString
    @Binding var sel: NSRange
    let onFocus: () -> Void
    let onCtrlReturn: () -> Void
    let onDelete: () -> Void

    @State private var didHydrate = false
    @State private var editorHeight: CGFloat = 44
    
    @State private var showClipMenu: Bool = false
    @State private var showCreatedAtSheet: Bool = false
    @State private var createdAtDraft: Date = Date()


    @State private var showTagSheet: Bool = false
    @State private var tagDraft: [String] = []
    @State private var tagNewText: String = ""
    @State private var tagSuggestions: [String] = []

    init(
        index: Int,
        createdAtMs: Int64?,
        domainPreview: String?,
        onEditTags: (() -> Void)?,
        onSaveCreatedAtMs: ((Int64) -> Void)? = nil,
        goalPreview: String?,
        onAddGoal: (() -> Void)?,
        hasClipPDF: Bool,
        onOpenClipPDF: (() -> Void)?,
        protonHandle: NJProtonEditorHandle,
        isCollapsed: Binding<Bool>,
        isFocused: Bool,
        attr: Binding<NSAttributedString>,
        sel: Binding<NSRange>,
        onFocus: @escaping () -> Void,
        onCtrlReturn: @escaping () -> Void,
        onDelete: @escaping () -> Void,
        onHydrateProton: @escaping () -> Void,
        onCommitProton: @escaping () -> Void,
        onMoveToClipboard: (() -> Void)? = nil,
        headerBadgeSymbolName: String? = nil,
        headerBadgeText: String? = nil,
        inheritedTags: [String] = [],
        editableTags: [String] = [],
        tagJSON: String? = nil,
        onSaveTagJSON: ((String) -> Void)? = nil,
        tagSuggestionsProvider: ((String, Int) -> [String])? = nil
    ) {
        self.index = index
        self.createdAtMs = createdAtMs
        self.domainPreview = domainPreview
        self.onEditTags = onEditTags
        self.onSaveCreatedAtMs = onSaveCreatedAtMs
        self.inheritedTags = inheritedTags
        self.editableTags = editableTags
        self.tagJSON = tagJSON
        self.onSaveTagJSON = onSaveTagJSON
        self.tagSuggestionsProvider = tagSuggestionsProvider
        self.goalPreview = goalPreview
        self.onAddGoal = onAddGoal
        self.hasClipPDF = hasClipPDF
        self.onOpenClipPDF = onOpenClipPDF
        self.protonHandle = protonHandle
        self._isCollapsed = isCollapsed
        self.isFocused = isFocused
        self._attr = attr
        self._sel = sel
        self.onFocus = onFocus
        self.onCtrlReturn = onCtrlReturn
        self.onHydrateProton = onHydrateProton
        self.onCommitProton = onCommitProton
        self.onMoveToClipboard = onMoveToClipboard
        self.headerBadgeSymbolName = headerBadgeSymbolName
        self.headerBadgeText = headerBadgeText
        self.onDelete = onDelete
    }

    @ViewBuilder
    private func headerBadgeView() -> some View {
        if let headerBadgeText, !headerBadgeText.isEmpty {
            HStack(spacing: 5) {
                if let headerBadgeSymbolName, !headerBadgeSymbolName.isEmpty {
                    Image(systemName: headerBadgeSymbolName)
                }
                Text(headerBadgeText)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.blue)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(Color.blue.opacity(0.12))
            )
        }
    }

    private func oneLine(_ s: String) -> String {
        let t = s.replacingOccurrences(of: "\u{FFFC}", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return "" }
        return t.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private func normalizedTag(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func uniqPreserveOrder(_ xs: [String]) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for x in xs {
            let t = normalizedTag(x)
            if t.isEmpty { continue }
            if seen.contains(t) { continue }
            seen.insert(t)
            out.append(t)
        }
        return out
    }
    
    private func decodeTagJSON(_ s: String?) -> [String] {
        guard let s, let data = s.data(using: .utf8) else { return [] }
        guard let arr = (try? JSONSerialization.jsonObject(with: data)) as? [Any] else { return [] }
        return arr.compactMap { $0 as? String }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }


    private func encodeTagJSON(_ tags: [String]) -> String {
        let arr = uniqPreserveOrder(tags)
        if let data = try? JSONSerialization.data(withJSONObject: arr, options: []),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return "[]"
    }

    private func openTagSheet() {
        let decoded = decodeTagJSON(tagJSON)
        let base = editableTags.isEmpty ? decoded : editableTags
        tagDraft = uniqPreserveOrder(base)

//        if tagDraft.isEmpty {
//            let s = (tagJSON ?? "<nil>")
//            tagDraft = ["__DEBUG tagJSON=\(s.prefix(120))__"]
//        }

        tagNewText = ""
        tagSuggestions = []
        showTagSheet = true
    }

    private func openCreatedAtSheet() {
        let baseMs = (createdAtMs ?? 0) > 0 ? (createdAtMs ?? 0) : Int64(Date().timeIntervalSince1970 * 1000.0)
        createdAtDraft = Date(timeIntervalSince1970: TimeInterval(baseMs) / 1000.0)
        showCreatedAtSheet = true
    }

    private func replaceTag(_ from: String, with to: String) {
        guard !from.isEmpty, !to.isEmpty else { return }
        let updated = tagDraft.map { $0 == from ? to : $0 }
        tagDraft = uniqPreserveOrder(updated)
    }

    private func domainCandidates() -> [String] {
        let fromPreview = (domainPreview ?? "")
            .split(separator: ",")
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return uniqPreserveOrder(fromPreview)
    }

    private func goalCandidate() -> String {
        normalizedTag(goalPreview ?? "")
    }

    private func addDomainAutofill() {
        let candidates = domainCandidates()
        guard !candidates.isEmpty else { return }
        tagDraft = uniqPreserveOrder(tagDraft + candidates)
    }

    private func addGoalAutofill() {
        let goal = goalCandidate()
        guard !goal.isEmpty else { return }
        tagDraft = uniqPreserveOrder(tagDraft + [goal])
    }

    private func refreshTagSuggestions() {
        let q = normalizedTag(tagNewText)
        if q.isEmpty {
            tagSuggestions = []
            return
        }
        var local = uniqPreserveOrder(inheritedTags + tagDraft + domainCandidates() + [goalCandidate()])
            .filter { $0.lowercased().hasPrefix(q.lowercased()) }
        if let provider = tagSuggestionsProvider {
            let remote = provider(q, 12)
            local = uniqPreserveOrder(local + remote)
        }
        let existing = Set(tagDraft.map { $0.lowercased() })
        tagSuggestions = local.filter { !existing.contains($0.lowercased()) }
    }

    private func addTagFromInput() {
        let t = normalizedTag(tagNewText)
        guard !t.isEmpty else { return }
        tagDraft = uniqPreserveOrder(tagDraft + [t])
        tagNewText = ""
        tagSuggestions = []
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(spacing: 2) {
                Button { isCollapsed.toggle() } label: {
                    Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)

                Text("\(index)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .baselineOffset(-2)

                Spacer(minLength: 0)
            }
            .frame(width: 26)
            .padding(.top, 4)

            ZStack(alignment: .trailing) {
                ZStack(alignment: .topLeading) {
                    VStack(alignment: .leading, spacing: 6) {
                        if isCollapsed {
                            HStack(alignment: .center, spacing: 8) {
                                Text(oneLine(attr.string))
                                    .font(.body.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                headerBadgeView()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture { onFocus() }
                        } else {
                            HStack(alignment: .center, spacing: 8) {
                                if let ms = createdAtMs, ms > 0 {
                                    Text(dateLine(ms))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.top, 2)
                                }
                                Spacer(minLength: 0)
                                headerBadgeView()
                            }

                            NJProtonEditorView(
                                initialAttributedText: attr,
                                initialSelectedRange: sel,
                                snapshotAttributedText: $attr,
                                snapshotSelectedRange: $sel,
                                measuredHeight: $editorHeight,
                                handle: protonHandle
                            )
                            .frame(minHeight: editorHeight)
                            .contentShape(Rectangle())
                            .onTapGesture { onFocus() }
                            .onAppear {
                                if !isCollapsed && !didHydrate {
                                    didHydrate = true
                                    DispatchQueue.main.async { onHydrateProton() }
                                }
                            }

                            HStack {
                                Spacer(minLength: 0)
                                if let raw = domainPreview {
                                    let s = domainBottom3(raw)
                                    if !s.isEmpty {
                                        Text(s)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .onTapGesture(count: 2) { onEditTags?() }
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }
                    .padding(.trailing, 44)
                }

                VStack {
                    Menu {
                        let d = oneLine(domainPreview ?? "")
                        let g = oneLine(goalPreview ?? "")

                        Button {
                            openTagSheet()
                        } label: {
                            Label(d.isEmpty ? "Domain: (none)" : "Domain: \(d)", systemImage: "tag")
                        }

                        .disabled(false)

                        Button {
                            openCreatedAtSheet()
                        } label: {
                            Label(createdAtSummary(), systemImage: "calendar")
                        }
                        .disabled(onSaveCreatedAtMs == nil)

                        if g.isEmpty {
                            Label("Goal: (none)", systemImage: "target").foregroundStyle(.secondary)
                        } else {
                            Label("Goal: \(g)", systemImage: "target").foregroundStyle(.secondary)
                        }

                        Button { onAddGoal?() } label: {
                            Label("Add Goal…", systemImage: "plus.circle")
                        }
                        .disabled(onAddGoal == nil)

                        Divider()
                        Button { onMoveToClipboard?() } label: {
                            Label("Move Block…", systemImage: "arrow.up.doc")
                        }
                        .disabled(onMoveToClipboard == nil)

                        Divider()
                        Button {
                            showClipMenu = true
                        } label: {
                            Label(hasClipPDF ? "Clip…" : "Clip: (none)", systemImage: "doc")
                        }
                        .disabled(onOpenClipPDF == nil)

                        Divider()

                        Button(role: .destructive) { onDelete() } label: {
                            Label("Delete Block", systemImage: "trash")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .symbolRenderingMode(.monochrome)
                            .foregroundStyle(.primary)
                            .tint(.primary)
                            .font(.system(size: 18))
                            .frame(width: 34, height: 34)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                }
                .frame(maxHeight: .infinity, alignment: isCollapsed ? .center : .bottom)
                .padding(.trailing, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onFocus() }
        .padding(.vertical, isCollapsed ? 2 : 6)
        
        
        .sheet(isPresented: $showTagSheet) {
            NavigationStack {
                List {
                    if !inheritedTags.isEmpty {
                        Section("Inherited") {
                            ForEach(uniqPreserveOrder(inheritedTags), id: \.self) { t in
                                HStack {
                                    Text(t)
                                    Spacer()
                                    Image(systemName: "lock.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    Section("Block Tags") {
                        let goal = goalCandidate()
                        let domains = domainCandidates()
                        if !goal.isEmpty || !domains.isEmpty {
                            HStack(spacing: 10) {
                                if !domains.isEmpty {
                                    Button(domains.count == 1 ? "Autofill Domain" : "Autofill Domains") {
                                        addDomainAutofill()
                                    }
                                    .buttonStyle(.bordered)
                                }
                                if !goal.isEmpty {
                                    Button("Autofill Goal") {
                                        addGoalAutofill()
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        let hasRemind = tagDraft.contains("#REMIND")
                        let hasPlanning = tagDraft.contains("#PLANNING")
                        if hasRemind || hasPlanning {
                            HStack(spacing: 10) {
                                if hasRemind {
                                    Button("Reminded") {
                                        replaceTag("#REMIND", with: "#REMINDED")
                                    }
                                    .buttonStyle(.bordered)
                                }
                                if hasPlanning {
                                    Button("Planned") {
                                        replaceTag("#PLANNING", with: "#PLANNED")
                                    }
                                    .buttonStyle(.bordered)
                                }
                            }
                        }

                        if tagDraft.isEmpty {
                            Text("(none)")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(tagDraft, id: \.self) { t in
                                Text(t)
                            }
                            .onDelete { idx in
                                tagDraft.remove(atOffsets: idx)
                            }
                        }

                        HStack(spacing: 10) {
                            TextField("Add tag", text: $tagNewText)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                                .onChange(of: tagNewText) { _, _ in
                                    refreshTagSuggestions()
                                }
                                .onSubmit {
                                    addTagFromInput()
                                }
                            Button("Add") {
                                addTagFromInput()
                            }
                            .disabled(normalizedTag(tagNewText).isEmpty)
                        }

                        if !tagSuggestions.isEmpty {
                            ForEach(tagSuggestions.prefix(6), id: \.self) { s in
                                Button {
                                    tagDraft = uniqPreserveOrder(tagDraft + [s])
                                    tagNewText = ""
                                    tagSuggestions = []
                                } label: {
                                    HStack {
                                        Text(s)
                                            .foregroundStyle(.primary)
                                        Spacer()
                                        Image(systemName: "sparkles")
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .navigationTitle("Tags")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showTagSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let json = encodeTagJSON(tagDraft)
                            onSaveTagJSON?(json)
                            showTagSheet = false
                        }
                        .disabled(onSaveTagJSON == nil)
                    }
                }
            }
        }
        .sheet(isPresented: $showCreatedAtSheet) {
            NavigationStack {
                Form {
                    Section("Created At") {
                        DatePicker(
                            "Block date",
                            selection: $createdAtDraft,
                            displayedComponents: [.date, .hourAndMinute]
                        )
                        Text("Use a future timestamp if you want this block to participate in date-sensitive flows later.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("Edit Block Date")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showCreatedAtSheet = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let ms = Int64(createdAtDraft.timeIntervalSince1970 * 1000.0)
                            onSaveCreatedAtMs?(max(1, ms))
                            showCreatedAtSheet = false
                        }
                        .disabled(onSaveCreatedAtMs == nil)
                    }
                }
            }
        }
        
        .confirmationDialog("Clip", isPresented: $showClipMenu, titleVisibility: .visible) {
            Button("Open PDF") { onOpenClipPDF?() }
                .disabled(onOpenClipPDF == nil)
        }

        .onChange(of: isCollapsed) { v in
            if v {
                didHydrate = false
                protonHandle.invalidateHydration()
            } else {
                if !didHydrate {
                    didHydrate = true
                    DispatchQueue.main.async { onHydrateProton() }
                }
            }
        }
    }

    private func dateLine(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func createdAtSummary() -> String {
        guard let ms = createdAtMs, ms > 0 else { return "Created At: (none)" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale.current
        f.dateStyle = .medium
        f.timeStyle = .short
        return "Created At: \(f.string(from: d))"
    }

    private func domainBottom3(_ raw: String) -> String {
        let parts = raw
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        if parts.isEmpty { return "" }
        if parts.count <= 3 { return parts.joined(separator: ", ") }
        return parts.prefix(3).joined(separator: ", ") + ", …"
    }
}
