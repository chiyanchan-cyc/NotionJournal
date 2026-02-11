import SwiftUI

struct NJOutlineDetailView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    let nodeID: String

    @State private var commentDraft: String = ""
    @State private var showAttachSheet = false
    @State private var activeTab: Tab = .note

    enum Tab: String, CaseIterable, Identifiable {
        case note
        case folder

        var id: String { rawValue }
        var title: String { rawValue.capitalized }
    }

    var node: NJOutlineNode? {
        outline.node(nodeID)
    }

    var body: some View {
        VStack(spacing: 0) {
            if let node {
                header(node)
                Divider()
                if activeTab == .note {
                    if !node.homeNoteID.isEmpty {
                        NJNoteEditorContainerView(noteID: NJNoteID(node.homeNoteID))
                            .id(node.homeNoteID)
                    } else {
                        ContentUnavailableView("No home note", systemImage: "doc.text")
                    }
                } else {
                    folderView(node)
                }
            } else {
                ContentUnavailableView("Select a node", systemImage: "list.bullet.rectangle")
            }
        }
        .sheet(isPresented: $showAttachSheet) {
            NavigationStack {
                NJOutlineClipboardAttachSheet(outline: outline, nodeID: nodeID)
                    .environmentObject(store)
            }
        }
        .onAppear {
            if let node {
                commentDraft = node.comment
            }
        }
        .onChange(of: nodeID) { _, _ in
            if let node {
                commentDraft = node.comment
            }
        }
    }

    private func header(_ node: NJOutlineNode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Button {
                    outline.toggleChecked(nodeID: node.id)
                } label: {
                    Image(systemName: node.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(node.isChecked ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)

                TextField("Topic", text: Binding(
                    get: { node.title },
                    set: { outline.setTitle(nodeID: node.id, title: $0) }
                ))
                .textFieldStyle(.roundedBorder)

                Picker("Tab", selection: $activeTab) {
                    ForEach(Tab.allCases) { t in
                        Text(t.title).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 240)
            }

            HStack(spacing: 12) {
                Picker("Status", selection: Binding(
                    get: { node.status },
                    set: { outline.setStatus(nodeID: node.id, status: $0) }
                )) {
                    ForEach(NJOutlineStatus.allCases) { s in
                        Text(s.displayName).tag(s)
                    }
                }
                .pickerStyle(.menu)

                if let date = node.dateMs {
                    DatePicker("Date", selection: Binding(
                        get: { Date(timeIntervalSince1970: TimeInterval(date) / 1000.0) },
                        set: { outline.setDate(nodeID: node.id, date: $0) }
                    ), displayedComponents: .date)
                    Button("Clear") { outline.setDate(nodeID: node.id, date: nil) }
                        .buttonStyle(.bordered)
                } else {
                    Button("Add Date") { outline.setDate(nodeID: node.id, date: Date()) }
                        .buttonStyle(.bordered)
                }

                Spacer()

                Button {
                    showAttachSheet = true
                } label: {
                    Label("Attach", systemImage: "paperclip")
                }
                .buttonStyle(.bordered)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Comment")
                    .font(.caption)
                    .foregroundColor(.secondary)
                TextEditor(text: $commentDraft)
                    .frame(minHeight: 80)
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
                        outline.setComment(nodeID: node.id, comment: commentDraft)
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func folderView(_ node: NJOutlineNode) -> some View {
        List {
            if outline.pinsForNode(node.id).isEmpty {
                ContentUnavailableView("No pinned items", systemImage: "pin")
            } else {
                Section("Pinned") {
                    ForEach(outline.pinsForNode(node.id)) { pin in
                        OutlinePinRow(pin: pin, store: store)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    outline.removePin(pinID: pin.id)
                                } label: {
                                    Label("Remove", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.plain)
    }
}

private struct OutlinePinRow: View {
    let pin: NJOutlinePin
    let store: AppStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(previewTitle())
                .font(.body)
                .lineLimit(2)
            Text(previewSubtitle())
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func previewTitle() -> String {
        guard let meta = blockMeta() else { return pin.blockID }
        return meta.title.isEmpty ? pin.blockID : meta.title
    }

    private func previewSubtitle() -> String {
        guard let meta = blockMeta() else { return "" }
        if meta.kind.isEmpty { return "Block" }
        if meta.website.isEmpty { return meta.kind }
        return "\(meta.kind) · \(meta.website)"
    }

    private func blockMeta() -> (title: String, website: String, kind: String)? {
        guard let row = store.notes.loadBlock(blockID: pin.blockID) else { return nil }
        let payload = (row["payload_json"] as? String) ?? ""
        let kind = (row["block_type"] as? String) ?? ""
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "", kind) }

        let title = (obj["title"] as? String) ?? ""
        let website = (obj["website"] as? String) ?? ""
        return (title, website, kind)
    }
}
