import SwiftUI
import PDFKit

struct NJClipboardInboxView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow

    let noteID: String
    let onImported: () -> Void

    @State private var rows: [Row] = []
    @State private var selectedBlockID: String? = nil

    @State private var showPDF = false
    @State private var pdfURL: URL? = nil

    @State private var diagText: String = ""

    struct Row: Identifiable, Equatable {
        let id: String
        let createdAtMs: Int64
        let website: String
        let title: String
        let pdfPath: String
        let jsonPath: String
        let audioPath: String
        let kind: Kind
    }

    enum Kind: String, Equatable {
        case clip
        case audio
    }

    var selectedRow: Row? {
        guard let bid = selectedBlockID else { return nil }
        return rows.first(where: { $0.id == bid })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !diagText.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(diagText)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .padding(.horizontal, 12)
                            .padding(.top, 10)
                        Divider()
                    }
                }

                List {
                    ForEach(rows) { r in
                        Button {
                            selectedBlockID = r.id
                            refreshICloudDiagForSelected()
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(njDate(r.createdAtMs))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Text(r.website)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Text(r.title.isEmpty ? "(untitled)" : r.title)
                                    .font(.body)
                                    .lineLimit(2)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .listRowBackground(
                            (selectedBlockID == r.id) ? Color.primary.opacity(0.10) : Color.clear
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                deleteRow(r)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selectedBlockID = r.id
                                refreshICloudDiagForSelected()
                                openPDF(for: r)
                            }
                        )
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button("Diag iCloud") {
                        refreshICloudDiagForSelected()
                    }

                    Button("Open PDF") {
                        guard let r = selectedRow, !r.pdfPath.isEmpty else { return }
                        refreshICloudDiagForSelected()
                        openPDF(for: r)
                    }
                    .disabled(selectedBlockID == nil || (selectedRow?.pdfPath.isEmpty ?? true))

                    Spacer()

                    Button("Import") {
                        importSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBlockID == nil)
                }
                .padding(12)
            }
            .navigationTitle("Clipboard Inbox")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") {
                        reload()
                        refreshICloudDiagForSelected()
                    }
                }
            }
            
            .onChange(of: selectedBlockID) { _ in
                refreshICloudDiagForSelected()
            }

            .onAppear {
                reload()
                refreshICloudDiagForSelected()
            }
            .sheet(isPresented: $showPDF) {
                NavigationStack {
                    VStack(spacing: 0) {
                        if let u = pdfURL {
                            PDFKitContainer(url: u)
                        } else {
                            Text("PDF not found")
                                .foregroundStyle(.secondary)
                                .padding(20)
                        }
                    }
                    .navigationTitle("PDF")
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Close") { showPDF = false }
                        }
                    }
                }
            }
        }
    }

    func reload() {
        let raw = store.notes.listOrphanClipBlocks(limit: 500)
        let rawAudio = store.notes.listOrphanAudioBlocks(limit: 500)

        var out: [Row] = []
        out.reserveCapacity(raw.count + rawAudio.count)

        for r in raw {
            let meta = parseClipPayload(r.payloadJSON)
            out.append(
                Row(
                    id: r.id,
                    createdAtMs: r.createdAtMs,
                    website: meta.website,
                    title: meta.title,
                    pdfPath: meta.pdfPath,
                    jsonPath: meta.jsonPath,
                    audioPath: "",
                    kind: .clip
                )
            )
        }

        for r in rawAudio {
            let meta = parseAudioPayload(r.payloadJSON)
            if meta.transcript.isEmpty { continue }
            out.append(
                Row(
                    id: r.id,
                    createdAtMs: r.createdAtMs,
                    website: "Audio",
                    title: meta.title,
                    pdfPath: meta.pdfPath,
                    jsonPath: meta.jsonPath,
                    audioPath: meta.audioPath,
                    kind: .audio
                )
            )
        }

        out.sort { $0.createdAtMs > $1.createdAtMs }

        rows = out
        if let sel = selectedBlockID, !rows.contains(where: { $0.id == sel }) {
            selectedBlockID = nil
        }
    }

    func importSelected() {
        guard let bid = selectedBlockID else { return }

        let ok = store.notes.nextAppendOrderKey(noteID: noteID)
        _ = store.notes.attachExistingBlockToNote(noteID: noteID, blockID: bid, orderKey: ok)

        store.sync.schedulePush(debounceMs: 0)

        onImported()
        dismiss()
    }

    func openPDF(for r: Row) {
        if r.pdfPath.isEmpty { return }
        guard let u = resolveICloudDocumentsPath(r.pdfPath) else {
            pdfURL = nil
            showPDF = true
            return
        }

        if !shouldUseWindowForPDF {
            pdfURL = nil
            showPDF = true
        }

        Task {
            let ready = await forceDownloadICloudFile(u, maxWaitSeconds: 6.0)
            await MainActor.run {
                if shouldUseWindowForPDF {
                    openWindow(id: "clip-pdf", value: u)
                } else {
                    pdfURL = ready ? u : nil
                }
            }
        }
    }

    func waitForICloudFile(_ u: URL, maxWaitSeconds: Double) async -> Bool {
        let fm = FileManager.default

        try? fm.startDownloadingUbiquitousItem(at: u)

        let deadline = Date().timeIntervalSince1970 + maxWaitSeconds

        while Date().timeIntervalSince1970 < deadline {
            if fm.fileExists(atPath: u.path) {
                return true
            }

            if let st = try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus {
                if st == .current { return true }
            }

            try? await Task.sleep(nanoseconds: 250_000_000)
        }

        return fm.fileExists(atPath: u.path)
    }

    func forceDownloadICloudFile(_ u: URL, maxWaitSeconds: Double) async -> Bool {
        let fm = FileManager.default

        // Best-effort: drop local copy so iCloud fetches the latest.
        let isUbiquitous = (try? u.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
        if isUbiquitous {
            try? fm.evictUbiquitousItem(at: u)
        }

        return await waitForICloudFile(u, maxWaitSeconds: maxWaitSeconds)
    }


    func parseClipPayload(_ payload: String) -> (title: String, website: String, pdfPath: String, jsonPath: String) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "", "", "") }

        if
            let sections = obj["sections"] as? [String: Any],
            let clip = sections["clip"] as? [String: Any],
            let clipData = clip["data"] as? [String: Any]
        {
            let title = clipData["title"] as? String ?? ""
            let website = clipData["website"] as? String ?? ""
            let pdfPath =
                (clipData["pdf_path"] as? String)
                ?? (clipData["PDF_Path"] as? String)
                ?? ""
            let jsonPath =
                (clipData["json_path"] as? String)
                ?? (clipData["JSON_Path"] as? String)
                ?? ""
            return (title, website, pdfPath, jsonPath)
        }

        let title = obj["title"] as? String ?? ""
        let website = obj["website"] as? String ?? ""
        let pdfPath = obj["PDF_Path"] as? String ?? ""
        let jsonPath = obj["JSON_Path"] as? String ?? ""
        return (title, website, pdfPath, jsonPath)
    }

    func parseAudioPayload(_ payload: String) -> (title: String, audioPath: String, pdfPath: String, jsonPath: String, transcript: String) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "", "", "", "") }

        if
            let sections = obj["sections"] as? [String: Any],
            let audio = sections["audio"] as? [String: Any],
            let audioData = audio["data"] as? [String: Any]
        {
            let title = (audioData["title"] as? String) ?? "Audio Recording"
            let audioPath = (audioData["audio_path"] as? String) ?? ""
            var pdfPath = (audioData["pdf_path"] as? String) ?? ""
            var jsonPath = (audioData["json_path"] as? String) ?? ""
            if pdfPath.isEmpty, !audioPath.isEmpty {
                pdfPath = URL(fileURLWithPath: audioPath).deletingPathExtension().path + ".pdf"
            }
            if jsonPath.isEmpty, !audioPath.isEmpty {
                jsonPath = URL(fileURLWithPath: audioPath).deletingPathExtension().path + ".json"
            }
            if pdfPath.hasPrefix("/") { pdfPath.removeFirst() }
            if jsonPath.hasPrefix("/") { jsonPath.removeFirst() }
            let transcript = (audioData["transcript_txt"] as? String) ?? ""
            return (title, audioPath, pdfPath, jsonPath, transcript.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        return ("Audio Recording", "", "", "", "")
    }



    func resolveICloudDocumentsPath(_ relative: String) -> URL? {
        var rel = relative
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { return nil }

        let fm = FileManager.default

        if let root = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") {
            return root.appendingPathComponent(rel)
        }

        if let root2 = fm.url(forUbiquityContainerIdentifier: nil) {
            return root2.appendingPathComponent(rel)
        }

        return nil
    }


    func refreshICloudDiagForSelected() {
        let fm = FileManager.default
        let tokenOK = (fm.ubiquityIdentityToken != nil)

        let explicit = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal")
        let implicit = fm.url(forUbiquityContainerIdentifier: nil)

        let pdfPath = selectedRow?.pdfPath ?? ""
        let audioPath = selectedRow?.audioPath ?? ""

        var lines: [String] = []
        lines.append("token=\(tokenOK ? "OK" : "NIL")")
        lines.append("explicit=\(explicit?.path ?? "NIL")")
        lines.append("implicit=\(implicit?.path ?? "NIL")")
        if !audioPath.isEmpty {
            lines.append("Audio_Path=\(audioPath)")
        } else {
            lines.append("PDF_Path=\(pdfPath.isEmpty ? "EMPTY" : pdfPath)")
        }

        if !pdfPath.isEmpty || !audioPath.isEmpty {
            var rel = !audioPath.isEmpty ? audioPath : pdfPath
            if rel.hasPrefix("/") { rel.removeFirst() }

            if let e = explicit {
                let u = e.appendingPathComponent(rel)
                let exists = fm.fileExists(atPath: u.path)
                lines.append("E.exists=\(exists ? "Y" : "N")")
                lines.append("E.url=\(u.path)")
                if !exists {
                    let downloading = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus) ?? nil
                    if let downloading { lines.append("E.dl=\(downloading.rawValue)") }
                }
            }

            if let i = implicit {
                let u = i.appendingPathComponent(rel)
                let exists = fm.fileExists(atPath: u.path)
                lines.append("I.exists=\(exists ? "Y" : "N")")
                lines.append("I.url=\(u.path)")
                if !exists {
                    let downloading = (try? u.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]).ubiquitousItemDownloadingStatus) ?? nil
                    if let downloading { lines.append("I.dl=\(downloading.rawValue)") }
                }
            }
        }

        diagText = lines.joined(separator: "\n")
    }

    func deleteRow(_ r: Row) {
        store.notes.markBlockDeleted(blockID: r.id)
        store.sync.schedulePush(debounceMs: 0)

        if r.kind == .clip {
            deleteClipFiles(pdfPath: r.pdfPath, jsonPath: r.jsonPath)
        } else if r.kind == .audio {
            deleteAudioFiles(audioPath: r.audioPath, pdfPath: r.pdfPath, jsonPath: r.jsonPath)
        }

        rows.removeAll { $0.id == r.id }
        if selectedBlockID == r.id {
            selectedBlockID = nil
        }
    }

    func deleteAudioFiles(audioPath: String, pdfPath: String, jsonPath: String) {
        let fm = FileManager.default
        let audioURL = resolveICloudDocumentsPath(audioPath)
        let resolvedPDF: URL? = {
            if !pdfPath.isEmpty {
                return resolveICloudDocumentsPath(pdfPath)
            }
            guard !audioPath.isEmpty else { return nil }
            let rel = (audioPath as NSString).deletingPathExtension + ".pdf"
            return resolveICloudDocumentsPath(rel)
        }()
        let resolvedJSON: URL? = {
            if !jsonPath.isEmpty {
                return resolveICloudDocumentsPath(jsonPath)
            }
            guard !audioPath.isEmpty else { return nil }
            let rel = (audioPath as NSString).deletingPathExtension + ".json"
            return resolveICloudDocumentsPath(rel)
        }()

        if let u = audioURL {
            try? fm.removeItem(at: u)
        }
        if let p = resolvedPDF {
            try? fm.removeItem(at: p)
        }
        if let j = resolvedJSON {
            try? fm.removeItem(at: j)
        }
        if let dir = (audioURL ?? resolvedPDF ?? resolvedJSON)?.deletingLastPathComponent() {
            pruneEmptyDirs(start: dir)
        }
    }

    func deleteClipFiles(pdfPath: String, jsonPath: String) {
        let fm = FileManager.default

        let pdfURL = resolveICloudDocumentsPath(pdfPath)
        let jsonURL = resolveICloudDocumentsPath(jsonPath)

        if let u = pdfURL {
            try? fm.removeItem(at: u)
        }

        if let u = jsonURL {
            try? fm.removeItem(at: u)
        }

        if let dir = (pdfURL ?? jsonURL)?.deletingLastPathComponent() {
            pruneEmptyDirs(start: dir)
        }
    }

    func pruneEmptyDirs(start: URL) {
        let fm = FileManager.default
        var current = start

        while true {
            if current.lastPathComponent == "Documents" { break }
            let contents = (try? fm.contentsOfDirectory(atPath: current.path)) ?? []
            if !contents.isEmpty { break }
            try? fm.removeItem(at: current)
            current = current.deletingLastPathComponent()
        }
    }

    func njDate(_ ms: Int64) -> String {
        if ms <= 0 { return "" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

private extension NJClipboardInboxView {
    var shouldUseWindowForPDF: Bool {
        #if os(iOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        return idiom == .pad || idiom == .mac
        #else
        return true
        #endif
    }
}

struct PDFKitContainer: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
    }
}
