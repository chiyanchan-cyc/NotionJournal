import SwiftUI

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
        store.notes.listNotes(tabDomainKey: tabDomainKey)
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
                            Text(n.title.isEmpty ? "Untitled" : n.title).font(.headline)
                            Text(n.tabDomain).font(.caption).foregroundStyle(.secondary)
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) {
                            selectedNoteID = n.id
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
