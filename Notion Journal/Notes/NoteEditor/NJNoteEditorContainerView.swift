import SwiftUI
import Combine
import UIKit
import SQLite3
import PDFKit
import PhotosUI

import os

private let NJShortcutLog = Logger(subsystem: "NotionJournal", category: "Shortcuts")


private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct NJNoteEditorContainerView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow
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

    private struct NJGoalSheetItem: Identifiable {
        let id = UUID()
        let blockID: String
    }

    @State private var goalSheetItem: NJGoalSheetItem? = nil
    @State private var lastGoalBlockID: String? = nil



    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text(persistence.tab.isEmpty ? "" : persistence.tab)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 10)

                TextField("Title", text: $persistence.title)
                    .font(.title2)
                    .textFieldStyle(.roundedBorder)
            }
            
            .padding(.horizontal, 12)
            .padding(.bottom, 10)

            Divider()

            List {
                ForEach(persistence.blocks, id: \.id) { b in
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

                    let rowIndex = (persistence.blocks.firstIndex(where: { $0.id == id }) ?? 0) + 1

                    let isFocusedNow = (id == persistence.focusedBlockID)
                    let attrB = bindingAttr(id)
                    let selB = bindingSel(id)

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
                        persistence.markDirty(id)
                        persistence.scheduleCommit(id)
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
                        persistence.markDirty(id)
                        persistence.scheduleCommit(id)
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

                    let rel = b.clipPDFRel.trimmingCharacters(in: .whitespacesAndNewlines)

                    NJBlockHostView(
                        index: rowIndex,
                        createdAtMs: b.createdAtMs,
                        domainPreview: b.domainPreview,
                        onEditTags: nil,
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
                        inheritedTags: inherited,
                        editableTags: editable,
                        tagJSON: liveTagJSON,
                        onSaveTagJSON: onSaveTags
                    )

                    .id("\(id.uuidString)-\(collapsedBinding.wrappedValue ? "c" : "e")")
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowInsets(EdgeInsets(top: 2, leading: 12, bottom: 2, trailing: 12))
                    .listRowSeparator(.hidden)
                    .onAppear {
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
                .onMove(perform: moveBlocks)
            }
            .listStyle(.plain)
            .environment(\.editMode, $editMode)
        }
        .overlay(NJHiddenShortcuts(getHandle: { focusedHandle() }))
//        .overlay(NJContainerKeyCommands(getHandle: { focusedHandle() })
//            .frame(width: 0, height: 0)
//            .allowsHitTesting(false)
//        )
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let h = focusedHandle() {
                NJProtonFloatingFormatBar(handle: h, pickedPhotoItem: $pickedPhotoItem)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 6)
                    .background(.ultraThinMaterial)
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

        .task {
            if loaded { return }
            loaded = true
            persistence.configure(store: store, noteID: noteID)
            blockBus.setHandler { e in handleBlockEvent(e) }
            persistence.reload(makeHandle: makeWiredHandle)
        }
        .onReceive(NotificationCenter.default.publisher(for: .njForceReloadNote)) { _ in
            persistence.reload(makeHandle: makeWiredHandle)
        }
        .onDisappear {
            if let id = persistence.focusedBlockID {
                persistence.forceEndEditingAndCommitNow(id)
            }
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
                    persistence.blocks[i].sel = v
                }
            }
        )
    }

}

private extension NJNoteEditorContainerView {
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
                mk("[", .command, #selector(cmdOutdent)),
                mk("7", .command, #selector(cmdBullet)),
                mk("8", .command, #selector(cmdNumber))
            ]

        }

        @objc func cmdBold() { withHandle { $0.toggleBold() } }
        @objc func cmdItalic() { withHandle { $0.toggleItalic() } }
        @objc func cmdUnderline() { withHandle { $0.toggleUnderline() } }
        @objc func cmdStrike() { withHandle { $0.toggleStrike() } }
        @objc func cmdIndent() { withHandle { $0.indent() } }
        @objc func cmdOutdent() { withHandle { $0.outdent() } }
        @objc func cmdBullet() { withHandle { $0.toggleBullet() } }
        @objc func cmdNumber() { withHandle { $0.toggleNumber() } }
        @objc func cmdTab() { withHandle { $0.indent() } }
        @objc func cmdShiftTab() { withHandle { $0.outdent() } }


        private func withHandle(_ f: (NJProtonEditorHandle) -> Void) {
            guard let h = getHandle?() else { return }
            f(h)
            h.snapshot()
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

            Button("") { fire { $0.toggleBullet() } }
                .keyboardShortcut("7", modifiers: .command)

            Button("") { fire { $0.toggleNumber() } }
                .keyboardShortcut("8", modifiers: .command)

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
        f(h)
        h.snapshot()
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
