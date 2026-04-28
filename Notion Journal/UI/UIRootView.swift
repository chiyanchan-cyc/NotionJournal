import SwiftUI
import UIKit
import Combine

struct RootView: View {
    @EnvironmentObject var store: AppStore
    @State private var selectedNoteID: NJNoteID?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openWindow) private var openWindow
    @State private var syncTick: Int = 0
    @State private var showProtonListLab: Bool = false
    @State private var splitViewVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        GeometryReader { proxy in
            let isPhoneLandscape = UIDevice.current.userInterfaceIdiom == .phone && proxy.size.width > proxy.size.height
            let isPhonePortrait = UIDevice.current.userInterfaceIdiom == .phone && proxy.size.height >= proxy.size.width

            Group {
                if store.sync.initialPullCompleted {
                    if isPhonePortrait && store.selectedModule == .investment {
                        NavigationStack {
                            NJInvestmentModuleView()
                                .environmentObject(store)
                                .toolbar {
                                    ToolbarItem(placement: .topBarLeading) {
                                        Button {
                                            store.selectedModule = .note
                                            splitViewVisibility = .all
                                        } label: {
                                            Label("Modules", systemImage: "sidebar.left")
                                        }
                                    }
                                }
                        }
                        .onAppear {
                            runActivationTasks()
                        }
                        .onChange(of: scenePhase) { ph in
                            if ph == .active {
                                runActivationTasks()
                            }
                        }
                    } else {
                        NavigationSplitView(columnVisibility: $splitViewVisibility) {
                            Sidebar(
                                selectedNoteID: $selectedNoteID,
                                onRequestDetailFocus: {
                                    splitViewVisibility = .detailOnly
                                }
                            )
                        } detail: {
                            switch store.selectedModule {
                            case .note:
                                if let id = selectedNoteID {
                                    NJNoteEditorContainerView(noteID: id)
                                        .id(String(describing: id))
            //                            .toolbar {
            //                                ToolbarItem(placement: .topBarTrailing) {
            //                                    Button {
            //                                        showProtonListLab = true
            //                                    } label: {
            //                                        Image(systemName: "ladybug")
            //                                    }
            //                                }
            //                            }
                                        .sheet(isPresented: $showProtonListLab) {
            //                                NavigationStack {
            //                                    NJProtonListLabView()
            //                                }
                                        }
                                } else {
                                    ContentUnavailableView("Select a note", systemImage: "doc.text")
                                }
                            case .goal:
                                if let gid = store.selectedGoalID {
                                    NJGoalDetailWorkspaceView(goalID: gid)
                                        .environmentObject(store)
                                } else {
                                    NJGoalJournalDashboardView()
                                        .environmentObject(store)
                                }
                            case .outline:
                                if let id = store.selectedOutlineID {
                                    NJOutlineDetailView(outline: store.outline, outlineID: id)
                                        .environmentObject(store)
                                } else {
                                    ContentUnavailableView("Select an outline", systemImage: "list.bullet.rectangle")
                                }
                            case .time:
                                NJTimeModuleView()
                                    .environmentObject(store)
                            case .investment:
                                NJInvestmentModuleView()
                                    .environmentObject(store)
                            case .planning:
                                NJCalendarView()
                                    .environmentObject(store)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            if isPhoneLandscape {
                                sidebarToggleButton
                                    .padding(.top, 10)
                                    .padding(.leading, 10)
                            }
                        }
                        .onAppear {
                            runActivationTasks()
                        }
                        .onChange(of: scenePhase) { ph in
                            if ph == .active {
                                runActivationTasks()
                            }
                        }
                        .onChange(of: store.selectedNotebookID) { _ in
                            NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                        }
                        .onChange(of: store.selectedTabID) { _ in
                            NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
                        }
                        .onChange(of: isPhoneLandscape) { active in
                            if !active {
                                splitViewVisibility = .all
                            }
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .njOpenLinkedNote)) { note in
                            openLinkedNote(note)
                        }
                        .onReceive(NotificationCenter.default.publisher(for: .njOpenLinkedView)) { note in
                            openLinkedView(note)
                        }
                    }

                } else {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Syncing…")
                            .font(.headline)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .onReceive(store.sync.objectWillChange) { _ in
            syncTick += 1
        }
        .alert("Goals Updated", isPresented: $store.showGoalMigrationAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Updated \(store.goalMigrationCount) goal(s) to In Progress based on goal tags.")
        }
    }

    private var sidebarToggleButton: some View {
        Button {
            splitViewVisibility = splitViewVisibility == .detailOnly ? .all : .detailOnly
        } label: {
            Image(systemName: splitViewVisibility == .detailOnly ? "sidebar.left" : "sidebar.leading")
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 36, height: 36)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(splitViewVisibility == .detailOnly ? "Show side panel" : "Hide side panel")
        .shadow(color: Color.black.opacity(0.12), radius: 8, y: 2)
    }

    private func runActivationTasks() {
        store.runClipIngestIfNeeded()
        store.runAudioIngestIfNeeded()
        store.runAudioTranscribeIfNeeded()
        store.runTimeModuleInboxIngestIfNeeded()
        store.syncOnAppActivationIfNeeded()
        store.syncTimeSlotOverrunNotifications()
        store.publishTimeSlotWidgetSnapshot()
        NJLocalBLRunner(db: store.db).run(.deriveBlockTagIndexAndDomainV1)
        NJHealthLogger.shared.configure(db: store.db)
        NJHealthLogger.shared.appDidBecomeActive()
        NJGPSLogger.shared.refreshAuthorityUI()
    }

    private func openLinkedNote(_ notification: Notification) {
        guard let noteID = NJExternalFileLinkSupport.linkedNoteID(from: notification),
              let note = store.notes.getNote(NJNoteID(noteID)) else { return }
        store.selectedModule = .note
        if let notebook = store.notebooks.first(where: { $0.title == note.notebook }) {
            store.selectNotebook(notebook.notebookID)
        }
        if let tab = store.tabs.first(where: { $0.domainKey == note.tabDomain }) {
            store.selectTab(tab.tabID)
        }
        selectedNoteID = note.id
    }

    private func openLinkedView(_ notification: Notification) {
        guard let payload = NJExternalFileLinkSupport.linkedViewPayload(from: notification),
              !payload.isEmpty else { return }
        openWindow(id: "reconstructed-manual", value: payload)
    }
}

private struct NJRenewalPrioritySummary: Identifiable {
    let id: String
    let title: String
    let count: Int
    let color: Color
}

struct NJRenewalsModuleView: View {
    @EnvironmentObject var store: AppStore

    @State private var searchText: String = ""
    @State private var rows: [NJRenewalItemRecord] = []

    var body: some View {
        List {
            Section {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(summaryChips) { chip in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(chip.title)
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(chip.color)
                                Text("\(chip.count)")
                                    .font(.title3.weight(.bold))
                            }
                            .frame(width: 92, alignment: .leading)
                            .padding(12)
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(chip.color.opacity(0.12))
                            )
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            }

            if filterSummaryText != "All records" {
                Section {
                    HStack(spacing: 10) {
                        Label(filterSummaryText, systemImage: "line.3.horizontal.decrease.circle")
                            .font(.subheadline.weight(.semibold))
                        Spacer(minLength: 8)
                        Button("Clear") {
                            store.selectedFamilyInfoPerson = "All"
                            store.selectedFamilyInfoType = "All"
                        }
                        .font(.subheadline)
                    }
                }
            }

            if filteredRows.isEmpty {
                Section {
                    ContentUnavailableView(
                        "No Personal ID cards",
                        systemImage: "person.text.rectangle",
                        description: Text("Add or sync passports, licenses, permits, and IDs here.")
                    )
                    .frame(maxWidth: .infinity, minHeight: 220)
                }
            } else {
                ForEach(groupedRows, id: \.key) { group in
                    Section(group.key) {
                        ForEach(group.value, id: \.renewalItemID) { row in
                            renewalRow(row)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Database")
        .searchable(text: $searchText, prompt: "Search person or document")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    reload()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
            }
        }
        .onAppear(perform: reload)
    }

    private var filteredRows: [NJRenewalItemRecord] {
        rows.filter { row in
            let matchesPerson = store.selectedFamilyInfoPerson == "All" || row.personName == store.selectedFamilyInfoPerson
            let matchesType = store.selectedFamilyInfoType == "All" || normalizedType(for: row) == store.selectedFamilyInfoType
            let term = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            let haystack = [row.personName, row.documentName, row.documentType, row.jurisdiction, row.notes]
                .joined(separator: " ")
                .lowercased()
            let matchesSearch = term.isEmpty || haystack.contains(term.lowercased())
            return matchesPerson && matchesType && matchesSearch
        }
    }

    private var filterSummaryText: String {
        let person = store.selectedFamilyInfoPerson
        let type = store.selectedFamilyInfoType
        if person == "All" && type == "All" { return "All records" }
        if person != "All" && type != "All" {
            return "\(person) • \(type.replacingOccurrences(of: "_", with: " ").capitalized)"
        }
        if person != "All" { return person }
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private var summaryChips: [NJRenewalPrioritySummary] {
        [
            NJRenewalPrioritySummary(id: "critical", title: "Critical", count: rows.filter { $0.priority == "critical" }.count, color: deepCriticalRed),
            NJRenewalPrioritySummary(id: "high", title: "High", count: rows.filter { $0.priority == "high" }.count, color: .orange),
            NJRenewalPrioritySummary(id: "review", title: "Review", count: rows.filter { $0.priority == "review" || $0.status == "missing_date" }.count, color: .blue),
            NJRenewalPrioritySummary(id: "active", title: "Active", count: rows.filter { $0.status == "active" }.count, color: .green)
        ]
    }

    private var groupedRows: [(key: String, value: [NJRenewalItemRecord])] {
        let grouped = Dictionary(grouping: filteredRows) { row in
            row.personName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Unknown" : row.personName
        }
        return grouped
            .map { key, value in (key: key, value: sortRows(value)) }
            .sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }
    }

    private func sortRows(_ items: [NJRenewalItemRecord]) -> [NJRenewalItemRecord] {
        items.sorted {
            let leftRank = priorityRank($0.priority)
            let rightRank = priorityRank($1.priority)
            if leftRank != rightRank { return leftRank < rightRank }

            let leftKey = $0.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let rightKey = $1.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if leftKey.isEmpty != rightKey.isEmpty { return !leftKey.isEmpty }
            if leftKey != rightKey { return leftKey < rightKey }
            return $0.documentName.localizedCaseInsensitiveCompare($1.documentName) == .orderedAscending
        }
    }

    @ViewBuilder
    private func renewalRow(_ row: NJRenewalItemRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.documentName)
                        .font(.headline)
                    Text(subtitle(for: row))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text(priorityLabel(for: row))
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(priorityColor(for: row).opacity(0.14), in: Capsule())
                    .foregroundStyle(priorityColor(for: row))
            }

            HStack(spacing: 8) {
                Label(expiryLabel(for: row), systemImage: "calendar")
                    .font(.subheadline)
                Spacer(minLength: 0)
                Text(statusText(for: row))
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(statusColor(for: row))
            }

            if !row.notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(row.notes)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func subtitle(for row: NJRenewalItemRecord) -> String {
        [row.documentTypeLabel, row.jurisdiction]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func priorityRank(_ priority: String) -> Int {
        switch priority {
        case "critical": return 0
        case "high": return 1
        case "medium": return 2
        case "low": return 3
        case "review": return 4
        default: return 5
        }
    }

    private func priorityLabel(for row: NJRenewalItemRecord) -> String {
        if row.priority == "review" || row.status == "missing_date" { return "Review" }
        return row.priority.replacingOccurrences(of: "_", with: " ").capitalized
    }

    private func priorityColor(for row: NJRenewalItemRecord) -> Color {
        switch row.priority {
        case "critical": return deepCriticalRed
        case "high": return .orange
        case "medium": return .yellow
        case "low": return .green
        case "review": return .blue
        default: return .secondary
        }
    }

    private func statusText(for row: NJRenewalItemRecord) -> String {
        switch row.status {
        case "expired": return "Expired"
        case "due_soon": return "Due Soon"
        case "active": return "Active"
        case "missing_date": return "Missing Date"
        default: return row.status.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    private func statusColor(for row: NJRenewalItemRecord) -> Color {
        switch row.status {
        case "expired": return deepCriticalRed
        case "due_soon": return .orange
        case "active": return .green
        case "missing_date": return .blue
        default: return .secondary
        }
    }

    private var deepCriticalRed: Color {
        Color(red: 0.55, green: 0.0, blue: 0.0)
    }

    private func expiryLabel(for row: NJRenewalItemRecord) -> String {
        let key = row.expiryDateKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "Date needed" }
        return key
    }

    private func reload() {
        rows = store.notes.listRenewalItems(ownerScope: "ME")
    }

    private func normalizedType(for row: NJRenewalItemRecord) -> String {
        let trimmed = row.documentType.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "other" : trimmed
    }
}

private extension NJRenewalItemRecord {
    var documentTypeLabel: String {
        documentType
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}
