import SwiftUI
import Combine
import UIKit
import SQLite3
import PDFKit
import PhotosUI

import os

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")


private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

private enum NJCardEmbeddedViewKind: String, CaseIterable, Identifiable {
    case rows = "rows"
    case transactionLedger = "transaction_ledger"
    case investmentPosition = "investment_position"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rows: return "Rows"
        case .transactionLedger: return "Transaction Ledger"
        case .investmentPosition: return "Investment Position"
        }
    }
}

private struct NJCardInvestmentExecution: Identifiable {
    let id: String
    let dateKey: String
    let thesis: String
    let tradeCode: String
    let region: String
    let orderRef: String
    let institution: String
    let accountLabel: String
    let symbol: String
    let side: String
    let quantity: Double
    let price: Double
    let currency: String
    let fees: Double?
}

private struct NJCardInvestmentLot: Identifiable {
    let id: String
    let dateKey: String
    let orderRef: String
    var quantity: Double
    let costPerShare: Double

    var cost: Double { quantity * costPerShare }
}

private struct NJCardInvestmentPosition: Identifiable {
    let id: String
    let thesis: String
    let tradeCode: String
    let region: String
    let symbol: String
    let institutions: [String]
    let currency: String
    let quantity: Double
    let averageCost: Double
    let openCost: Double
    let realizedPL: Double
    let currentPrice: Double?
    let lots: [NJCardInvestmentLot]

    var marketValue: Double? { currentPrice.map { quantity * $0 } }
    var unrealizedPL: Double? { marketValue.map { $0 - openCost } }
    var unrealizedPct: Double? {
        guard openCost != 0, let unrealizedPL else { return nil }
        return unrealizedPL / openCost * 100
    }
}

struct NJNoteEditorContainerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase
    let noteID: NJNoteID

    @StateObject var persistence = NJNoteEditorContainerPersistence()

    @State var loaded = false
    @State var pendingFocusID: UUID? = nil
    @State var pendingFocusToStart: Bool = false
    @State var editMode: EditMode = .inactive
    @State var lastBreakAtMs: Int64 = 0
    @State var lastSplitSig: (UUID, Int, Int, Int)? = nil
    @State var lastSplitSigAtMs: Int64 = 0
    @State var blockBus = NJBlockEventBus()

    private struct NJPDFSheetItem: Identifiable {
        let id = UUID()
        let url: URL
    }

    @State private var clipPDFSheet: NJPDFSheetItem? = nil

    @State private var showClipboardInbox = false
    @State private var pickedPhotoItem: PhotosPickerItem? = nil
    @State private var showGoalQuickPick = false
    @State private var showRemoteAppliedHint = false
    @AppStorage("nj_note_editor_show_finished_blocks") private var showFinishedBlocks = false
    @AppStorage("nj_card_show_done_blocks") private var showDoneCardBlocks = false
    @State private var showNoteConfigurator = false
    @State private var cardSortColumn: NJCardTableColumn = .rowID
    @State private var cardSortAscending = true
    @State private var cardFilterPriority: String = ""
    @State private var cardFilterStatus: String = ""
    @State private var cardFilterCategory: String = ""
    @State private var cardFilterArea: String = ""
    @State private var cardFilterContext: String = ""
    @State private var cardColumnOrder: [NJCardTableColumn] = NJCardTableColumn.allCases
    @State private var hiddenCardColumns: Set<NJCardTableColumn> = []
    @State private var cardColumnWidths: [NJCardTableColumn: CGFloat] = [:]
    @State private var cardTableFontScale: Double = 1.0
    @State private var cardResizeStartWidths: [NJCardTableColumn: CGFloat] = [:]
    @State private var presentedCardFilterColumn: NJCardTableColumn? = nil
    @State private var selectedCardBlockItem: NJCardBlockSheetItem? = nil
    @State private var selectedCardEmbeddedView: NJCardEmbeddedViewKind = .rows
    @State private var cardInvestmentPrices: [String: Double] = [:]
    @State private var cardInvestmentPriceStatus: [String: String] = [:]

    private struct NJGoalSheetItem: Identifiable {
        let id = UUID()
        let blockID: String
    }

    private enum NJCardTableColumn: String, CaseIterable, Identifiable {
        case rowID = "row_id"
        case status = "status"
        case priority = "priority"
        case category = "category"
        case area = "area"
        case context = "context"
        case title = "title"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .rowID: return "ID"
            case .status: return "Status"
            case .priority: return "Priority"
            case .category: return "Category"
            case .area: return "Area"
            case .context: return "Context"
            case .title: return "Title"
            }
        }
    }

    private struct NJPersonalIdentificationCardFields {
        var person: String
        var document: String
        var documentType: String
        var jurisdiction: String
        var expiryDate: String
        var documentNumber: String
    }

    private struct NJCardBlockSheetItem: Identifiable {
        let id: UUID
    }

    @State private var goalSheetItem: NJGoalSheetItem? = nil
    @State private var lastGoalBlockID: String? = nil

    private var currentNote: NJNote? {
        store.notes.getNote(noteID)
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(persistence.tab.isEmpty ? "" : persistence.tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                HStack(spacing: 8) {
                    TextField(persistence.noteType == .card ? "Card Name" : "Title", text: $persistence.title)
                        .font(.title2)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: persistence.title) { _ in
                            persistence.scheduleNoteMetaCommit()
                        }

                    Button {
                        UIPasteboard.general.string = noteID.raw
                    } label: {
                        Image(systemName: "number")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 34, height: 34)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Copy Note ID")
                }

                if persistence.noteType == .note {
                    noteConfigurator()
                } else if persistence.noteType == .card {
                    cardViewChooser()
                }
            }
            
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            if persistence.noteType == .card {
                switch selectedCardEmbeddedView {
                case .rows:
                    cardTableView()
                case .transactionLedger:
                    cardInvestmentTransactionLedgerView()
                case .investmentPosition:
                    cardInvestmentPositionView()
                }
            } else {
                List {
                    ForEach(displayedBlocks, id: \.id) { b in
                        standardBlockRow(b)
                    }
                    .onMove(perform: moveBlocks)

                    NJBlockListBottomRunwayRow()
                }
                .listStyle(.plain)
                .environment(\.editMode, $editMode)
            }
        }
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
//        .overlay(NJContainerKeyCommands(getHandle: { focusedHandle() })
//            .frame(width: 0, height: 0)
//            .allowsHitTesting(false)
//        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                statusStrip()
                if let h = focusedHandle() {
                    NJProtonFloatingFormatBar(
                        handle: h,
                        pickedPhotoItem: $pickedPhotoItem,
                        currentHandle: { focusedHandle() }
                    )
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                }
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                
                Button {
                    if let id = persistence.focusedBlockID {
                        persistence.forceEndEditingAndCommitNow(id)
                    }
                    showClipboardInbox = true
                } label: {
                    Image(systemName: "doc.on.clipboard")
                        .overlay(alignment: .topTrailing) {
                            NJBadgeCountView(count: store.quickClipboardCount)
                                .offset(x: 6, y: -6)
                        }
                }

                Button {
                    showGoalQuickPick = true
                } label: {
                    Image(systemName: "target")
                }

                Button {
                    let isFavorited = (currentNote?.favorited ?? 0) > 0
                    store.notes.setFavorited(noteID: noteID.raw, favorited: !isFavorited)
                    store.objectWillChange.send()
                } label: {
                    Image(systemName: (currentNote?.favorited ?? 0) > 0 ? "star.fill" : "star")
                        .foregroundStyle((currentNote?.favorited ?? 0) > 0 ? .yellow : .primary)
                }

                Button {
                    editMode = (editMode == .active) ? .inactive : .active
                } label: {
                    Image(systemName: editMode == .active ? "checkmark.circle" : "arrow.up.arrow.down")
                }

                Button {
                    addBlock(after: nil)
                } label: {
                    Image(systemName: persistence.focusedBlockID == nil ? "plus.square" : "square.on.square")
                }

                Button(role: .destructive) {
                    if let id = persistence.focusedBlockID { deleteBlock(id) }
                } label: {
                    Image(systemName: "trash")
                }

                Button(role: .destructive) {
                    deleteWholeNote()
                } label: {
                    Image(systemName: "trash.fill")
                }
            }
        }

        .sheet(item: $clipPDFSheet) { item in
            NJPDFQuickView(url: item.url)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }

        .sheet(item: $goalSheetItem, onDismiss: {
            if let blockID = lastGoalBlockID {
                persistence.refreshGoalPreview(blockID: blockID)
                lastGoalBlockID = nil
            }
        }) { item in
            NJGoalCreateSheet(
                repo: store.notes,
                originBlockID: item.blockID
            )
        }
        .sheet(isPresented: $showGoalQuickPick) {
            NJGoalQuickPickSheet { picked in
                addTaggedBlocks(after: persistence.focusedBlockID, goals: picked)
            }
            .environmentObject(store)
        }

        .sheet(isPresented: $showClipboardInbox) {
            NJClipboardInboxView(
                noteID: noteID.raw,
                onImported: {
                    persistence.reload(makeHandle: makeWiredHandle)
                }
            )
            .environmentObject(store)
        }
        .sheet(item: $selectedCardBlockItem) { item in
            NavigationStack {
                cardBlockDetailSheet(item.id)
                    .navigationTitle("Block")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Save") {
                                saveCardBlockSheet(item.id)
                            }
                            .fontWeight(.semibold)
                        }
                    }
                    .safeAreaInset(edge: .bottom, spacing: 0) {
                        if let h = focusedHandle() {
                            NJProtonFloatingFormatBar(
                                handle: h,
                                pickedPhotoItem: $pickedPhotoItem,
                                currentHandle: { focusedHandle() }
                            )
                            .padding(.horizontal, 8)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                        }
                    }
            }
            .environmentObject(store)
        }

        .task {
            if loaded { return }
            loaded = true
            persistence.configure(store: store, noteID: noteID)
            blockBus.setHandler { e in handleBlockEvent(e) }
            loadCardTablePreferences()
            loadCardEmbeddedViewPreference()
            persistence.reload(makeHandle: makeWiredHandle)
        }
        .onReceive(NotificationCenter.default.publisher(for: .njPullCompleted)) { _ in
            applyRemoteRefreshIfPossible(forcePending: true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .njForceReloadNote)) { _ in
            applyRemoteRefreshIfPossible(forcePending: true)
        }
        .onChange(of: persistence.hasPendingNoteMetaChanges) { _, _ in
            applyRemoteRefreshIfPossible(forcePending: false)
        }
        .onDisappear {
            persistence.commitNoteMetaNow()
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .inactive || phase == .background {
                persistence.commitNoteMetaNow()
                persistence.forceEndEditingAndCommitAllDirtyNow()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            persistence.commitNoteMetaNow()
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didEnterBackgroundNotification)) { _ in
            persistence.commitNoteMetaNow()
            persistence.forceEndEditingAndCommitAllDirtyNow()
        }
    }

    func waitForICloudFile(_ u: URL, maxWaitSeconds: Double) async -> Bool {
        let fm = FileManager.default

        try? fm.startDownloadingUbiquitousItem(at: u)

        let deadline = Date().timeIntervalSince1970 + maxWaitSeconds

        while Date().timeIntervalSince1970 < deadline {
            if let st = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))
                .flatMap({ $0.ubiquitousItemDownloadingStatus }) {
                if st == .current { return true }
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        if let st = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]))
            .flatMap({ $0.ubiquitousItemDownloadingStatus }) {
            return st == .current
        }

        return false
    }

    private func isLikelyPDF(_ u: URL) -> Bool {
        let ext = u.pathExtension.lowercased()
        return ext == "pdf"
    }

    private func firstLinePreview(_ attr: NSAttributedString) -> String {
        let s = attr.string
            .replacingOccurrences(of: "\u{FFFC}", with: "")
            .replacingOccurrences(of: "\u{200B}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "" }
        return s.split(whereSeparator: \.isNewline).first.map { String($0) } ?? ""
    }

    private func clipPDFURLFromRel(_ rel: String) -> URL? {
        let r = rel.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.isEmpty { return nil }
        if r.hasPrefix("/") { return URL(fileURLWithPath: r) }
        guard let base = FileManager.default.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") else { return nil }

        if r.hasPrefix("Documents/") {
            let tail = String(r.dropFirst("Documents/".count))
            return base.appendingPathComponent("Documents", isDirectory: true).appendingPathComponent(tail, isDirectory: false)
        }

        return base.appendingPathComponent(r)
    }
    private func openClipPDFRel(_ rel: String) {
        guard let u = clipPDFURLFromRel(rel) else { return }

        Task {
            let ready = await waitForICloudFile(u, maxWaitSeconds: 15.0)

            guard ready else {
                await MainActor.run {
                    if shouldUseWindowForPDF {
                        openWindow(id: "clip-pdf", value: u)
                    } else {
                        clipPDFSheet = NJPDFSheetItem(url: u)
                    }
                }
                return
            }

            let local = await materializeToTemp(u)

            await MainActor.run {
                let target = local ?? u
                if shouldUseWindowForPDF {
                    openWindow(id: "clip-pdf", value: target)
                } else {
                    clipPDFSheet = NJPDFSheetItem(url: target)
                }
            }
        }
    }

    private func focusedHandle() -> NJProtonEditorHandle? {
        guard let id = persistence.focusedBlockID else { return nil }
        return persistence.blocks.first(where: { $0.id == id })?.protonHandle
    }

    private func statusStrip() -> some View {
        let (text, color) = currentStatus()
        return HStack {
            Text(text)
                .font(.caption2)
                .foregroundStyle(color)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .background(.ultraThinMaterial)
    }

    private func currentStatus() -> (String, Color) {
        if persistence.hasPendingRemoteRefresh {
            return ("Remote updates pending. They will apply after your local edits finish.", .orange)
        }
        if showRemoteAppliedHint {
            return ("Remote updates applied.", .green)
        }
        if persistence.hasActivelyEditingBlock() || persistence.blocks.contains(where: { $0.isDirty }) {
            return ("You are editing. Local changes are being saved and synced.", .secondary)
        }
        return ("", .clear)
    }

    private func applyRemoteRefreshIfPossible(forcePending: Bool) {
        if forcePending {
            persistence.markPendingRemoteRefresh()
        }
        guard persistence.hasPendingRemoteRefresh else { return }
        if !persistence.hasRemoteContentUpdateAvailable() {
            persistence.clearPendingRemoteRefresh()
            return
        }
        let hasPendingLocalEdits = persistence.blocks.contains { $0.isDirty }
        if hasPendingLocalEdits || persistence.hasActivelyEditingBlock() || persistence.hasPendingNoteMetaChanges {
            return
        }
        persistence.reload(makeHandle: makeWiredHandle)
        showRemoteAppliedHint = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            showRemoteAppliedHint = false
        }
    }

    private func mergeTagJSONWithInherited(json: String, inheritedTags: [String]) -> String {
        let base: [String] = {
            guard let data = json.data(using: .utf8),
                  let arr = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { return [] }
            return arr
        }()
        if inheritedTags.isEmpty { return json }
        var merged = base
        for t in inheritedTags {
            let tt = t.trimmingCharacters(in: .whitespacesAndNewlines)
            if tt.isEmpty { continue }
            if merged.contains(where: { $0.caseInsensitiveCompare(tt) == .orderedSame }) { continue }
            merged.append(tt)
        }
        if let data = try? JSONSerialization.data(withJSONObject: merged),
           let s = String(data: data, encoding: .utf8) {
            return s
        }
        return json
    }

    func bindingAttr(_ id: UUID) -> Binding<NSAttributedString> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.attr ?? makeEmptyBlockAttr() },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    let prev = persistence.focusedBlockID
                    if prev != persistence.blocks[i].id {
                        if let prev { persistence.forceEndEditingAndCommitNow(prev) }
                        persistence.focusedBlockID = persistence.blocks[i].id
                    }
                    if !persistence.blocks[i].attr.isEqual(to: v) {
                        persistence.blocks[i].attr = v
                        persistence.blocks[i].sel = clampSelectionRange(
                            persistence.blocks[i].sel,
                            textLength: v.length
                        )
                    }
                }
            }
        )
    }


    func bindingSel(_ id: UUID) -> Binding<NSRange> {
        Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.sel ?? NSRange(location: 0, length: 0) },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    let prev = persistence.focusedBlockID
                    if prev != persistence.blocks[i].id {
                        if let prev { persistence.forceEndEditingAndCommitNow(prev) }
                        persistence.focusedBlockID = persistence.blocks[i].id
                    }
                    persistence.blocks[i].sel = clampSelectionRange(v, textLength: persistence.blocks[i].attr.length)
                }
            }
        )
    }

}

