import SwiftUI
import UIKit
import Combine
import Proton
import PhotosUI

struct Sidebar: View {
    @EnvironmentObject var store: AppStore
    @Binding var selectedNoteID: NJNoteID?
    var onRequestDetailFocus: (() -> Void)? = nil
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
    @State private var showMeetingInbox = false
    @State private var showExport = false
    @State private var showQuickNoteSheet = false
    @State private var quickNoteAttr = NSAttributedString(string: "")
    @State private var quickNoteSel = NSRange(location: 0, length: 0)
    @State private var quickNoteEditorHeight: CGFloat = 180
    @State private var quickNotePickedPhotoItem: PhotosPickerItem? = nil
    @State private var quickNoteHandle = NJProtonEditorHandle()
    @State private var showRecoverFromCloudConfirm = false
    @State private var showRecoverFinanceFromCloudConfirm = false
    @State private var tradeThesisExpanded = true
    private var notesInScope: [NJNote] {
        guard let nb = store.currentNotebookTitle else { return [] }

        let scopedNotes: [NJNote]
        if store.showFavoriteNotesOnly {
            scopedNotes = store.notes.listFavoriteNotes(notebook: nb)
        } else if
            let tabID = store.selectedTabID,
            let tab = store.tabs.first(where: { $0.tabID == tabID })
        {
            let dom = tab.domainKey
            let key = dom.hasSuffix(".") ? "\(dom)%" : "\(dom).%"
            scopedNotes = store.notes.listNotes(tabDomainKey: key)
                .filter { $0.notebook == nb && $0.deleted == 0 }
        } else {
            return []
        }

        return scopedNotes.sorted(by: sortNotes)
    }

    private func createNote(noteType: NJNoteType = .note) {
        guard
            let nb = store.currentNotebookTitle,
            let tabID = store.selectedTabID,
            let tab = store.tabs.first(where: { $0.tabID == tabID })
        else { return }

        let n = store.notes.createNote(
            notebook: nb,
            tabDomain: tab.domainKey,
            title: "",
            noteType: noteType
        )
        selectedNoteID = n.id
    }

    private func cardPriorityRank(_ note: NJNote) -> Int {
        switch note.cardPriority.lowercased() {
        case "high": return 0
        case "medium": return 1
        case "low": return 2
        default: return 3
        }
    }

    private func cardStatusRank(_ note: NJNote) -> Int {
        switch note.cardStatus.lowercased() {
        case "pending": return 0
        case "in progress": return 1
        case "tbt": return 2
        case "done": return 3
        case "dropped": return 4
        default: return 5
        }
    }

