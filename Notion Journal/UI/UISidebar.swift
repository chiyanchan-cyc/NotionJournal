import SwiftUI
import UIKit

struct Sidebar: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedNoteID: NJNoteID?

    @State private var showNewNotebook = false
    @State private var showNewTab = false

    @State private var newNotebookTitle = ""
    @State private var newNotebookColor = Color.blue

    @State private var newTabTitle = ""
    @State private var newTabDomain = ""
    @State private var newTabColor = Color.blue

    @State private var noteListResetKey = UUID()

    @State private var showCKNoteBlockDebug = false
    @State private var showWeeklyReconstructed = false
    @State private var showManualReconstructed = false // <-- ADD THIS
    @State private var showGPSLogger = false

    private var notesInScope: [NJNote] {
        guard
            let nb = store.currentNotebookTitle,
            let tabID = store.selectedTabID,
            let tab = store.tabs.first(where: { $0.tabID == tabID })
        else { return [] }

        let dom = tab.domainKey
        let key = dom.hasSuffix(".") ? "\(dom)%" : "\(dom).%"

        return store.notes.listNotes(tabDomainKey: key)
            .filter { $0.notebook == nb && $0.deleted == 0 }
            .sorted {
                if $0.createdAtMs != $1.createdAtMs { return $0.createdAtMs > $1.createdAtMs }
                return String(describing: $0.id) > String(describing: $1.id)
            }
    }

    private func createNote() {
        guard
            let nb = store.currentNotebookTitle,
            let tabID = store.selectedTabID,
            let tab = store.tabs.first(where: { $0.tabID == tabID })
        else { return }

        let n = store.notes.createNote(
            notebook: nb,
            tabDomain: tab.domainKey,
            title: ""
        )
        selectedNoteID = n.id
    }

    private func njDateSubscript(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func addMenu() -> some View {
        Menu {
            Button(action: {
                newNotebookTitle = ""
                newNotebookColor = .blue
                showNewNotebook = true
            }) {
                Text("New Notebook")
            }

            Button(action: {
                if store.selectedNotebookID == nil { return }
                newTabTitle = ""
                newTabDomain = ""
                newTabColor = Color(hex: store.currentNotebookColorHex)
                showNewTab = true
            }) {
                Text("New Tab")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                NotebookTopBar(
                    notebooks: store.notebooks,
                    selectedID: store.selectedNotebookID,
                    onSelect: { nbID in
                        store.selectNotebook(nbID)
                        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                        selectedNoteID = nil
                        noteListResetKey = UUID()
                    }
                )
                .padding(.top, 34)

                HStack(spacing: 10) {
                    Button(action: createNote) { Image(systemName: "plus") }
                        .disabled(store.selectedTabID == nil || store.selectedNotebookID == nil)

                    addMenu()

                    Button {
                        showGPSLogger = true
                    } label: {
                        Image(systemName: "location.circle")
                    }
//                    Button {
//                        showCKNoteBlockDebug = true
//                    } label: {
//                        Image(systemName: "icloud.and.arrow.down")
//                    }

                    Button {
                        showWeeklyReconstructed = true
                    } label: {
                        Image(systemName: "calendar")
                    }

                    Button {
                        showManualReconstructed = true
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                    
                    Button {
                        store.showDBDebugPanel = true
                    } label: {
                        Image(systemName: "terminal")
                    }
                }
                .padding(.trailing, 10)
                .padding(.top, 8)
            }

            Divider()

            HStack(spacing: 0) {
                Rail(onChanged: { selectedNoteID = nil })
                Divider()

                List(selection: $selectedNoteID) {
                    if store.selectedNotebookID == nil {
                        ContentUnavailableView("Create a notebook", systemImage: "books.vertical")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if store.selectedTabID == nil {
                        ContentUnavailableView("Create a tab", systemImage: "rectangle.on.rectangle")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else if notesInScope.isEmpty {
                        Text("No notes")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(notesInScope, id: \.id) { n in
                            NavigationLink(value: n.id) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(n.title.isEmpty ? "Untitled" : n.title)
                                        .lineLimit(1)

                                    if n.createdAtMs > 0 {
                                        Text(njDateSubscript(n.createdAtMs))
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .tag(n.id)
                            .simultaneousGesture(TapGesture().onEnded {
                                selectedNoteID = nil
                                DispatchQueue.main.async { selectedNoteID = n.id }
                            })
                        }
                    }
                }
                .id(noteListResetKey)
                .onChange(of: store.selectedTabID) { _ in
                    selectedNoteID = nil
                    noteListResetKey = UUID()
                }
                .onChange(of: store.selectedNotebookID) { _ in
                    selectedNoteID = nil
                    noteListResetKey = UUID()
                }
                .listStyle(.sidebar)
            }
        }
        .sheet(isPresented: $showNewNotebook) {
            NavigationStack {
                Form {
                    Section("Notebook") {
                        TextField("Title", text: $newNotebookTitle)
                        ColorPicker("Color", selection: $newNotebookColor, supportsOpacity: false)
                    }
                }
                .navigationTitle("New Notebook")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNewNotebook = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            _ = store.addNotebook(title: newNotebookTitle, colorHex: newNotebookColor.toHexString())
                            showNewNotebook = false
                            selectedNoteID = nil
                            noteListResetKey = UUID()
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showNewTab) {
            NavigationStack {
                Form {
                    Section("Tab") {
                        TextField("Title", text: $newTabTitle)
                        TextField("Domain", text: $newTabDomain)
                        ColorPicker("Color", selection: $newTabColor, supportsOpacity: false)
                    }
                    Section("Notebook") {
                        Text(store.currentNotebookTitle ?? "")
                            .foregroundStyle(.secondary)
                    }
                }
                .navigationTitle("New Tab")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showNewTab = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Create") {
                            guard let nbID = store.selectedNotebookID else { return }
                            _ = store.addTab(
                                notebookID: nbID,
                                title: newTabTitle,
                                domainKey: newTabDomain,
                                colorHex: newTabColor.toHexString()
                            )
                            showNewTab = false
                            selectedNoteID = nil
                            noteListResetKey = UUID()
                        }
                    }
                }
            }
        }

//#if DEBUG
//        .sheet(isPresented: $showCKNoteBlockDebug) {
//            NJDebugCKNoteBlockView(
//                recordType: "NJNoteBlock",
//                db: store.db
//            )
//        }
//#endif

        .sheet(isPresented: $showGPSLogger) {
            NavigationStack {
                NJGPSLoggerPage()
            }
        }

        .sheet(isPresented: $showWeeklyReconstructed) {
            NavigationStack {
                NJReconstructedNoteView(spec: .weekly())
                    .environmentObject(store)
            }
        }

        .sheet(isPresented: $showManualReconstructed) {
            NavigationStack {
                NJReconstructedManualView() // Initialize the new manual view
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $store.showDBDebugPanel) {
            NJDebugSQLConsole(db: store.db)
        }
    }
}

struct NotebookTopBar: View {
    let notebooks: [NJNotebook]
    let selectedID: String?
    let onSelect: (String) -> Void

    private let itemW: CGFloat = 120
    private let itemH: CGFloat = 52

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(notebooks) { nb in
                    let isOn = (selectedID == nb.notebookID)

                    Button {
                        onSelect(nb.notebookID)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isOn ? Color(hex: nb.colorHex).opacity(0.22) : Color(UIColor.secondarySystemBackground))

                            Text(nb.title)
                                .font(.system(size: 12, weight: .regular))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.65)
                                .allowsTightening(true)
                                .frame(width: itemW - 16, alignment: .center)
                                .foregroundStyle(.primary)
                        }
                        .frame(width: itemW, height: itemH)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 10)
        }
        .background(Color(UIColor.systemBackground))
    }
}