private func clampSelectionRange(_ range: NSRange, textLength: Int) -> NSRange {
    let safeLen = max(0, textLength)
    if safeLen == 0 { return NSRange(location: 0, length: 0) }

    let start = min(max(0, range.location), safeLen)
    let remaining = max(0, safeLen - start)
    let len = min(max(0, range.length), remaining)
    return NSRange(location: start, length: len)
}

private extension NJNoteEditorContainerView {
    var isInvestmentLedgerCard: Bool {
        guard persistence.noteType == .card else { return false }
        return persistence.cardCategory.caseInsensitiveCompare("Investment Ledger") == .orderedSame ||
            persistence.cardCategory.caseInsensitiveCompare("Investment Transaction") == .orderedSame
    }

    var cardEmbeddedViewPreferenceKey: String {
        "nj_card_embedded_view_\(noteID.raw)"
    }

    func loadCardEmbeddedViewPreference() {
        guard let raw = UserDefaults.standard.string(forKey: cardEmbeddedViewPreferenceKey),
              let view = NJCardEmbeddedViewKind(rawValue: raw)
        else {
            selectedCardEmbeddedView = isInvestmentLedgerCard ? .transactionLedger : .rows
            return
        }
        if isInvestmentLedgerCard && view == .rows {
            selectedCardEmbeddedView = .transactionLedger
            return
        }
        selectedCardEmbeddedView = isInvestmentLedgerCard || view == .rows ? view : .rows
    }

    func persistCardEmbeddedViewPreference() {
        if selectedCardEmbeddedView != .rows && !isInvestmentLedgerCard {
            selectedCardEmbeddedView = .rows
        }
        UserDefaults.standard.set(selectedCardEmbeddedView.rawValue, forKey: cardEmbeddedViewPreferenceKey)
    }

