import SwiftUI
import PDFKit

struct NJClipboardInboxView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

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

                List(selection: $selectedBlockID) {
                    ForEach(rows) { r in
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
                        .onTapGesture { selectedBlockID = r.id }
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
                    Button("Diag iCloud") {
                        refreshICloudDiagForSelected()
                    }

                    Button("Open PDF") {
                        guard let r = selectedRow else { return }
                        refreshICloudDiagForSelected()
                        openPDF(for: r)
                    }
                    .disabled(selectedBlockID == nil)

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

        var out: [Row] = []
        out.reserveCapacity(raw.count)

        for r in raw {
            let meta = parseClipPayload(r.payloadJSON)
            out.append(
                Row(
                    id: r.id,
                    createdAtMs: r.createdAtMs,
                    website: meta.website,
                    title: meta.title,
                    pdfPath: meta.pdfPath
                )
            )
        }

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
        guard let u = resolveICloudDocumentsPath(r.pdfPath) else {
            pdfURL = nil
            showPDF = true
            return
        }
        pdfURL = u
        showPDF = true
    }

    func parseClipPayload(_ payload: String) -> (title: String, website: String, pdfPath: String) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "", "") }

        let title = obj["title"] as? String ?? ""
        let website = obj["website"] as? String ?? ""
        let pdfPath = obj["PDF_Path"] as? String ?? ""
        return (title, website, pdfPath)
    }

    func resolveICloudDocumentsPath(_ relative: String) -> URL? {
        var rel = relative
        if rel.hasPrefix("/") { rel.removeFirst() }
        if rel.isEmpty { return nil }

        let fm = FileManager.default

        if let root = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal") {
            let u = root.appendingPathComponent(rel)
            if fm.fileExists(atPath: u.path) { return u }
            try? fm.startDownloadingUbiquitousItem(at: u)
            if fm.fileExists(atPath: u.path) { return u }
        }

        if let root2 = fm.url(forUbiquityContainerIdentifier: nil) {
            let u2 = root2.appendingPathComponent(rel)
            if fm.fileExists(atPath: u2.path) { return u2 }
            try? fm.startDownloadingUbiquitousItem(at: u2)
            if fm.fileExists(atPath: u2.path) { return u2 }
        }

        return nil
    }

    func refreshICloudDiagForSelected() {
        let fm = FileManager.default
        let tokenOK = (fm.ubiquityIdentityToken != nil)

        let explicit = fm.url(forUbiquityContainerIdentifier: "iCloud.com.CYC.NotionJournal")
        let implicit = fm.url(forUbiquityContainerIdentifier: nil)

        let pdfPath = selectedRow?.pdfPath ?? ""

        var lines: [String] = []
        lines.append("token=\(tokenOK ? "OK" : "NIL")")
        lines.append("explicit=\(explicit?.path ?? "NIL")")
        lines.append("implicit=\(implicit?.path ?? "NIL")")
        lines.append("PDF_Path=\(pdfPath.isEmpty ? "EMPTY" : pdfPath)")

        if !pdfPath.isEmpty {
            var rel = pdfPath
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

    func njDate(_ ms: Int64) -> String {
        if ms <= 0 { return "" }
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
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
