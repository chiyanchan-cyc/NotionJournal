import SwiftUI
import UIKit
import Combine

struct Sidebar: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedNoteID: NJNoteID?
    @Environment(\.openWindow) private var openWindow

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
    @State private var showChronoNotes = false
    @State private var showCalendarView = false
    @State private var showGoalSeedlingList = false
    @State private var showGPSLogger = false
    @State private var showHealthLogger = false
    @State private var showHealthWeeklySummary = false
    @State private var showExport = false
    @State private var showQuickNoteSheet = false
    @State private var quickNoteText = ""


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
                if $0.pinned != $1.pinned { return $0.pinned > $1.pinned }
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

    private var isPhone: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .phone
        #else
        return false
        #endif
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
                if isPhone {
                    HStack {
                        ModuleToolbarButtons(
                            items: [
                                ModuleToolbarButtons.Item(id: "note", title: "Note", systemImage: "doc.text", isOn: store.selectedModule == .note, action: {
                                    store.selectedModule = .note
                                    selectedNoteID = nil
                                }),
                                ModuleToolbarButtons.Item(id: "goal", title: "Goal", systemImage: "target", isOn: store.selectedModule == .goal, action: {
                                    store.selectedModule = .goal
                                    selectedNoteID = nil
                                }),
                                ModuleToolbarButtons.Item(id: "outline", title: "Outline", systemImage: "list.bullet.rectangle", isOn: store.selectedModule == .outline, action: {
                                    store.selectedModule = .outline
                                    selectedNoteID = nil
                                })
                            ]
                        )
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                    .padding(.top, 4)
                    .padding(.bottom, 6)
                }
                if store.selectedModule == .note {
                    HStack(spacing: 10) {
                        Spacer()

                        Button(action: createNote) { Image(systemName: "plus") }
                            .disabled(store.selectedTabID == nil || store.selectedNotebookID == nil)

                        addMenu()

                        Menu {
                            Button("GPS Logger", systemImage: "location.circle") {
                                showGPSLogger = true
                            }

                            Button("Health Logger", systemImage: "heart.circle") {
                                showHealthLogger = true
                            }

                            Button("DB Debug", systemImage: "terminal") {
                                store.showDBDebugPanel = true
                            }

                            Button("Force Pull", systemImage: "arrow.down.circle") {
                                store.forcePullNow(forceSinceZero: true)
                            }

                            Button("Export", systemImage: "square.and.arrow.up") {
                                showExport = true
                            }

                            Divider()

                            Button("Rebuild Tag Index", systemImage: "arrow.triangle.2.circlepath") {
                                NJLocalBLRunner(db: store.db).runDeriveBlockTagIndexAndDomainV1All(limit: 8000)
                            }
                        } label: {
                            Image(systemName: "slider.horizontal.3")
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
                    .frame(height: 36)
                    .background(Color(UIColor.systemBackground))
                }

                if store.selectedModule == .note {
                    Divider()
                    if isPhone {
                        Color.clear.frame(height: 6)
                    }
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
                }
            

            Divider()

            if store.selectedModule == .note {
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
                                        HStack(spacing: 6) {
                                            Text(n.title.isEmpty ? "Untitled" : n.title)
                                                .lineLimit(1)
                                            if n.pinned > 0 {
                                                Image(systemName: "pin.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

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
                    .id(noteListResetKey)
                    .onChange(of: store.selectedTabID) { _, _ in
                        selectedNoteID = nil
                        noteListResetKey = UUID()
                    }
                    .onChange(of: store.selectedNotebookID) { _, _ in
                        selectedNoteID = nil
                        noteListResetKey = UUID()
                    }
                    .safeAreaInset(edge: .bottom) {
                        Color.clear.frame(height: 56)
                    }
                    .listStyle(.sidebar)
                }
            } else if store.selectedModule == .goal {
                NJGoalSidebarView()
                    .environmentObject(store)
            } else if store.selectedModule == .outline {
                NJOutlineSidebarView(outline: store.outline)
                    .environmentObject(store)
            } else {
                Spacer(minLength: 0)
            }

            Divider()

            if store.selectedModule == .note {
                HStack(spacing: 12) {
                    SidebarSquareButton(systemName: "target") {
                        openWeeklyReconstructed()
                    }

                    SidebarSquareButton(systemName: "magnifyingglass") {
                        openManualReconstructed()
                    }

                    SidebarSquareButton(systemName: "clock") {
                        openChronoView()
                    }

                    SidebarSquareButton(systemName: "calendar") {
                        openCalendarView()
                    }

                    SidebarSquareButton(systemName: "heart.text.square") {
                        showHealthWeeklySummary = true
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Button {
                showQuickNoteSheet = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 46, height: 46)
                    .background(Circle().fill(Color.accentColor))
                    .shadow(color: .black.opacity(0.2), radius: 6, x: 0, y: 3)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 14)
            .padding(.bottom, store.selectedModule == .note ? 64 : 14)
        }
        .toolbar {
            if !isPhone {
                ToolbarItem(placement: .navigationBarLeading) {
                    ModuleToolbarButtons(
                        items: [
                            ModuleToolbarButtons.Item(id: "note", title: "Note", systemImage: "doc.text", isOn: store.selectedModule == .note, action: {
                                store.selectedModule = .note
                                selectedNoteID = nil
                            }),
                            ModuleToolbarButtons.Item(id: "goal", title: "Goal", systemImage: "target", isOn: store.selectedModule == .goal, action: {
                                store.selectedModule = .goal
                                selectedNoteID = nil
                            }),
                            ModuleToolbarButtons.Item(id: "outline", title: "Outline", systemImage: "list.bullet.rectangle", isOn: store.selectedModule == .outline, action: {
                                store.selectedModule = .outline
                                selectedNoteID = nil
                            })
                        ]
                    )
                }
            }
        }
        .toolbar(isPhone ? .hidden : .automatic, for: .navigationBar)
        .sheet(isPresented: $showQuickNoteSheet) {
            NavigationStack {
                VStack(spacing: 12) {
                    TextEditor(text: $quickNoteText)
                        .padding(10)
                        .frame(minHeight: 160)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    Spacer()
                }
                .padding(16)
                .navigationTitle("Quick Note")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            quickNoteText = ""
                            showQuickNoteSheet = false
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add to Clipboard") {
                            let trimmed = quickNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            store.createQuickNoteToClipboard(plainText: trimmed)
                            quickNoteText = ""
                            showQuickNoteSheet = false
                        }
                    }
                }
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

        .sheet(isPresented: $showGPSLogger) {
            NavigationStack {
                NJGPSLoggerPage()
            }
        }

        .sheet(isPresented: $showHealthLogger) {
            NavigationStack {
                NJHealthLoggerPage()
            }
        }

        .sheet(isPresented: $showHealthWeeklySummary) {
            NavigationStack {
                NJHealthWeeklySummaryView()
                    .environmentObject(store)
            }
        }
        
        .sheet(isPresented: $showExport) {
            NJExportView().environmentObject(store)
        }

        .sheet(isPresented: $showWeeklyReconstructed) {
            NavigationStack {
                NJReconstructedNoteView(spec: .weekly())
                    .environmentObject(store)
            }
        }

        .sheet(isPresented: $showManualReconstructed) {
            NavigationStack {
                NJReconstructedWorkspaceView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showChronoNotes) {
            NavigationStack {
                NJChronoNoteListView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showCalendarView) {
            NavigationStack {
                NJCalendarView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $showGoalSeedlingList) {
            NavigationStack {
                NJGoalWorkspaceView()
                    .environmentObject(store)
            }
        }
        .sheet(isPresented: $store.showDBDebugPanel) {
            NJDebugSQLConsole(db: store.db)
        }
    }

    private func openWeeklyReconstructed() {
        if shouldUseWindowForReconstructed {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                openWindow(id: "reconstructed-weekly")
            } else {
                showWeeklyReconstructed = true
            }
            #else
            openWindow(id: "reconstructed-weekly")
            #endif
        } else {
            showWeeklyReconstructed = true
        }
    }

    private func openManualReconstructed() {
        if shouldUseWindowForReconstructed {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                openWindow(id: "reconstructed-workspace")
            } else {
                showManualReconstructed = true
            }
            #else
            openWindow(id: "reconstructed-workspace")
            #endif
        } else {
            showManualReconstructed = true
        }
    }

    private func openCalendarView() {
        if shouldUseWindowForReconstructed {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                openWindow(id: "calendar")
            } else {
                showCalendarView = true
            }
            #else
            openWindow(id: "calendar")
            #endif
        } else {
            showCalendarView = true
        }
    }

    private func openChronoView() {
        if shouldUseWindowForReconstructed {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                openWindow(id: "chrono")
            } else {
                showChronoNotes = true
            }
            #else
            openWindow(id: "chrono")
            #endif
        } else {
            showChronoNotes = true
        }
    }

}

private extension Sidebar {
    var shouldUseWindowForReconstructed: Bool {
        #if os(iOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        return idiom == .pad || idiom == .mac
        #else
        return true
        #endif
    }
}

private struct SidebarSquareButton: View {
    let systemName: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

struct NotebookTopBar: View {
    let notebooks: [NJNotebook]
    let selectedID: String?
    let onSelect: (String) -> Void

    private var itemW: CGFloat {
        isPad ? 92 : 120
    }
    private var itemH: CGFloat {
        isPad ? 44 : 52
    }
    private var fontSize: CGFloat {
        isPad ? 11 : 12
    }
    private var itemSpacing: CGFloat {
        isPad ? 8 : 10
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: itemSpacing) {
                ForEach(notebooks) { nb in
                    let isOn = (selectedID == nb.notebookID)

                    Button {
                        onSelect(nb.notebookID)
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(isOn ? Color(hex: nb.colorHex).opacity(0.22) : Color(UIColor.secondarySystemBackground))

                            Text(nb.title)
                                .font(.system(size: fontSize, weight: .regular))
                                .multilineTextAlignment(.center)
                                .lineLimit(2)
                                .minimumScaleFactor(0.65)
                                .allowsTightening(true)
                                .frame(width: itemW - 14, alignment: .center)
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

    private var isPad: Bool {
        #if os(iOS)
        return UIDevice.current.userInterfaceIdiom == .pad
        #else
        return false
        #endif
    }
}
