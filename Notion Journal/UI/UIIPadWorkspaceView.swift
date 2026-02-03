import SwiftUI
import Combine

struct IPadWorkspaceView: View {
    @EnvironmentObject var store: AppStore

    @State private var notebook: String = "zz"
    @State private var tabDomainKey: String = "zz.edu"
    @State private var selectedNoteID: NJNoteID? = nil

    private var notebookTabs: [String] {
        if notebook == "self" { return ["self.reflection", "self.finance", "self.marriage"] }
        if notebook == "zz" { return ["zz.edu", "zz.adhd"] }
        return ["mushy.general"]
    }

    private var notesInTab: [NJNote] {
        store.notes.listNotes(tabDomainKey: tabDomainKey).sorted {
            if $0.pinned != $1.pinned { return $0.pinned > $1.pinned }
            if $0.updatedAtMs != $1.updatedAtMs { return $0.updatedAtMs > $1.updatedAtMs }
            return String(describing: $0.id) > String(describing: $1.id)
        }
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    Picker("Notebook", selection: $notebook) {
                        Text("zz").tag("zz")
                        Text("self").tag("self")
                        Text("mushy").tag("mushy")
                    }
                    .pickerStyle(.segmented)
                }
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 10)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(notebookTabs, id: \.self) { t in
                            Button {
                                tabDomainKey = t
                                selectedNoteID = nil
                            } label: {
                                Text(t)
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(tabDomainKey == t ? Color.primary.opacity(0.12) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 10)
                }

                List {
                    ForEach(notesInTab) { n in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Text(n.title.isEmpty ? "Untitled" : n.title).font(.headline)
                                if n.pinned > 0 {
                                    Image(systemName: "pin.fill")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(n.tabDomain).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedNoteID = n.id
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button {
                                store.notes.setPinned(noteID: n.id.raw, pinned: n.pinned == 0)
                                store.objectWillChange.send()
                            } label: {
                                Label(n.pinned == 0 ? "Pin" : "Unpin", systemImage: n.pinned == 0 ? "pin" : "pin.slash")
                            }
                            .tint(n.pinned == 0 ? .orange : .gray)
                        }
                    }
                }
            }
        } detail: {
            if let id = selectedNoteID {
                NJNoteEditorContainerView(noteID: id)
            } else {
                Text("Double-click a note")
                    .foregroundStyle(.secondary)
            }
        }
    }
}