    private func sortNotes(_ lhs: NJNote, _ rhs: NJNote) -> Bool {
        if lhs.pinned != rhs.pinned { return lhs.pinned > rhs.pinned }

        if lhs.updatedAtMs != rhs.updatedAtMs { return lhs.updatedAtMs > rhs.updatedAtMs }
        if lhs.createdAtMs != rhs.createdAtMs { return lhs.createdAtMs > rhs.createdAtMs }
        return String(describing: lhs.id) > String(describing: rhs.id)
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

    private func focusDetailIfNeeded() {
        guard isPhone else { return }
        onRequestDetailFocus?()
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

    @ViewBuilder
    private var scopeToolbarButton: some View {
        Button {
            openWeeklyReconstructed()
        } label: {
            Image(systemName: "scope")
                .font(.system(size: 12, weight: .semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var gpsToolbarButton: some View {
        Button {
            showGPSLogger = true
        } label: {
            Image(systemName: "location.circle")
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 32, height: 32)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(UIColor.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("GPS Logger")
    }

    private var moduleToolbarItems: [ModuleToolbarButtons.Item] {
        [
            ModuleToolbarButtons.Item(id: "note", title: "Note", systemImage: "doc.text", isOn: store.selectedModule == .note, action: {
                store.selectedModule = .note
                selectedNoteID = nil
                focusDetailIfNeeded()
            }),
            ModuleToolbarButtons.Item(id: "goal", title: "Goal", systemImage: "target", isOn: store.selectedModule == .goal, action: {
                store.selectedModule = .goal
                selectedNoteID = nil
                focusDetailIfNeeded()
            }),
            ModuleToolbarButtons.Item(id: "outline", title: "Outline", systemImage: "list.bullet.rectangle", isOn: store.selectedModule == .outline, action: {
                store.selectedModule = .outline
                selectedNoteID = nil
                focusDetailIfNeeded()
            }),
            ModuleToolbarButtons.Item(id: "time", title: "Time", systemImage: "applewatch", isOn: store.selectedModule == .time, action: {
                store.selectedModule = .time
                selectedNoteID = nil
                focusDetailIfNeeded()
            }),
            ModuleToolbarButtons.Item(id: "investment", title: "Investment", systemImage: "chart.line.uptrend.xyaxis", isOn: store.selectedModule == .investment, action: {
                store.selectedModule = .investment
                selectedNoteID = nil
                focusDetailIfNeeded()
            }),
            ModuleToolbarButtons.Item(id: "planning", title: "Planning", systemImage: "calendar", isOn: false, action: {
                openCalendarView()
            })
        ]
    }

    @ViewBuilder
    private var sharedModuleRow: some View {
        HStack {
            ScrollView(.horizontal, showsIndicators: false) {
                ModuleToolbarButtons(items: moduleToolbarItems)
            }

            if store.selectedModule == .note {
                HStack(spacing: 6) {
                    scopeToolbarButton
                    NJGPSStatusBadge()
                    if !isPhone {
                        gpsToolbarButton
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 4)
        .padding(.bottom, 6)
    }

    var body: some View {
        VStack(spacing: 0) {
                sharedModuleRow
                if store.selectedModule == .note {
                    Group {
                        if isPhone {
                            HStack(spacing: 8) {
                                Spacer()

                                Menu {
                                    Button("New Note", systemImage: "doc.text") {
                                        createNote()
                                    }
                                    Button("New Card", systemImage: "rectangle.stack") {
                                        createNote(noteType: .card)
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                }
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

                                    Button("Recover from Cloud", systemImage: "icloud.and.arrow.down") {
                                        showRecoverFromCloudConfirm = true
                                    }

                                    Button("Pull Finance from Cloud", systemImage: "banknote.and.arrow.down") {
                                        showRecoverFinanceFromCloudConfirm = true
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
                            .frame(height: 36)
                        } else {
                            HStack(spacing: 8) {
                                Spacer(minLength: 0)

                                Menu {
                                    Button("New Note", systemImage: "doc.text") {
                                        createNote()
                                    }
                                    Button("New Card", systemImage: "rectangle.stack") {
                                        createNote(noteType: .card)
                                    }
                                } label: {
                                    Image(systemName: "plus")
                                }
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

                                    Button("Recover from Cloud", systemImage: "icloud.and.arrow.down") {
                                        showRecoverFromCloudConfirm = true
                                    }

                                    Button("Pull Finance from Cloud", systemImage: "banknote.and.arrow.down") {
                                        showRecoverFinanceFromCloudConfirm = true
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
                            .frame(height: 36)
                        }
                    }
                    .padding(.trailing, 10)
                    .padding(.top, 6)
                    .padding(.bottom, 6)
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
                        } else if !store.showFavoriteNotesOnly && store.selectedTabID == nil {
                            ContentUnavailableView("Create a tab", systemImage: "rectangle.on.rectangle")
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else if notesInScope.isEmpty {
                            Text(store.showFavoriteNotesOnly ? "No favorite notes" : "No notes")
                                .foregroundStyle(.secondary)
                        } else {
                            ForEach(notesInScope, id: \.id) { n in
                                NavigationLink(value: n.id) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 6) {
                                            Image(systemName: n.noteType == .card ? "rectangle.stack.fill" : "doc.text")
                                                .font(.caption2)
                                                .foregroundStyle(n.noteType == .card ? .blue : .secondary)
                                            Text(n.title.isEmpty ? "Untitled" : n.title)
                                                .lineLimit(1)
                                            if n.favorited > 0 {
                                                Image(systemName: "star.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.yellow)
                                            }
                                            if n.pinned > 0 {
                                                Image(systemName: "pin.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        }

                                        if n.noteType == .card {
                                            cardSubtitle(for: n)
                                        } else if n.createdAtMs > 0 {
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
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    Button {
                                        toggleFavorite(note: n)
                                    } label: {
                                        Label(n.favorited == 0 ? "Star" : "Unstar", systemImage: n.favorited == 0 ? "star" : "star.slash")
                                    }
                                    .tint(n.favorited == 0 ? .yellow : .gray)

                                    Button {
                                        togglePinned(note: n)
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
                    .onChange(of: store.showFavoriteNotesOnly) { _, _ in
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
            } else if store.selectedModule == .investment {
                investmentSidebar
            } else if store.selectedModule == .time, isPhone {
                NJTimeModuleView()
                    .environmentObject(store)
            } else {
                Spacer(minLength: 0)
            }

            Divider()

            if store.selectedModule == .note {
                HStack(spacing: 12) {
                    SidebarSquareButton(systemName: "magnifyingglass") {
                        openManualReconstructed()
                    }

                    SidebarSquareButton(systemName: "clock") {
                        openChronoView()
                    }

                    SidebarSquareButton(systemName: "heart.text.square") {
                        showHealthWeeklySummary = true
                    }

                    SidebarSquareButton(
                        systemName: store.showFavoriteNotesOnly ? "star.fill" : "star",
                        isOn: store.showFavoriteNotesOnly
                    ) {
                        store.showFavoriteNotesOnly.toggle()
                        selectedNoteID = nil
                        noteListResetKey = UUID()
                    }

                    SidebarSquareButton(systemName: "waveform.badge.mic") {
                        showMeetingInbox = true
                    }

                    Spacer()
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if store.selectedModule == .note {
                Button {
                    resetQuickNoteEditor()
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
                .padding(.bottom, 64)
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showQuickNoteSheet) {
            NavigationStack {
                VStack(spacing: 12) {
                    NJProtonEditorView(
                        initialAttributedText: quickNoteAttr,
                        initialSelectedRange: quickNoteSel,
                        snapshotAttributedText: $quickNoteAttr,
                        snapshotSelectedRange: $quickNoteSel,
                        measuredHeight: $quickNoteEditorHeight,
                        handle: quickNoteHandle
                    )
                    .frame(minHeight: quickNoteEditorHeight)
                    .padding(10)
                    .background(Color(UIColor.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Spacer()
                }
                .padding(16)
                .navigationTitle("Quick Note")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    NJProtonFloatingFormatBar(handle: quickNoteHandle, pickedPhotoItem: $quickNotePickedPhotoItem)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            showQuickNoteSheet = false
                            resetQuickNoteEditor()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add to Clipboard") {
                            quickNoteHandle.snapshot()
                            let attrToSave = quickNoteHandle.editor?.attributedText ?? quickNoteAttr
                            let trimmed = attrToSave.string.trimmingCharacters(in: .whitespacesAndNewlines)
                            guard !trimmed.isEmpty else { return }
                            let protonJSON = quickNoteHandle.exportProtonJSONString()
                            let rtfBase64 = DBNoteRepository.encodeRTFBase64FromAttributedText(attrToSave)
                            let payload = NJQuickNotePayload.makePayloadJSON(
                                protonJSON: protonJSON,
                                rtfBase64: rtfBase64
                            )
                            store.createQuickNoteToClipboard(payloadJSON: payload)
                            showQuickNoteSheet = false
                            resetQuickNoteEditor()
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
        .sheet(isPresented: $showMeetingInbox) {
            NavigationStack {
                NJMeetingInboxView()
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
                .environmentObject(store)
        }
        .alert("Recover from Cloud?", isPresented: $showRecoverFromCloudConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Recover", role: .destructive) {
                store.recoverFromCloudNow()
            }
        } message: {
            Text("This resets only this Mac app's local CloudKit pull cursors and re-downloads notes and blocks from iCloud. It does not erase data from your iPhone or iPad.")
        }
        .alert("Pull Finance from Cloud?", isPresented: $showRecoverFinanceFromCloudConfirm) {
            Button("Cancel", role: .cancel) { }
            Button("Pull") {
                store.pullFinanceFromCloudNow()
            }
        } message: {
            Text("This resets only the local finance transaction pull cursor and re-downloads finance records from iCloud for this device.")
        }
    }

    private func openWeeklyReconstructed() {
        if shouldUseWindowForReconstructed {
            #if os(macOS)
            if #available(macOS 13.0, *) {
                openWindow(id: "reconstructed-weekly", value: "weekly")
            } else {
                showWeeklyReconstructed = true
            }
            #else
            openWindow(id: "reconstructed-weekly", value: "weekly")
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

    private func toggleFavorite(note: NJNote) {
        store.notes.setFavorited(noteID: note.id.raw, favorited: note.favorited == 0)
        store.objectWillChange.send()
    }

    private func togglePinned(note: NJNote) {
        store.notes.setPinned(noteID: note.id.raw, pinned: note.pinned == 0)
        store.objectWillChange.send()
    }

    private func resetQuickNoteEditor() {
        quickNoteAttr = NSAttributedString(string: "")
        quickNoteSel = NSRange(location: 0, length: 0)
        quickNoteEditorHeight = 180
        quickNotePickedPhotoItem = nil
        quickNoteHandle = NJProtonEditorHandle()
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

    var investmentSidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Investment")
                .font(.headline.weight(.bold))
                .padding(.horizontal, 14)
                .padding(.top, 16)
                .padding(.bottom, 8)

            ForEach(NJInvestmentSection.allCases) { section in
                if section == .trades {
                    VStack(alignment: .leading, spacing: 4) {
                        Button {
                            tradeThesisExpanded.toggle()
                            store.selectedInvestmentSection = .trades
                            selectedNoteID = nil
                            focusDetailIfNeeded()
                        } label: {
                            HStack(spacing: 8) {
                                Label(section.rawValue, systemImage: section.symbolName)
                                Spacer()
                                Image(systemName: tradeThesisExpanded ? "chevron.down" : "chevron.right")
                                    .font(.caption.weight(.bold))
                            }
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(store.selectedInvestmentSection == section ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(store.selectedInvestmentSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                        .buttonStyle(.plain)

                        if tradeThesisExpanded {
                            ForEach(NJInvestmentTradeTab.allCases) { tab in
                                Button {
                                    store.selectedInvestmentSection = .trades
                                    store.selectedInvestmentTradeTab = tab
                                    selectedNoteID = nil
                                    focusDetailIfNeeded()
                                } label: {
                                    Label(tab.rawValue, systemImage: tab.symbolName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(store.selectedInvestmentSection == .trades && store.selectedInvestmentTradeTab == tab ? Color.accentColor : Color.primary)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.leading, 28)
                                        .padding(.trailing, 12)
                                        .padding(.vertical, 8)
                                        .background(store.selectedInvestmentSection == .trades && store.selectedInvestmentTradeTab == tab ? Color.accentColor.opacity(0.10) : Color.clear)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                } else {
                    Button {
                        store.selectedInvestmentSection = section
                        selectedNoteID = nil
                        focusDetailIfNeeded()
                    } label: {
                        Label(section.rawValue, systemImage: section.symbolName)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(store.selectedInvestmentSection == section ? Color.accentColor : Color.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(store.selectedInvestmentSection == section ? Color.accentColor.opacity(0.14) : Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 10)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color(UIColor.systemBackground))
    }

    @ViewBuilder
    private func cardSubtitle(for note: NJNote) -> some View {
        Text(note.tabDomain)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }
}

private struct SidebarSquareButton: View {
    let systemName: String
    var isOn: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .frame(width: 40, height: 40)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isOn ? Color.accentColor.opacity(0.22) : Color(UIColor.secondarySystemBackground))
                )
        }
        .buttonStyle(.plain)
    }
}

private struct NJDatabaseSidebarView: View {
    @EnvironmentObject var store: AppStore
    @State private var rows: [NJRenewalItemRecord] = []

    var body: some View {
        List {
            Section("Browse") {
                familyFilterRow(
                    title: "Personal Identification",
                    subtitle: "\(rows.count) total",
                    systemImage: "person.text.rectangle",
                    isSelected: store.selectedFamilyInfoPerson == "All" && store.selectedFamilyInfoType == "All"
                ) {
                    store.selectedFamilyInfoPerson = "All"
                    store.selectedFamilyInfoType = "All"
                }
            }

            Section("People") {
                ForEach(personItems, id: \.title) { item in
                    familyFilterRow(
                        title: item.title,
                        subtitle: "\(item.count)",
                        systemImage: "person.fill",
                        isSelected: store.selectedFamilyInfoPerson == item.title
                    ) {
                        store.selectedFamilyInfoPerson = item.title
                    }
                }
            }

            Section("Types") {
                ForEach(typeItems, id: \.rawType) { item in
                    familyFilterRow(
                        title: item.title,
                        subtitle: "\(item.count)",
                        systemImage: item.icon,
                        isSelected: store.selectedFamilyInfoType == item.rawType
                    ) {
                        store.selectedFamilyInfoType = item.rawType
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Database")
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            reload()
        }
    }

    private var personItems: [(title: String, count: Int)] {
        Dictionary(grouping: rows) { row in
            row.personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : row.personName
        }
        .map { (title: $0.key, count: $0.value.count) }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var typeItems: [(rawType: String, title: String, icon: String, count: Int)] {
        Dictionary(grouping: rows) { row in
            row.documentType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "other" : row.documentType
        }
        .map { key, value in
            (
                rawType: key,
                title: key.replacingOccurrences(of: "_", with: " ").capitalized,
                icon: icon(for: key),
                count: value.count
            )
        }
        .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    @ViewBuilder
    private func familyFilterRow(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .foregroundStyle(isSelected ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.secondary))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.accentColor)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
                .padding(.vertical, 2)
        )
    }

    private func icon(for rawType: String) -> String {
        switch rawType {
        case "passport": return "globe"
        case "driver_license": return "car.fill"
        case "identity_card": return "person.text.rectangle.fill"
        case "travel_permit": return "airplane"
        case "vaccine_record": return "cross.case.fill"
        case "medical_record": return "cross.vial.fill"
        default: return "folder"
        }
    }

    private func reload() {
        rows = store.notes.listRenewalItems(ownerScope: "ME")
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
                                .lineLimit(1)
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
