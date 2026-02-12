import SwiftUI

struct NJOutlineDetailView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    let outlineID: String

    @State private var titleDraft: String = ""
    @State private var commentDraft: String = ""
    @State private var domainDraft: String = ""

    private var selectedNode: NJOutlineNodeRecord? {
        guard let nodeID = store.selectedOutlineNodeID else { return nil }
        return outline.node(nodeID)
    }

    private var rows: [NJOutlineNodeRow] {
        outline.nodeRows(outlineID: outlineID)
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar()
            Divider()
            if rows.isEmpty {
                ContentUnavailableView("No nodes", systemImage: "list.bullet")
            } else {
                List {
                    ForEach(rows) { row in
                        nodeRow(row)
                    }
                }
                .listStyle(.plain)
            }
            Divider()
            editorPanel()
        }
        .onAppear {
            outline.loadNodes(outlineID: outlineID)
            syncDrafts()
        }
        .onChange(of: store.selectedOutlineNodeID) { _, _ in
            syncDrafts()
        }
    }

    private func topBar() -> some View {
        HStack(spacing: 10) {
            Button("Add Root") {
                let n = outline.createRootNode(outlineID: outlineID)
                store.selectedOutlineNodeID = n.nodeID
                syncDrafts()
            }
            .buttonStyle(.bordered)

            if let nodeID = store.selectedOutlineNodeID {
                Button("Add Sibling") {
                    if let n = outline.createSiblingNode(nodeID: nodeID) {
                        store.selectedOutlineNodeID = n.nodeID
                        syncDrafts()
                    }
                }
                .buttonStyle(.bordered)

                Button("Add Child") {
                    if let n = outline.createChildNode(nodeID: nodeID) {
                        store.selectedOutlineNodeID = n.nodeID
                        syncDrafts()
                    }
                }
                .buttonStyle(.bordered)

                Button("Promote") {
                    outline.promote(nodeID: nodeID)
                }
                .buttonStyle(.bordered)

                Button("Demote") {
                    outline.demote(nodeID: nodeID)
                }
                .buttonStyle(.bordered)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func nodeRow(_ row: NJOutlineNodeRow) -> some View {
        let n = row.node
        return HStack(spacing: 8) {
            Spacer().frame(width: CGFloat(row.depth) * 16)

            if n.isChecklist {
                Button {
                    outline.toggleChecked(nodeID: n.nodeID)
                } label: {
                    Image(systemName: n.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(n.isChecked ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "minus")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .frame(width: 18)
            }

            Text(n.title.isEmpty ? "Untitled" : n.title)
                .lineLimit(1)
                .foregroundColor(.primary)

            Spacer(minLength: 0)

            if !n.domainTag.isEmpty {
                Text(n.domainTag)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Button {
                outline.toggleChecklist(nodeID: n.nodeID)
            } label: {
                Image(systemName: n.isChecklist ? "checkmark.square" : "square")
                    .foregroundColor(.secondary)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            store.selectedOutlineNodeID = n.nodeID
            syncDrafts()
        }
    }

    private func editorPanel() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let node = selectedNode {
                Text("Node")
                    .font(.caption)
                    .foregroundColor(.secondary)

                TextField("Title", text: $titleDraft)
                    .textFieldStyle(.roundedBorder)

                TextField("Domain", text: $domainDraft)
                    .textFieldStyle(.roundedBorder)

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
                    Button("Save") {
                        outline.updateNodeTitle(nodeID: node.nodeID, title: titleDraft)
                        outline.updateNodeDomain(nodeID: node.nodeID, domainTag: domainDraft)
                        outline.updateNodeComment(nodeID: node.nodeID, comment: commentDraft)
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                Text("Select a node")
                    .foregroundColor(.secondary)
            }
        }
        .padding(12)
    }

    private func syncDrafts() {
        guard let n = selectedNode else {
            titleDraft = ""
            commentDraft = ""
            domainDraft = ""
            return
        }
        titleDraft = n.title
        commentDraft = n.comment
        domainDraft = n.domainTag
    }
}
