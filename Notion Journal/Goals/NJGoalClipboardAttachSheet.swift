import SwiftUI

struct NJGoalClipboardAttachSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.openWindow) private var openWindow

    let goalID: String

    @State private var rows: [Row] = []
    @State private var selectedBlockID: String? = nil
    @State private var showPDF = false
    @State private var pdfURL: URL? = nil

    struct Row: Identifiable, Equatable {
        let id: String
        let createdAtMs: Int64
        let title: String
        let pdfPath: String
        let jsonPath: String
        let audioPath: String
        let kind: Kind
    }

    enum Kind: String, Equatable {
        case clip
        case audio
        case quick
    }

    var selectedRow: Row? {
        guard let bid = selectedBlockID else { return nil }
        return rows.first(where: { $0.id == bid })
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    ForEach(rows) { r in
                        Button {
                            selectedBlockID = r.id
                        } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                HStack(spacing: 8) {
                                    Text(njDate(r.createdAtMs))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                Text(kindLabel(r.kind))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
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
                        .simultaneousGesture(
                            TapGesture(count: 2).onEnded {
                                selectedBlockID = r.id
                                openPDF(for: r)
                            }
                        )
                    }
                }

                Divider()

                HStack(spacing: 10) {
                    Button("Open PDF") {
                        guard let r = selectedRow, !r.pdfPath.isEmpty else { return }
                        openPDF(for: r)
                    }
                    .disabled(selectedBlockID == nil || (selectedRow?.pdfPath.isEmpty ?? true))

                    Spacer()
                    Button("Attach") {
                        attachSelected()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedBlockID == nil)
                }
                .padding(12)
            }
            .navigationTitle("Attach From Clipboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("Refresh") { reload() }
                }
            }
            .onAppear { reload() }
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

    private func reload() {
        let raw = store.notes.listOrphanClipBlocks(limit: 500)
        let rawAudio = store.notes.listOrphanAudioBlocks(limit: 500)
        let rawQuick = store.notes.listOrphanQuickBlocks(limit: 500)

        var out: [Row] = []
        out.reserveCapacity(raw.count + rawAudio.count + rawQuick.count)

        for r in raw {
            let meta = parseClipPayload(r.payloadJSON)
            out.append(Row(
                id: r.id,
                createdAtMs: r.createdAtMs,
                title: meta.title,
                pdfPath: meta.pdfPath,
                jsonPath: meta.jsonPath,
                audioPath: "",
                kind: .clip
            ))
        }

        for r in rawAudio {
            let meta = parseAudioPayload(r.payloadJSON)
            if meta.transcript.isEmpty { continue }
            out.append(Row(
                id: r.id,
                createdAtMs: r.createdAtMs,
                title: meta.title,
                pdfPath: meta.pdfPath,
                jsonPath: meta.jsonPath,
                audioPath: meta.audioPath,
                kind: .audio
            ))
        }

        for r in rawQuick {
            let title = parseQuickPayload(r.payloadJSON)
            out.append(Row(
                id: r.id,
                createdAtMs: r.createdAtMs,
                title: title,
                pdfPath: "",
                jsonPath: "",
                audioPath: "",
                kind: .quick
            ))
        }

        rows = out.sorted { $0.createdAtMs > $1.createdAtMs }
    }

    private func attachSelected() {
        guard let row = selectedRow else { return }
        store.notes.setBlockGoalID(blockID: row.id, goalID: goalID)
        dismiss()
    }

    private func openPDF(for r: Row) {
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

    private func waitForICloudFile(_ u: URL, maxWaitSeconds: Double) async -> Bool {
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

    private func forceDownloadICloudFile(_ u: URL, maxWaitSeconds: Double) async -> Bool {
        let fm = FileManager.default

        let isUbiquitous = (try? u.resourceValues(forKeys: [.isUbiquitousItemKey]).isUbiquitousItem) ?? false
        if isUbiquitous {
            try? fm.evictUbiquitousItem(at: u)
        }

        return await waitForICloudFile(u, maxWaitSeconds: maxWaitSeconds)
    }

    private func parseClipPayload(_ payload: String) -> (title: String, pdfPath: String, jsonPath: String) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "", "") }

        if
            let sections = obj["sections"] as? [String: Any],
            let clip = sections["clip"] as? [String: Any],
            let clipData = clip["data"] as? [String: Any]
        {
            let title = clipData["title"] as? String ?? ""
            let pdfPath =
                (clipData["pdf_path"] as? String)
                ?? (clipData["PDF_Path"] as? String)
                ?? ""
            let jsonPath =
                (clipData["json_path"] as? String)
                ?? (clipData["JSON_Path"] as? String)
                ?? ""
            return (title, pdfPath, jsonPath)
        }

        let title = obj["title"] as? String ?? ""
        let pdfPath = obj["PDF_Path"] as? String ?? ""
        let jsonPath = obj["JSON_Path"] as? String ?? ""
        return (title, pdfPath, jsonPath)
    }

    private func parseAudioPayload(_ payload: String) -> (title: String, audioPath: String, pdfPath: String, jsonPath: String, transcript: String) {
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

    private func parseQuickPayload(_ payload: String) -> String {
        NJQuickNotePayload.title(from: payload)
    }

    private func kindLabel(_ kind: Kind) -> String {
        switch kind {
        case .clip: return "Clip"
        case .audio: return "Audio"
        case .quick: return "Quick Note"
        }
    }

    private func resolveICloudDocumentsPath(_ relative: String) -> URL? {
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

    private func njDate(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}

private extension NJGoalClipboardAttachSheet {
    var shouldUseWindowForPDF: Bool {
        #if os(iOS)
        let idiom = UIDevice.current.userInterfaceIdiom
        return idiom == .pad || idiom == .mac
        #else
        return true
        #endif
    }
}