    var cardPriorityOptions: [String] {
        if isPersonalIdentificationCard {
            return ["Low", "Review", "Medium", "High", "Critical"]
        }
        return ["Low", "Medium", "High"]
    }

    var cardStatusOptions: [String] {
        if isPersonalIdentificationCard {
            return ["Active", "Due Soon", "Expired", "Missing Date", "Review", "Pending"]
        }
        return ["Pending", "TBT", "Done"]
    }

    func cardStatusRank(_ value: String) -> Int {
        switch value.lowercased() {
        case "active": return 0
        case "due soon": return 1
        case "missing date", "review": return 2
        case "expired": return 3
        case "pending": return 0
        case "tbt": return 1
        case "done": return 2
        default: return 3
        }
    }

    func cardPriorityRank(_ value: String) -> Int {
        switch value.lowercased() {
        case "critical": return 0
        case "high": return 0
        case "review": return 1
        case "medium": return 2
        case "low": return 3
        default: return 3
        }
    }

    private var isPersonalIdentificationCard: Bool {
        guard persistence.noteType == .card else { return false }
        let title = persistence.title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let context = persistence.cardContext.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let cardID = persistence.cardID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return title == "personal identification"
            || context == "personal identification"
            || cardID == "db-personal-id"
    }

    private func cardColumnTitle(_ column: NJCardTableColumn) -> String {
        guard isPersonalIdentificationCard else { return column.title }
        switch column {
        case .rowID: return "ID"
        case .status: return "Status"
        case .priority: return "Urgency"
        case .category: return "Type"
        case .area: return "Person"
        case .context: return "Details"
        case .title: return "Document"
        }
    }

    private func personalIdentificationFields(from block: NJNoteEditorContainerPersistence.BlockState) -> NJPersonalIdentificationCardFields {
        let titleParts = block.cardTitle
            .split(separator: "-", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let document = titleParts.count == 2 ? titleParts[1] : block.cardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let contextParts = block.cardContext
            .replacingOccurrences(of: "•", with: "|")
            .split(separator: "|")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return NJPersonalIdentificationCardFields(
            person: block.cardArea,
            document: document,
            documentType: block.cardCategory,
            jurisdiction: contextParts.indices.contains(0) ? contextParts[0] : "",
            expiryDate: contextParts.indices.contains(1) ? contextParts[1] : "",
            documentNumber: contextParts.indices.contains(2) ? contextParts[2] : ""
        )
    }

    private func personalIdentificationContext(jurisdiction: String, expiryDate: String, documentNumber: String) -> String {
        [jurisdiction, expiryDate, documentNumber]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " • ")
    }

    private func personalIdentificationTitle(person: String, document: String) -> String {
        let cleanPerson = person.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanDocument = document.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanPerson.isEmpty { return cleanDocument }
        if cleanDocument.isEmpty { return cleanPerson }
        return "\(cleanPerson) - \(cleanDocument)"
    }

    func cardDisplayTitle(_ block: NJNoteEditorContainerPersistence.BlockState) -> String {
        let explicit = block.cardTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty { return explicit }
        let fallback = firstLinePreview(block.attr).trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? "Untitled block" : fallback
    }

    private var visibleCardColumns: [NJCardTableColumn] {
        let ordered = cardColumnOrder.isEmpty ? NJCardTableColumn.allCases : cardColumnOrder
        let known = Set(ordered)
        let remainder = NJCardTableColumn.allCases.filter { !known.contains($0) }
        return (ordered + remainder).filter { !hiddenCardColumns.contains($0) }
    }

    private func cardColumnWidth(_ column: NJCardTableColumn) -> CGFloat {
        if let width = cardColumnWidths[column], width > 0 {
            return width
        }
        switch column {
        case .rowID: return 90
        case .status: return 110
        case .priority: return 110
        case .category: return 150
        case .area: return 150
        case .context: return 220
        case .title: return 280
        }
    }

    private func cardColumnValue(_ column: NJCardTableColumn, for block: NJNoteEditorContainerPersistence.BlockState) -> String {
        switch column {
        case .rowID:
            return block.cardRowID.isEmpty ? "-" : block.cardRowID
        case .status:
            return block.cardStatus.isEmpty ? "Pending" : block.cardStatus
        case .priority:
            return block.cardPriority.isEmpty ? "Medium" : block.cardPriority
        case .category:
            return block.cardCategory
        case .area:
            return block.cardArea
        case .context:
            return block.cardContext
        case .title:
            return cardDisplayTitle(block)
        }
    }

    private func cardFilterBinding(for column: NJCardTableColumn) -> Binding<String>? {
        switch column {
        case .status: return $cardFilterStatus
        case .priority: return $cardFilterPriority
        case .category: return $cardFilterCategory
        case .area: return $cardFilterArea
        case .context: return $cardFilterContext
        case .rowID, .title: return nil
        }
    }

    private func cardColumnHasFilter(_ column: NJCardTableColumn) -> Bool {
        cardFilterBinding(for: column) != nil
    }

    private func cardFilterValues(for column: NJCardTableColumn) -> [String] {
        let values: [String] = persistence.blocks.map { block in
            switch column {
            case .status: return block.cardStatus.isEmpty ? "Pending" : block.cardStatus
            case .priority: return block.cardPriority.isEmpty ? "Medium" : block.cardPriority
            case .category: return block.cardCategory
            case .area: return block.cardArea
            case .context: return block.cardContext
            case .rowID, .title: return ""
            }
        }
        return Array(Set(values.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty })).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    func cardDeviceBucket() -> String {
        switch UIDevice.current.userInterfaceIdiom {
        case .phone: return "phone"
        case .pad: return "pad"
        case .mac: return "mac"
        default: return "default"
        }
    }

    func cardColumnOrderKey() -> String {
        "nj_card_column_order_\(cardDeviceBucket())"
    }

    func cardHiddenColumnsKey() -> String {
        "nj_card_hidden_columns_\(cardDeviceBucket())"
    }

    func cardColumnWidthsKey() -> String {
        "nj_card_column_widths_\(cardDeviceBucket())"
    }

    func cardTableFontScaleKey() -> String {
        "nj_card_table_font_scale_\(cardDeviceBucket())"
    }

    private func clampedCardTableFontScale(_ value: Double) -> Double {
        min(max(value, 0.85), 1.35)
    }

    private func cardTableScaledFont(_ base: CGFloat, weight: Font.Weight? = nil) -> Font {
        let size = CGFloat(clampedCardTableFontScale(cardTableFontScale)) * base
        if let weight {
            return .system(size: size, weight: weight)
        }
        return .system(size: size)
    }

    private func adjustCardTableFontScale(delta: Double) {
        cardTableFontScale = clampedCardTableFontScale(cardTableFontScale + delta)
        persistCardTablePreferences()
    }

    private func resetCardTableFontScale() {
        cardTableFontScale = 1.0
        persistCardTablePreferences()
    }

