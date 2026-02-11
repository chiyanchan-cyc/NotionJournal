import SwiftUI
import UIKit

struct NJBlockHostView: View {
    let index: Int

    let createdAtMs: Int64?
    let domainPreview: String?
    let onEditTags: (() -> Void)?

    let inheritedTags: [String]
    let editableTags: [String]
    let tagJSON: String?
    let onSaveTagJSON: ((String) -> Void)?


    let goalPreview: String?
    let onAddGoal: (() -> Void)?

    let hasClipPDF: Bool
    let onOpenClipPDF: (() -> Void)?

    let protonHandle: NJProtonEditorHandle
    let onHydrateProton: () -> Void
    let onCommitProton: () -> Void
    let onMoveToClipboard: (() -> Void)?

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


    @State private var showTagSheet: Bool = false
    @State private var tagDraft: [String] = []
    @State private var tagNewText: String = ""

    init(
        index: Int,
        createdAtMs: Int64?,
        domainPreview: String?,
        onEditTags: (() -> Void)?,
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
        inheritedTags: [String] = [],
        editableTags: [String] = [],
        tagJSON: String? = nil,
        onSaveTagJSON: ((String) -> Void)? = nil
    ) {
        self.index = index
        self.createdAtMs = createdAtMs
        self.domainPreview = domainPreview
        self.onEditTags = onEditTags
        self.inheritedTags = inheritedTags
        self.editableTags = editableTags
        self.tagJSON = tagJSON
        self.onSaveTagJSON = onSaveTagJSON
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
        self.onDelete = onDelete
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
        showTagSheet = true
    }

    private func replaceTag(_ from: String, with to: String) {
        guard !from.isEmpty, !to.isEmpty else { return }
        let updated = tagDraft.map { $0 == from ? to : $0 }
        tagDraft = uniqPreserveOrder(updated)
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
                            Text(oneLine(attr.string))
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .contentShape(Rectangle())
                                .onTapGesture { onFocus() }
                        } else {
                            if let ms = createdAtMs, ms > 0 {
                                Text(dateLine(ms))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 2)
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
                    Spacer()
                    Menu {
                        let d = oneLine(domainPreview ?? "")
                        let g = oneLine(goalPreview ?? "")

                        Button {
                            openTagSheet()
                        } label: {
                            Label(d.isEmpty ? "Domain: (none)" : "Domain: \(d)", systemImage: "tag")
                        }

                        .disabled(false)

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
                    Spacer()
                }
                .frame(maxHeight: .infinity)
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
                            Button("Add") {
                                let t = normalizedTag(tagNewText)
                                if !t.isEmpty {
                                    tagDraft = uniqPreserveOrder(tagDraft + [t])
                                }
                                tagNewText = ""
                            }
                            .disabled(normalizedTag(tagNewText).isEmpty)
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
