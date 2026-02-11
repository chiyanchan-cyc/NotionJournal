import SwiftUI
import UniformTypeIdentifiers

struct NJOutlineSidebarView: View {
    @EnvironmentObject var store: AppStore
    @ObservedObject var outline: NJOutlineStore

    @State private var filterStatus: StatusFilter = .all
    @State private var filterFromEnabled = false
    @State private var filterToEnabled = false
    @State private var filterOnlyDated = false
    @State private var filterFromDate = Date()
    @State private var filterToDate = Date()
    @State private var showFilterBar = false

    @State private var showCreateAlert = false
    @State private var newTitle = ""

    var body: some View {
        VStack(spacing: 0) {
            header()
            Divider()
            List(selection: $store.selectedOutlineNodeID) {
                if outline.nodes.isEmpty {
                    ContentUnavailableView("Create an outline node", systemImage: "list.bullet.rectangle")
                        .frame(maxWidth: .infinity, alignment: .center)
                } else {
                    ForEach(outline.flatten(filter: currentFilter())) { row in
                        NJOutlineRowView(
                            row: row,
                            outline: outline,
                            onSelect: { store.selectedOutlineNodeID = row.node.id }
                        )
                        .tag(row.node.id)
                        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
                    }
                }
            }
            .listStyle(.sidebar)
            .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                handleDropToRoot(providers: providers)
            }
        }
    }

    private func header() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 10) {
                Spacer()
                Button {
                    newTitle = ""
                    showCreateAlert = true
                } label: {
                    Image(systemName: "plus")
                }
                .disabled(store.currentNotebookTitle == nil || store.currentTabDomain == nil)

                Button {
                    showFilterBar.toggle()
                } label: {
                    Image(systemName: showFilterBar ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
            .padding(.trailing, 10)
            .padding(.top, 6)
            .padding(.bottom, 6)
            .frame(height: 36)
            .background(Color(UIColor.systemBackground))

            if showFilterBar {
                filterBar()
            }
        }
        .alert("New Outline Node", isPresented: $showCreateAlert) {
            TextField("Title", text: $newTitle)
            Button("Create") { createNode(parentID: nil) }
            Button("Cancel", role: .cancel) { }
        }
    }

    private func filterBar() -> some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Text("Status")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Picker("Status", selection: $filterStatus) {
                    ForEach(StatusFilter.allCases) { s in
                        Text(s.title).tag(s)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }

            HStack(spacing: 10) {
                Toggle("Only dated", isOn: $filterOnlyDated)
                    .font(.caption)
                Spacer()
            }

            HStack(spacing: 8) {
                Toggle("From", isOn: $filterFromEnabled)
                    .font(.caption)
                if filterFromEnabled {
                    DatePicker("", selection: $filterFromDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }

            HStack(spacing: 8) {
                Toggle("To", isOn: $filterToEnabled)
                    .font(.caption)
                if filterToEnabled {
                    DatePicker("", selection: $filterToDate, displayedComponents: .date)
                        .labelsHidden()
                }
                Spacer()
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private func createNode(parentID: String?) {
        guard let nb = store.currentNotebookTitle, let tab = store.currentTabDomain else {
            store.selectedOutlineNodeID = nil
            return
        }
        let n = store.notes.createNote(notebook: nb, tabDomain: tab, title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines))
        let node = outline.createNode(parentID: parentID, title: newTitle.trimmingCharacters(in: .whitespacesAndNewlines), homeNoteID: n.id.raw)
        store.selectedOutlineNodeID = node.id
        newTitle = ""
    }

    private func currentFilter() -> NJOutlineFilter {
        let status: NJOutlineStatus? = {
            switch filterStatus {
            case .all: return nil
            case .none: return .none
            case .active: return .active
            case .hold: return .hold
            case .done: return .done
            }
        }()
        return NJOutlineFilter(
            status: status,
            fromDate: filterFromEnabled ? filterFromDate : nil,
            toDate: filterToEnabled ? filterToDate : nil,
            onlyDated: filterOnlyDated
        )
    }

    private func handleDropToRoot(providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let id = object as? String else { return }
            DispatchQueue.main.async {
                outline.moveNodeToRoot(draggedID: id)
            }
        }
        return true
    }
}

private enum StatusFilter: String, CaseIterable, Identifiable {
    case all
    case none
    case active
    case hold
    case done

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .none: return "None"
        case .active: return "Active"
        case .hold: return "Hold"
        case .done: return "Done"
        }
    }
}

private struct NJOutlineRowView: View {
    @EnvironmentObject var store: AppStore
    let row: NJOutlineRow
    @ObservedObject var outline: NJOutlineStore
    let onSelect: () -> Void

    private var hasChildren: Bool { outline.hasChildren(row.node.id) }
    private var titleText: String { row.node.title.isEmpty ? "Untitled" : row.node.title }

    var body: some View {
        HStack(spacing: 6) {
            Spacer().frame(width: CGFloat(row.depth) * 16)

            if hasChildren {
                Button {
                    outline.toggleCollapsed(nodeID: row.node.id)
                } label: {
                    Image(systemName: row.node.isCollapsed ? "chevron.right" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                Spacer().frame(width: 14)
            }

                Button {
                    outline.toggleChecked(nodeID: row.node.id)
                } label: {
                    Image(systemName: row.node.isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(row.node.isChecked ? .accentColor : .secondary)
                }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Image(systemName: "folder")
                    .foregroundColor(.secondary)
                Text(titleText)
                    .lineLimit(1)
                    .foregroundColor(row.isDimmed ? .secondary : .primary)
            }
            .contentShape(Rectangle())
            .onTapGesture { onSelect() }
            .onDrop(of: [UTType.text], delegate: NJOutlineDropDelegate(
                targetID: row.node.id,
                outline: outline,
                asChild: true
            ))

            Spacer(minLength: 0)

            if row.node.status != .none {
                Text(row.node.status.displayName)
                    .font(.caption2)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color(UIColor.secondarySystemBackground))
                    )
            }

            if let date = row.node.dateMs {
                Text(njDate(date))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onSelect() }
        .onDrag {
            NSItemProvider(object: row.node.id as NSString)
        }
        .onDrop(of: [UTType.text], delegate: NJOutlineDropDelegate(
            targetID: row.node.id,
            outline: outline,
            asChild: false
        ))
        .contextMenu {
            Button("Add Child") {
                createChild()
            }
            Button("Delete", role: .destructive) {
                outline.deleteNode(nodeID: row.node.id)
                if store.selectedOutlineNodeID == row.node.id {
                    store.selectedOutlineNodeID = nil
                }
            }
        }
    }

    private func createChild() {
        guard let nb = store.currentNotebookTitle, let tab = store.currentTabDomain else { return }
        let note = store.notes.createNote(notebook: nb, tabDomain: tab, title: "")
        let child = outline.createNode(parentID: row.node.id, title: "", homeNoteID: note.id.raw)
        store.selectedOutlineNodeID = child.id
    }

    private func njDate(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

private struct NJOutlineDropDelegate: DropDelegate {
    let targetID: String
    let outline: NJOutlineStore
    let asChild: Bool

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let provider = info.itemProviders(for: [UTType.text]).first else { return false }
        _ = provider.loadObject(ofClass: NSString.self) { object, _ in
            guard let draggedID = object as? String else { return }
            DispatchQueue.main.async {
                if asChild {
                    outline.moveNodeAsChild(draggedID: draggedID, parentID: targetID)
                } else {
                    outline.moveNodeAfter(draggedID: draggedID, targetID: targetID)
                }
            }
        }
        return true
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }
}