    private func cardPriorityColor(_ value: String, isSecondary: Bool = false) -> Color {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "critical":
            return Color(red: 0.55, green: 0.0, blue: 0.0)
        case "high":
            return Color(red: 0.82, green: 0.08, blue: 0.08)
        default:
            return isSecondary ? .secondary : .primary
        }
    }

    private func cardCellColor(
        for block: NJNoteEditorContainerPersistence.BlockState,
        column: NJCardTableColumn,
        isSecondary: Bool
    ) -> Color {
        switch column {
        case .priority:
            return cardPriorityColor(block.cardPriority, isSecondary: isSecondary)
        case .title:
            return cardPriorityColor(block.cardPriority, isSecondary: isSecondary)
        default:
            return isSecondary ? .secondary : .primary
        }
    }

    func loadCardTablePreferences() {
        let defaults = UserDefaults.standard

        if let raw = defaults.string(forKey: cardColumnOrderKey()), !raw.isEmpty {
            let ordered = raw
                .split(separator: ",")
                .compactMap { NJCardTableColumn(rawValue: String($0)) }
            if !ordered.isEmpty {
                cardColumnOrder = ordered
            }
        }

        if let raw = defaults.string(forKey: cardHiddenColumnsKey()), !raw.isEmpty {
            hiddenCardColumns = Set(
                raw.split(separator: ",")
                    .compactMap { NJCardTableColumn(rawValue: String($0)) }
            )
        }

        if let data = defaults.data(forKey: cardColumnWidthsKey()),
           let decoded = try? JSONDecoder().decode([String: CGFloat].self, from: data) {
            var mapped: [NJCardTableColumn: CGFloat] = [:]
            for (key, value) in decoded {
                if let column = NJCardTableColumn(rawValue: key) {
                    mapped[column] = value
                }
            }
            cardColumnWidths = mapped
        }

        let savedFontScale = defaults.double(forKey: cardTableFontScaleKey())
        if savedFontScale > 0 {
            cardTableFontScale = clampedCardTableFontScale(savedFontScale)
        }
    }

    func persistCardTablePreferences() {
        let defaults = UserDefaults.standard
        defaults.set(cardColumnOrder.map(\.rawValue).joined(separator: ","), forKey: cardColumnOrderKey())
        defaults.set(hiddenCardColumns.map(\.rawValue).sorted().joined(separator: ","), forKey: cardHiddenColumnsKey())
        defaults.set(clampedCardTableFontScale(cardTableFontScale), forKey: cardTableFontScaleKey())

        let widthMap = Dictionary(uniqueKeysWithValues: cardColumnWidths.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(widthMap) {
            defaults.set(data, forKey: cardColumnWidthsKey())
        }
    }

    private func moveCardColumn(_ column: NJCardTableColumn, delta: Int) {
        guard let index = cardColumnOrder.firstIndex(of: column) else { return }
        let target = index + delta
        guard cardColumnOrder.indices.contains(target) else { return }
        var order = cardColumnOrder
        order.remove(at: index)
        order.insert(column, at: target)
        cardColumnOrder = order
        persistCardTablePreferences()
    }

    private func setCardColumnHidden(_ column: NJCardTableColumn, hidden: Bool) {
        if hidden {
            hiddenCardColumns.insert(column)
        } else {
            hiddenCardColumns.remove(column)
        }
        persistCardTablePreferences()
    }

    private func minimumCardWidth(for column: NJCardTableColumn) -> CGFloat {
        32
    }

    private func setCardColumnWidth(_ column: NJCardTableColumn, width: CGFloat) {
        cardColumnWidths[column] = max(minimumCardWidth(for: column), width)
        persistCardTablePreferences()
    }

    func resetCardColumns() {
        cardColumnOrder = NJCardTableColumn.allCases
        hiddenCardColumns = []
        cardColumnWidths = [:]
        cardTableFontScale = 1.0
        persistCardTablePreferences()
    }

    var displayedBlocks: [NJNoteEditorContainerPersistence.BlockState] {
        var blocks = persistence.blocks

        if persistence.noteType == .card {
            if !cardFilterPriority.isEmpty {
                blocks = blocks.filter { $0.cardPriority == cardFilterPriority }
            }
            if !showDoneCardBlocks {
                blocks = blocks.filter { $0.cardStatus.caseInsensitiveCompare("Done") != .orderedSame }
            }
            if !cardFilterStatus.isEmpty {
                blocks = blocks.filter { ($0.cardStatus.isEmpty ? "Pending" : $0.cardStatus) == cardFilterStatus }
            }
            if !cardFilterCategory.isEmpty {
                blocks = blocks.filter { $0.cardCategory == cardFilterCategory }
            }
            if !cardFilterArea.isEmpty {
                blocks = blocks.filter { $0.cardArea == cardFilterArea }
            }
            if !cardFilterContext.isEmpty {
                blocks = blocks.filter { $0.cardContext == cardFilterContext }
            }

            blocks.sort { lhs, rhs in
                let orderedAscending: Bool = {
                    switch cardSortColumn {
                    case .rowID:
                        let left = Int(lhs.cardRowID) ?? Int.max
                        let right = Int(rhs.cardRowID) ?? Int.max
                        if left != right { return left < right }
                        return cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs)) == .orderedAscending
                    case .status:
                        let left = cardStatusRank(lhs.cardStatus)
                        let right = cardStatusRank(rhs.cardStatus)
                        if left != right { return left < right }
                        return cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs)) == .orderedAscending
                    case .priority:
                        let left = cardPriorityRank(lhs.cardPriority)
                        let right = cardPriorityRank(rhs.cardPriority)
                        if left != right { return left < right }
                        return cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs)) == .orderedAscending
                    case .category:
                        let compare = lhs.cardCategory.localizedCaseInsensitiveCompare(rhs.cardCategory)
                        if compare != .orderedSame { return compare == .orderedAscending }
                        return cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs)) == .orderedAscending
                    case .area:
                        let compare = lhs.cardArea.localizedCaseInsensitiveCompare(rhs.cardArea)
                        if compare != .orderedSame { return compare == .orderedAscending }
                        return cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs)) == .orderedAscending
                    case .context:
                        let compare = lhs.cardContext.localizedCaseInsensitiveCompare(rhs.cardContext)
                        if compare != .orderedSame { return compare == .orderedAscending }
                        return cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs)) == .orderedAscending
                    case .title:
                        let compare = cardDisplayTitle(lhs).localizedCaseInsensitiveCompare(cardDisplayTitle(rhs))
                        if compare != .orderedSame { return compare == .orderedAscending }
                        return (Int(lhs.cardRowID) ?? Int.max) < (Int(rhs.cardRowID) ?? Int.max)
                    }
                }()
                return cardSortAscending ? orderedAscending : !orderedAscending
            }

            return blocks
        }

        if !persistence.isChecklist || showFinishedBlocks {
            return blocks
        }
        return blocks.filter { !$0.isChecked }
    }

    @ViewBuilder
    func cardInvestmentTransactionLedgerView() -> some View {
        let executions = cardInvestmentExecutions()
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Investment Transaction Ledger")
                                .font(.headline)
                            Text("One row per broker transaction. This is the permanent source table used by all position, exposure, and trade-performance views.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }

                    cardInvestmentHeader(
                        ["Txn", "Date", "Bank Reference", "Bank", "Symbol", "CCY", "Qty", "Price", "Region", "Trade"],
                        widths: [70, 110, 140, 170, 100, 80, 90, 110, 90, 130]
                    )
                    ForEach(Array(executions.enumerated()), id: \.element.id) { index, execution in
                        cardInvestmentRow(
                            [
                                "\(index + 1)",
                                execution.dateKey,
                                execution.orderRef,
                                execution.institution,
                                execution.symbol,
                                execution.currency,
                                cardInvestmentQuantity(execution.quantity),
                                cardInvestmentMoney(execution.price, currency: execution.currency),
                                execution.region,
                                execution.tradeCode
                            ],
                            widths: [70, 110, 140, 170, 100, 80, 90, 110, 90, 130]
                        )
                    }

                    if executions.isEmpty {
                        ContentUnavailableView("No investment transactions yet", systemImage: "list.bullet.rectangle")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }
                }
                .padding(14)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
        }
    }

    @ViewBuilder
    func cardInvestmentPositionView() -> some View {
        let executions = cardInvestmentExecutions()
        let positions = cardInvestmentPositions(from: executions)
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Transaction-Based Holding / Mark to Market")
                                .font(.headline)
                            Text("The source rows are transactions: institution/account, symbol, side, quantity, price, fees, and order ref. FIFO and P/L are views on top.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await refreshCardInvestmentPrices(for: positions.map(\.symbol)) }
                        } label: {
                            Label("Refresh Price", systemImage: "arrow.clockwise")
                                .font(.caption.weight(.semibold))
                        }
                        .buttonStyle(.bordered)
                    }

                    if positions.isEmpty {
                        ContentUnavailableView("No investment ledger rows for this card", systemImage: "chart.line.uptrend.xyaxis")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            cardInvestmentHeader(["Symbol", "Region", "CCY", "Institution", "Trade", "Qty", "Avg Cost", "Current", "Market Value", "Unrealized", "Unrl %", "Realized"], widths: [90, 90, 80, 150, 130, 80, 110, 110, 130, 130, 90, 120])
                            ForEach(positions) { position in
                                cardInvestmentRow(
                                    [
                                        position.symbol,
                                        position.region,
                                        position.currency,
                                        position.institutions.joined(separator: ", "),
                                        position.tradeCode,
                                        cardInvestmentQuantity(position.quantity),
                                        cardInvestmentMoney(position.averageCost, currency: position.currency),
                                        cardInvestmentOptionalMoney(position.currentPrice, currency: position.currency),
                                        cardInvestmentOptionalMoney(position.marketValue, currency: position.currency),
                                        cardInvestmentOptionalMoney(position.unrealizedPL, currency: position.currency),
                                        cardInvestmentOptionalPct(position.unrealizedPct),
                                        cardInvestmentMoney(position.realizedPL, currency: position.currency)
                                    ],
                                    widths: [90, 90, 80, 150, 130, 80, 110, 110, 130, 130, 90, 120],
                                    negativeColumns: [9, 11]
                                )
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("FIFO Lots")
                                .font(.subheadline.weight(.semibold))
                            cardInvestmentHeader(["Symbol", "Date", "Ref", "Open Qty", "Cost / Share", "Open Cost"], widths: [90, 110, 110, 100, 120, 130])
                            ForEach(positions) { position in
                                ForEach(position.lots) { lot in
                                    cardInvestmentRow(
                                        [
                                            position.symbol,
                                            lot.dateKey,
                                            lot.orderRef,
                                            cardInvestmentQuantity(lot.quantity),
                                            cardInvestmentMoney(lot.costPerShare, currency: position.currency),
                                            cardInvestmentMoney(lot.cost, currency: position.currency)
                                        ],
                                        widths: [90, 110, 110, 100, 120, 130]
                                    )
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ledger Rows")
                                .font(.subheadline.weight(.semibold))
                            cardInvestmentHeader(["Txn", "Date", "Bank Ref", "Bank", "Symbol", "CCY", "Qty", "Price", "Region", "Trade"], widths: [70, 110, 110, 150, 90, 80, 90, 110, 90, 130])
                            ForEach(Array(executions.enumerated()), id: \.element.id) { index, execution in
                                cardInvestmentRow(
                                    [
                                        "\(index + 1)",
                                        execution.dateKey,
                                        execution.orderRef,
                                        execution.institution,
                                        execution.symbol,
                                        execution.currency,
                                        cardInvestmentQuantity(execution.quantity),
                                        cardInvestmentMoney(execution.price, currency: execution.currency),
                                        execution.region,
                                        execution.tradeCode
                                    ],
                                    widths: [70, 110, 110, 150, 90, 80, 90, 110, 90, 130]
                                )
                            }
                        }
                    }
                }
                .padding(14)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .task(id: positions.map(\.symbol).joined(separator: ",")) {
                await refreshCardInvestmentPrices(for: positions.map(\.symbol))
            }
        }
    }

    private func cardInvestmentHeader(_ values: [String], widths: [CGFloat]) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: widths[index], alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.tertiarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardInvestmentRow(_ values: [String], widths: [CGFloat], negativeColumns: [Int] = []) -> some View {
        HStack(spacing: 8) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                Text(value)
                    .font(.caption)
                    .foregroundStyle(negativeColumns.contains(index) && value.contains("-") ? Color.red : Color.primary)
                    .lineLimit(2)
                    .frame(width: widths[index], alignment: .leading)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color(UIColor.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func cardInvestmentExecutions() -> [NJCardInvestmentExecution] {
        let cardFilter = persistence.cardContext.trimmingCharacters(in: .whitespacesAndNewlines)
        return store.notes.listRecentFinanceTransactions(limit: 500)
            .compactMap(cardInvestmentExecution(from:))
            .filter { execution in
                cardFilter.isEmpty ||
                execution.symbol.caseInsensitiveCompare(cardFilter) == .orderedSame ||
                execution.thesis.caseInsensitiveCompare(cardFilter) == .orderedSame
            }
            .sorted {
                if $0.dateKey != $1.dateKey { return $0.dateKey < $1.dateKey }
                return $0.id < $1.id
            }
    }

    private func cardInvestmentExecution(from row: NJFinanceTransaction) -> NJCardInvestmentExecution? {
        guard row.deleted == 0,
              row.analysisNature == "investment_trade",
              let data = row.rawPayloadJSON.data(using: .utf8),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["schema"] as? String == "investment_ledger_execution_v1",
              let symbol = payload["symbol"] as? String,
              let side = payload["side"] as? String,
              let quantity = cardInvestmentPayloadDouble(payload["quantity"]),
              let price = cardInvestmentPayloadDouble(payload["execution_price"])
        else { return nil }

        return NJCardInvestmentExecution(
            id: row.transactionID,
            dateKey: row.dateKey,
            thesis: payload["trade_thesis"] as? String ?? row.tagText,
            tradeCode: payload["trade"] as? String ?? payload["trade_code"] as? String ?? payload["trade_thesis"] as? String ?? row.tagText,
            region: payload["region"] as? String ?? "US",
            orderRef: payload["order_ref"] as? String ?? row.externalRef,
            institution: payload["institution"] as? String ?? row.counterparty,
            accountLabel: payload["account_label"] as? String ?? row.accountLabel,
            symbol: symbol,
            side: side,
            quantity: quantity,
            price: price,
            currency: payload["currency"] as? String ?? row.currencyCode,
            fees: cardInvestmentPayloadDouble(payload["transaction_cost"])
        )
    }

    private func cardInvestmentPositions(from executions: [NJCardInvestmentExecution]) -> [NJCardInvestmentPosition] {
        let grouped = Dictionary(grouping: executions) { "\($0.tradeCode)|\($0.region)|\($0.symbol)|\($0.currency)" }
        return grouped.values.map { rows in
            let orderedRows = rows.sorted {
                if $0.dateKey != $1.dateKey { return $0.dateKey < $1.dateKey }
                return $0.id < $1.id
            }
            var lots: [NJCardInvestmentLot] = []
            var realizedPL = 0.0

            for execution in orderedRows {
                let fees = execution.fees ?? 0
                if execution.side.uppercased() == "SELL" {
                    var remainingSellQuantity = execution.quantity
                    let sellPriceAfterFees = execution.quantity == 0 ? execution.price : execution.price - fees / execution.quantity
                    var updatedLots: [NJCardInvestmentLot] = []

                    for lot in lots {
                        guard remainingSellQuantity > 0 else {
                            updatedLots.append(lot)
                            continue
                        }
                        let consumed = min(lot.quantity, remainingSellQuantity)
                        realizedPL += consumed * (sellPriceAfterFees - lot.costPerShare)
                        remainingSellQuantity -= consumed
                        let remainingLotQuantity = lot.quantity - consumed
                        if remainingLotQuantity > 0.0001 {
                            updatedLots.append(
                                NJCardInvestmentLot(
                                    id: lot.id,
                                    dateKey: lot.dateKey,
                                    orderRef: lot.orderRef,
                                    quantity: remainingLotQuantity,
                                    costPerShare: lot.costPerShare
                                )
                            )
                        }
                    }
                    lots = updatedLots
                } else {
                    let costPerShare = execution.quantity == 0 ? execution.price : execution.price + fees / execution.quantity
                    lots.append(
                        NJCardInvestmentLot(
                            id: execution.id,
                            dateKey: execution.dateKey,
                            orderRef: execution.orderRef,
                            quantity: execution.quantity,
                            costPerShare: costPerShare
                        )
                    )
                }
            }

            let first = orderedRows[0]
            let quantity = lots.reduce(0) { $0 + $1.quantity }
            let openCost = lots.reduce(0) { $0 + $1.cost }
            let averageCost = quantity == 0 ? 0 : openCost / quantity
            return NJCardInvestmentPosition(
                id: "\(first.thesis)|\(first.symbol)|\(first.currency)",
                thesis: first.thesis,
                tradeCode: first.tradeCode,
                region: first.region,
                symbol: first.symbol,
                institutions: Array(Set(orderedRows.map(\.institution))).filter { !$0.isEmpty }.sorted(),
                currency: first.currency,
                quantity: quantity,
                averageCost: averageCost,
                openCost: openCost,
                realizedPL: realizedPL,
                currentPrice: cardInvestmentPrices[first.symbol],
                lots: lots
            )
        }
        .sorted { $0.id < $1.id }
    }

    private func refreshCardInvestmentPrices(for symbols: [String]) async {
        let uniqueSymbols = Array(Set(symbols)).sorted()
        guard !uniqueSymbols.isEmpty else { return }
        for symbol in uniqueSymbols {
            cardInvestmentPriceStatus[symbol] = "Loading"
            if let price = await fetchCardInvestmentPrice(symbol: symbol) {
                cardInvestmentPrices[symbol] = price
                cardInvestmentPriceStatus[symbol] = "Live"
            } else {
                cardInvestmentPriceStatus[symbol] = "Unavailable"
            }
        }
    }

    private func fetchCardInvestmentPrice(symbol: String) async -> Double? {
        let sourceSymbol = cardInvestmentSourceSymbol(for: symbol)
        guard let url = URL(string: "https://stooq.com/q/l/?s=\(sourceSymbol)&f=sd2t2ohlcv&h&e=csv") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            guard let csv = String(data: data, encoding: .utf8) else { return nil }
            let lines = csv.split(whereSeparator: \.isNewline).map(String.init)
            guard lines.count >= 2 else { return nil }
            let values = lines[1].split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard values.count > 6, let close = Double(values[6]), close > 0 else { return nil }
            return close
        } catch {
            return nil
        }
    }

    private func cardInvestmentSourceSymbol(for symbol: String) -> String {
        switch symbol.uppercased() {
        case "SQQQ": return "sqqq.us"
        case "QQQ": return "qqq.us"
        case "SPY": return "spy.us"
        case "AMD": return "amd.us"
        case "NVDA": return "nvda.us"
        default: return "\(symbol.lowercased()).us"
        }
    }

    private func cardInvestmentPayloadDouble(_ value: Any?) -> Double? {
        if let value = value as? Double { return value }
        if let value = value as? Int { return Double(value) }
        if let value = value as? Int64 { return Double(value) }
        if let value = value as? String { return Double(value) }
        return nil
    }

    private func cardInvestmentMoney(_ value: Double, currency: String) -> String {
        "\(currency.uppercased()) \(String(format: "%.2f", value))"
    }

    private func cardInvestmentOptionalMoney(_ value: Double?, currency: String) -> String {
        guard let value else { return "Live pending" }
        return cardInvestmentMoney(value, currency: currency)
    }

    private func cardInvestmentOptionalPct(_ value: Double?) -> String {
        guard let value else { return "Live pending" }
        return String(format: "%+.2f%%", value)
    }

    private func cardInvestmentQuantity(_ value: Double) -> String {
        value.rounded() == value ? String(format: "%.0f", value) : String(format: "%.2f", value)
    }

    @ViewBuilder
    func cardTableView() -> some View {
        GeometryReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Rows")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Toggle("Show Done", isOn: $showDoneCardBlocks)
                            .toggleStyle(.switch)
                            .labelsHidden()
                        Spacer()
                        Menu {
                            ForEach(cardColumnOrder) { column in
                                Section(cardColumnTitle(column)) {
                                    Button("Move Left") {
                                        moveCardColumn(column, delta: -1)
                                    }
                                    .disabled(cardColumnOrder.firstIndex(of: column) == 0)

                                    Button("Move Right") {
                                        moveCardColumn(column, delta: 1)
                                    }
                                    .disabled(cardColumnOrder.firstIndex(of: column) == cardColumnOrder.count - 1)

                                    Button(hiddenCardColumns.contains(column) ? "Show Column" : "Hide Column") {
                                        setCardColumnHidden(column, hidden: !hiddenCardColumns.contains(column))
                                    }

                                    Menu("Width") {
                                        Button("Narrow") { setCardColumnWidth(column, width: max(minimumCardWidth(for: column), cardColumnWidth(column) - 40)) }
                                        Button("Default") { setCardColumnWidth(column, width: defaultCardWidth(for: column)) }
                                        Button("Wide") { setCardColumnWidth(column, width: defaultCardWidth(for: column) + 80) }
                                    }
                                }
                            }

                            Divider()

                            Section("Text Size") {
                                Button("Smaller Text") {
                                    adjustCardTableFontScale(delta: -0.1)
                                }

                                Button("Larger Text") {
                                    adjustCardTableFontScale(delta: 0.1)
                                }

                                Button("Default Text") {
                                    resetCardTableFontScale()
                                }
                            }

                            Divider()

                            Button("Reset Columns") {
                                resetCardColumns()
                            }
                        } label: {
                            Label("Columns", systemImage: "slider.horizontal.3")
                                .font(.caption)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)

                    HStack(spacing: 12) {
                        ForEach(visibleCardColumns) { column in
                            cardHeaderCell(
                                column,
                                width: cardColumnWidth(column),
                                filterValues: cardFilterValues(for: column),
                                activeFilter: cardFilterBinding(for: column)
                            )
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.tertiarySystemBackground))
                    )

                    ForEach(displayedBlocks, id: \.id) { b in
                        cardBlockPreviewRow(b)
                    }

                    if displayedBlocks.isEmpty {
                        ContentUnavailableView("No blocks match the current filters", systemImage: "line.3.horizontal.decrease.circle")
                            .frame(maxWidth: .infinity)
                            .padding(.top, 32)
                    }
                }
                .padding(12)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .topLeading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func defaultCardWidth(for column: NJCardTableColumn) -> CGFloat {
        switch column {
        case .rowID: return 130
        case .status: return 110
        case .priority: return 110
        case .category: return 150
        case .area: return 150
        case .context: return 220
        case .title: return 280
        }
    }

    @ViewBuilder
    private func cardHeaderCell(
        _ column: NJCardTableColumn,
        width: CGFloat,
        filterValues: [String] = [],
        activeFilter: Binding<String>? = nil
    ) -> some View {
        ZStack(alignment: .trailing) {
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    Text(cardColumnTitle(column))
                        .font(cardTableScaledFont(12, weight: .semibold))
                    if cardSortColumn == column {
                        Image(systemName: cardSortAscending ? "arrow.up" : "arrow.down")
                            .font(cardTableScaledFont(11, weight: .bold))
                    }
                }
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture {
                    if cardSortColumn == column {
                        cardSortAscending.toggle()
                    } else {
                        cardSortColumn = column
                        cardSortAscending = true
                    }
                }
                .onTapGesture(count: 2) {
                    guard activeFilter != nil else { return }
                    presentedCardFilterColumn = column
                }

                if let activeFilter {
                    Button {
                        presentedCardFilterColumn = column
                    } label: {
                        Image(systemName: activeFilter.wrappedValue.isEmpty ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                            .font(.caption)
                            .foregroundStyle(activeFilter.wrappedValue.isEmpty ? AnyShapeStyle(.secondary) : AnyShapeStyle(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .popover(
                        isPresented: Binding(
                            get: { presentedCardFilterColumn == column },
                            set: { isPresented in
                                if isPresented {
                                    presentedCardFilterColumn = column
                                } else if presentedCardFilterColumn == column {
                                    presentedCardFilterColumn = nil
                                }
                            }
                        ),
                        arrowEdge: .bottom
                    ) {
                        cardFilterPopover(column: column, filterValues: filterValues, activeFilter: activeFilter)
                    }
                }
            }
            .padding(.trailing, 22)
            .frame(maxHeight: .infinity, alignment: .center)

            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 18, height: 36)
                    .contentShape(Rectangle())

                Rectangle()
                    .fill(Color.secondary.opacity(0.25))
                    .frame(width: 3, height: 28)
            }
            .highPriorityGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let base = cardResizeStartWidths[column] ?? cardColumnWidth(column)
                        if cardResizeStartWidths[column] == nil {
                            cardResizeStartWidths[column] = base
                        }
                        cardColumnWidths[column] = max(minimumCardWidth(for: column), base + value.translation.width)
                    }
                    .onEnded { value in
                        let base = cardResizeStartWidths[column] ?? cardColumnWidth(column)
                        setCardColumnWidth(column, width: max(minimumCardWidth(for: column), base + value.translation.width))
                        cardResizeStartWidths[column] = nil
                    }
            )
        }
        .frame(width: width, alignment: .leading)
        .frame(height: 40)
    }

    @ViewBuilder
    private func cardFilterPopover(
        column: NJCardTableColumn,
        filterValues: [String],
        activeFilter: Binding<String>
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(cardColumnTitle(column)) Filter")
                .font(.headline)

            Button("All") {
                activeFilter.wrappedValue = ""
                presentedCardFilterColumn = nil
            }

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(filterValues, id: \.self) { value in
                        Button {
                            activeFilter.wrappedValue = value
                            presentedCardFilterColumn = nil
                        } label: {
                            HStack {
                                Text(value)
                                    .lineLimit(1)
                                Spacer(minLength: 8)
                                if activeFilter.wrappedValue == value {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .frame(maxHeight: 220)
        }
        .frame(width: 220, alignment: .leading)
        .padding(12)
    }

    @ViewBuilder
    func cardRowCell(
        _ text: String,
        width: CGFloat,
        alignment: Alignment = .leading,
        isSecondary: Bool = false,
        foregroundColor: Color? = nil
    ) -> some View {
        Text(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "-" : text)
            .font(cardTableScaledFont(15))
            .foregroundStyle(foregroundColor ?? (isSecondary ? .secondary : .primary))
            .lineLimit(1)
            .frame(width: width, alignment: alignment)
    }

    @ViewBuilder
    func cardBlockMetadataEditor(_ block: NJNoteEditorContainerPersistence.BlockState) -> some View {
        if isPersonalIdentificationCard {
            personalIdentificationMetadataEditor(block)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    TextField(
                        "Row ID",
                        text: .constant(persistence.blocks.first(where: { $0.id == block.id })?.cardRowID ?? block.cardRowID)
                    )
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 160)
                    .disabled(true)

                    Picker("Priority", selection: Binding(
                        get: { persistence.blocks.first(where: { $0.id == block.id })?.cardPriority.isEmpty == false ? (persistence.blocks.first(where: { $0.id == block.id })?.cardPriority ?? "Medium") : "Medium" },
                        set: { persistence.updateCardRowFields(block.id, priority: $0) }
                    )) {
                        ForEach(cardPriorityOptions, id: \.self) { priority in
                            Text(priority).tag(priority)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)

                    Picker("Status", selection: Binding(
                        get: { persistence.blocks.first(where: { $0.id == block.id })?.cardStatus.isEmpty == false ? (persistence.blocks.first(where: { $0.id == block.id })?.cardStatus ?? "Pending") : "Pending" },
                        set: { persistence.updateCardRowFields(block.id, status: $0) }
                    )) {
                        ForEach(cardStatusOptions, id: \.self) { status in
                            Text(status).tag(status)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                }

                TextField("Category", text: Binding(
                    get: { persistence.blocks.first(where: { $0.id == block.id })?.cardCategory ?? block.cardCategory },
                    set: { persistence.updateCardRowFields(block.id, category: $0) }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Area", text: Binding(
                    get: { persistence.blocks.first(where: { $0.id == block.id })?.cardArea ?? block.cardArea },
                    set: { persistence.updateCardRowFields(block.id, area: $0) }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Context", text: Binding(
                    get: { persistence.blocks.first(where: { $0.id == block.id })?.cardContext ?? block.cardContext },
                    set: { persistence.updateCardRowFields(block.id, context: $0) }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Title", text: Binding(
                    get: { persistence.blocks.first(where: { $0.id == block.id })?.cardTitle ?? block.cardTitle },
                    set: { persistence.updateCardRowFields(block.id, title: $0) }
                ))
                .textFieldStyle(.roundedBorder)
            }
        }
    }

    @ViewBuilder
    func personalIdentificationMetadataEditor(_ block: NJNoteEditorContainerPersistence.BlockState) -> some View {
        let current = persistence.blocks.first(where: { $0.id == block.id }) ?? block
        let fields = personalIdentificationFields(from: current)
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                TextField(
                    "Row ID",
                    text: .constant(persistence.blocks.first(where: { $0.id == block.id })?.cardRowID ?? block.cardRowID)
                )
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)
                .disabled(true)

                Picker("Urgency", selection: Binding(
                    get: { current.cardPriority.isEmpty ? "Low" : current.cardPriority },
                    set: { persistence.updateCardRowFields(block.id, priority: $0) }
                )) {
                    ForEach(cardPriorityOptions, id: \.self) { priority in
                        Text(priority).tag(priority)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)

                Picker("Status", selection: Binding(
                    get: { current.cardStatus.isEmpty ? "Active" : current.cardStatus },
                    set: { persistence.updateCardRowFields(block.id, status: $0) }
                )) {
                    ForEach(cardStatusOptions, id: \.self) { status in
                        Text(status).tag(status)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
            }

            TextField("Person", text: Binding(
                get: { fields.person },
                set: { persistence.updateCardRowFields(block.id, area: $0, title: personalIdentificationTitle(person: $0, document: fields.document)) }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Document", text: Binding(
                get: { fields.document },
                set: { persistence.updateCardRowFields(block.id, title: personalIdentificationTitle(person: fields.person, document: $0)) }
            ))
            .textFieldStyle(.roundedBorder)

            TextField("Type", text: Binding(
                get: { fields.documentType },
                set: { persistence.updateCardRowFields(block.id, category: $0) }
            ))
            .textFieldStyle(.roundedBorder)

            HStack(spacing: 12) {
                TextField("Country / Jurisdiction", text: Binding(
                    get: { fields.jurisdiction },
                    set: { persistence.updateCardRowFields(block.id, context: personalIdentificationContext(jurisdiction: $0, expiryDate: fields.expiryDate, documentNumber: fields.documentNumber)) }
                ))
                .textFieldStyle(.roundedBorder)

                TextField("Expiry Date", text: Binding(
                    get: { fields.expiryDate },
                    set: { persistence.updateCardRowFields(block.id, context: personalIdentificationContext(jurisdiction: fields.jurisdiction, expiryDate: $0, documentNumber: fields.documentNumber)) }
                ))
                .textFieldStyle(.roundedBorder)
            }

            TextField("Document Number", text: Binding(
                get: { fields.documentNumber },
                set: { persistence.updateCardRowFields(block.id, context: personalIdentificationContext(jurisdiction: fields.jurisdiction, expiryDate: fields.expiryDate, documentNumber: $0)) }
            ))
            .textFieldStyle(.roundedBorder)
        }
    }

    @ViewBuilder
    func cardBlockPreviewRow(_ b: NJNoteEditorContainerPersistence.BlockState) -> some View {
        HStack(spacing: 12) {
            ForEach(visibleCardColumns) { column in
                cardRowCell(
                    cardColumnValue(column, for: b),
                    width: cardColumnWidth(column),
                    alignment: .leading,
                    isSecondary: column == .rowID,
                    foregroundColor: cardCellColor(for: b, column: column, isSecondary: column == .rowID)
                )
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            selectedCardBlockItem = NJCardBlockSheetItem(id: b.id)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(UIColor.secondarySystemBackground).opacity(0.6))
        )
    }

    @ViewBuilder
    func cardBlockDetailSheet(_ id: UUID) -> some View {
        if let block = persistence.blocks.first(where: { $0.id == id }) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    cardBlockMetadataEditor(block)
                    standardBlockRow(block, showOnAppearFocus: false, displayIndexOverride: 1)
                }
                .padding(12)
            }
        } else {
            ContentUnavailableView("Block not found", systemImage: "exclamationmark.triangle")
        }
    }

    func saveCardBlockSheet(_ id: UUID) {
        persistence.forceEndEditingAndCommitNow(id)
        selectedCardBlockItem = nil
    }

    @ViewBuilder
    func standardBlockRow(
        _ b: NJNoteEditorContainerPersistence.BlockState,
        showOnAppearFocus: Bool = true,
        displayIndexOverride: Int? = nil
    ) -> some View {
        let id = b.id
        let h = b.protonHandle

        let collapsedBinding = Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isCollapsed ?? false },
            set: { v in
                if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    persistence.blocks[i].isCollapsed = v
                    persistence.saveCollapsed(blockID: persistence.blocks[i].blockID, collapsed: v)
                }
            }
        )

        let rowIndex = displayIndexOverride ?? ((persistence.blocks.firstIndex(where: { $0.id == id }) ?? 0) + 1)

        let isFocusedNow = (id == persistence.focusedBlockID)
        let attrB = bindingAttr(id)
        let selB = bindingSel(id)
        let checkedBinding = Binding(
            get: { persistence.blocks.first(where: { $0.id == id })?.isChecked ?? false },
            set: { v in
                persistence.setBlockChecked(id, isChecked: v)
            }
        )

        let onFocusBlock: () -> Void = {
            let prev = persistence.focusedBlockID
            if let prev, prev != id {
                persistence.forceEndEditingAndCommitNow(prev)
            }
            persistence.focusedBlockID = id
            h.focus()
            blockBus.focus(id)
        }

        let onCommitBlock: () -> Void = {
            if persistence.blocks.first(where: { $0.id == id })?.isDirty == true {
                persistence.scheduleCommit(id, source: "container.onCommitProton.alreadyDirty")
            }
        }

        let onCtrlReturnBlock: () -> Void = { blockBus.ctrlReturn(id) }
        let onDeleteBlock: () -> Void = { blockBus.delete(id) }
        let onHydrateBlock: () -> Void = { persistence.hydrateProton(id) }

        let inherited: [String] = {
            let t = persistence.tab.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? [] : [t]
        }()
        let editable: [String] = []

        let liveTagJSON: String? = persistence.blocks.first(where: { $0.id == id })?.tagJSON

        let onSaveTags: (String) -> Void = { newJSON in
            let merged = mergeTagJSONWithInherited(json: newJSON, inheritedTags: inherited)
            if let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                persistence.blocks[i].tagJSON = merged
                persistence.blocks = Array(persistence.blocks)
            }
            persistence.markDirty(id, source: "container.saveTags")
            persistence.scheduleCommit(id, source: "container.saveTags")
        }

        let onMoveToClipboard: () -> Void = {
            persistence.forceEndEditingAndCommitNow(id)
            guard let i = persistence.blocks.firstIndex(where: { $0.id == id }) else { return }
            let b = persistence.blocks[i]
            guard !b.instanceID.isEmpty else { return }
            let preview = firstLinePreview(b.attr)
            let fromDomain = persistence.tab.trimmingCharacters(in: .whitespacesAndNewlines)
            store.pendingMoveBlock = NJPendingMoveBlock(
                blockID: b.blockID,
                instanceID: b.instanceID,
                fromNoteID: noteID.raw,
                fromNoteDomain: fromDomain,
                preview: preview
            )
        }

        let onSaveCreatedAtMs: (Int64) -> Void = { newMs in
            persistence.forceEndEditingAndCommitNow(id)
            persistence.updateBlockCreatedAt(id, createdAtMs: newMs)
        }

        let rel = b.clipPDFRel.trimmingCharacters(in: .whitespacesAndNewlines)

        NJBlockHostView(
            index: rowIndex,
            blockID: b.blockID,
            createdAtMs: b.createdAtMs,
            domainPreview: b.domainPreview,
            onEditTags: nil,
            onSaveCreatedAtMs: onSaveCreatedAtMs,
            goalPreview: b.goalPreview,
            onAddGoal: {
                lastGoalBlockID = b.blockID
                goalSheetItem = NJGoalSheetItem(blockID: b.blockID)
            },
            hasClipPDF: !rel.isEmpty,
            onOpenClipPDF: rel.isEmpty ? nil : { openClipPDFRel(rel) },
            protonHandle: h,
            isCollapsed: collapsedBinding,
            isFocused: isFocusedNow,
            attr: attrB,
            sel: selB,
            onFocus: onFocusBlock,
            onCtrlReturn: onCtrlReturnBlock,
            onDelete: onDeleteBlock,
            onHydrateProton: onHydrateBlock,
            onCommitProton: onCommitBlock,
            onMoveToClipboard: onMoveToClipboard,
            checklistChecked: persistence.isChecklist ? checkedBinding : nil,
            onToggleChecklistChecked: persistence.isChecklist ? {
                checkedBinding.wrappedValue.toggle()
            } : nil,
            inheritedTags: inherited,
            editableTags: editable,
            tagJSON: liveTagJSON,
            onSaveTagJSON: onSaveTags,
            tagSuggestionsProvider: { prefix, limit in
                store.notes.listTagSuggestions(prefix: prefix, limit: limit)
            }
        )
        .fixedSize(horizontal: false, vertical: true)
        .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
        .listRowSeparator(.hidden)
        .onAppear {
            guard showOnAppearFocus else { return }
            if pendingFocusID == id {
                if pendingFocusToStart, let i = persistence.blocks.firstIndex(where: { $0.id == id }) {
                    persistence.blocks[i].sel = NSRange(location: 0, length: 0)
                }
                persistence.focusedBlockID = id
                pendingFocusID = nil
                pendingFocusToStart = false
                h.focus()
            }
        }
    }

    func blockDateLabel(_ ms: Int64) -> String {
        guard ms > 0 else { return "" }
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    @ViewBuilder
    func noteConfigurator() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showNoteConfigurator.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showNoteConfigurator ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 14)
                    Text("Note settings")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(configuratorSummary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            if showNoteConfigurator {
                Picker("Dominance", selection: $persistence.dominanceMode) {
                    ForEach(NJNoteDominanceMode.allCases, id: \.self) { mode in
                        Text(mode.title).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: persistence.dominanceMode) { _, _ in
                    persistence.scheduleNoteMetaCommit()
                }

                HStack(spacing: 16) {
                    Toggle("Checklist", isOn: $persistence.isChecklist)
                        .toggleStyle(.switch)
                        .onChange(of: persistence.isChecklist) { _, enabled in
                            if !enabled {
                                showFinishedBlocks = false
                            }
                            persistence.scheduleNoteMetaCommit()
                        }

                    if persistence.isChecklist {
                        Toggle("Show finished", isOn: $showFinishedBlocks)
                            .toggleStyle(.switch)
                    }
                }
                .font(.subheadline)
            }
        }
    }

    @ViewBuilder
    func cardViewChooser() -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Picker("Card View", selection: $selectedCardEmbeddedView) {
                    if isInvestmentLedgerCard {
                        Text("Ledger").tag(NJCardEmbeddedViewKind.transactionLedger)
                        Text("Position / P&L").tag(NJCardEmbeddedViewKind.investmentPosition)
                    } else {
                        Text("Rows").tag(NJCardEmbeddedViewKind.rows)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: isInvestmentLedgerCard ? 420 : 180)
                .onChange(of: selectedCardEmbeddedView) { _, _ in
                    persistCardEmbeddedViewPreference()
                }

                if isInvestmentLedgerCard {
                    Text("Permanent transaction ledger. Views can filter by trade, region, currency, symbol, and institution.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
        }
    }

    var configuratorSummary: String {
        var parts = [persistence.dominanceMode.title]
        parts.append(persistence.isChecklist ? "Checklist on" : "Checklist off")
        if persistence.isChecklist && showFinishedBlocks {
            parts.append("showing finished")
        }
        return parts.joined(separator: "  •  ")
    }

    var shouldUseWindowForPDF: Bool {
        #if os(iOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        return idiom == .pad || idiom == .mac
        #else
        return true
        #endif
    }
}
private struct NJContainerKeyCommands: UIViewControllerRepresentable {
    let getHandle: () -> NJProtonEditorHandle?

    func makeUIViewController(context: Context) -> VC {
        let vc = VC()
        vc.getHandle = getHandle
        return vc
    }

    func updateUIViewController(_ uiViewController: VC, context: Context) {
        uiViewController.getHandle = getHandle
        uiViewController.becomeFirstResponder()
    }

    final class VC: UIViewController {
        var getHandle: (() -> NJProtonEditorHandle?)? = nil

        override var canBecomeFirstResponder: Bool { true }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            becomeFirstResponder()
        }

        override var keyCommands: [UIKeyCommand]? {
            let mk: (String, UIKeyModifierFlags, Selector) -> UIKeyCommand = { input, flags, sel in
                let c = UIKeyCommand(input: input, modifierFlags: flags, action: sel)
                c.wantsPriorityOverSystemBehavior = true
                return c
            }

            return [
                mk("b", .command, #selector(cmdBold)),
                mk("i", .command, #selector(cmdItalic)),
                mk("u", .command, #selector(cmdUnderline)),
                mk("x", [.command, .shift], #selector(cmdStrike)),
                mk("\t", [], #selector(cmdTab)),
                mk("\t", [.shift], #selector(cmdShiftTab)),
                mk("]", .command, #selector(cmdIndent)),
                mk("[", .command, #selector(cmdOutdent))
            ]

        }

        @objc func cmdBold() { withHandle { $0.toggleBold() } }
        @objc func cmdItalic() { withHandle { $0.toggleItalic() } }
        @objc func cmdUnderline() { withHandle { $0.toggleUnderline() } }
        @objc func cmdStrike() { withHandle { $0.toggleStrike() } }
        @objc func cmdIndent() { withHandle { $0.indent() } }
        @objc func cmdOutdent() { withHandle { $0.outdent() } }
        @objc func cmdTab() { withHandle { $0.indent() } }
        @objc func cmdShiftTab() { withHandle { $0.outdent() } }


        private func withHandle(_ f: (NJProtonEditorHandle) -> Void) {
            guard let h = getHandle?() else { return }
            h.isEditing = true
            f(h)
            h.snapshot(markUserEdit: true)
        }
    }
}

private func materializeToTemp(_ src: URL) async -> URL? {
    let fm = FileManager.default
    let tmp = fm.temporaryDirectory
        .appendingPathComponent("nj_clip_pdf", isDirectory: true)

    try? fm.createDirectory(at: tmp, withIntermediateDirectories: true)

    let dst = tmp.appendingPathComponent(UUID().uuidString + ".pdf", isDirectory: false)

    return await withCheckedContinuation { cont in
        let coord = NSFileCoordinator()
        var err: NSError?
        coord.coordinate(readingItemAt: src, options: [], error: &err) { readURL in
            do {
                if fm.fileExists(atPath: dst.path) { try fm.removeItem(at: dst) }
                try fm.copyItem(at: readURL, to: dst)
                cont.resume(returning: dst)
            } catch {
                cont.resume(returning: nil)
            }
        }
        if err != nil {
            cont.resume(returning: nil)
        }
    }
}


private func extractProtonJSON(_ payload: String) -> String? {
    guard
        let data = payload.data(using: .utf8),
        let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let sections = root["sections"] as? [String: Any],
        let proton1 = sections["proton1"] as? [String: Any],
        let dataNode = proton1["data"] as? [String: Any],
        let pj = dataNode["proton_json"] as? String
    else { return nil }

    return pj
}


private struct NJHiddenShortcuts: View {
    let getHandle: () -> NJProtonEditorHandle?

    var body: some View {
        Group {
            Button("") { fire { $0.toggleBold() } }
                .keyboardShortcut("b", modifiers: .command)

            Button("") { fire { $0.toggleItalic() } }
                .keyboardShortcut("i", modifiers: .command)

            Button("") { fire { $0.toggleUnderline() } }
                .keyboardShortcut("u", modifiers: .command)

            Button("") { fire { $0.toggleStrike() } }
                .keyboardShortcut("x", modifiers: [.command, .shift])

            Button("") { fire { $0.indent() } }
                .keyboardShortcut("]", modifiers: .command)

            Button("") { fire { $0.outdent() } }
                .keyboardShortcut("[", modifiers: .command)
            Button("") {
                NJShortcutLog.info("SHORTCUT TEST CMD+K HIT")
            }
            .keyboardShortcut("k", modifiers: .command)

        }
        .opacity(0.001)
        .frame(width: 1, height: 1)
        .allowsHitTesting(false)
    }

    private func fire(_ f: (NJProtonEditorHandle) -> Void) {
        NJShortcutLog.info("SHORTCUT HIT (SwiftUI layer)")

        guard let h = getHandle() else {
            NJShortcutLog.error("SHORTCUT: getHandle() returned nil")
            return
        }

        NJShortcutLog.info("SHORTCUT: has handle owner=\(String(describing: h.ownerBlockUUID)) editor_nil=\(h.editor == nil) tv_nil=\(h.textView == nil)")
        h.isEditing = true
        f(h)
        h.snapshot(markUserEdit: true)
    }

}

private struct NJPDFQuickView: View {
    let url: URL
    @Environment(\.dismiss) var dismiss

    @State private var doc: PDFDocument? = nil
    @State private var err: String = ""
    @State private var loading: Bool = true

    var body: some View {
        VStack(spacing: 0) {

            // ✅ SHEET DRAG ZONE (MUST BE OUTSIDE NavigationStack)
            Rectangle()
                .fill(.clear)
                .frame(height: 28)
                .contentShape(Rectangle())

            NavigationStack {
                Group {
                    if loading {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading PDF…")
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if let doc {
                        PDFKitDocumentView(doc: doc)
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Failed to open PDF")
                                .font(.headline)
                            if !err.isEmpty {
                                Text(err)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(16)
                    }
                }
                .navigationTitle(url.lastPathComponent)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackgroundInteraction(.enabled)
        .presentationContentInteraction(.resizes)
        .task {
            loading = true
            err = ""
            doc = PDFDocument(url: url)
            loading = false
        }
    }

}

private struct PDFKitDocumentView: UIViewRepresentable {
    let doc: PDFDocument

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = false
        v.backgroundColor = .clear
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document !== doc {
            v.document = doc

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                v.minScaleFactor = v.scaleFactorForSizeToFit
                v.maxScaleFactor = 4.0
                v.scaleFactor = v.scaleFactorForSizeToFit
            }
        }
    }
}

private struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.autoScales = false
        v.minScaleFactor = v.scaleFactorForSizeToFit
        v.maxScaleFactor = 4.0
        v.scaleFactor = v.scaleFactorForSizeToFit
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document == nil {
            uiView.document = PDFDocument(url: url)
            uiView.scaleFactor = uiView.scaleFactorForSizeToFit
        }
    }
}


private func loadPDFDocument(url: URL) async throws -> PDFDocument {
    let fm = FileManager.default
    let rv = try? url.resourceValues(forKeys: [.isUbiquitousItemKey])
    if rv?.isUbiquitousItem == true {
        try? fm.startDownloadingUbiquitousItem(at: url)

        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            let v = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
            if let s = v?.ubiquitousItemDownloadingStatus, s == .current { break }
            try await Task.sleep(nanoseconds: 200_000_000)
        }
    }

    let coord = NSFileCoordinator()
    var readErr: NSError?
    var data: Data? = nil

    coord.coordinate(readingItemAt: url, options: [], error: &readErr) { u in
        data = try? Data(contentsOf: u)
    }

    if let readErr { throw readErr }
    guard let data, let d = PDFDocument(data: data) else {
        throw NSError(domain: "NJPDF", code: -1, userInfo: [NSLocalizedDescriptionKey: "PDFDocument init failed"])
    }
    return d
}
