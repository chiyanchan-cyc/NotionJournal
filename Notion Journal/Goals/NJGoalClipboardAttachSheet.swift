import SwiftUI

struct NJGoalClipboardAttachSheet: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss

    let goalID: String

    @State private var rows: [Row] = []
    @State private var selectedBlockID: String? = nil

    struct Row: Identifiable, Equatable {
        let id: String
        let createdAtMs: Int64
        let title: String
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
                                Text(r.kind == .clip ? "Clip" : "Audio")
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
                }
            }

            Divider()

            HStack(spacing: 10) {
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
    }

    private func reload() {
        let raw = store.notes.listOrphanClipBlocks(limit: 500)
        let rawAudio = store.notes.listOrphanAudioBlocks(limit: 500)

        var out: [Row] = []
        out.reserveCapacity(raw.count + rawAudio.count)

        for r in raw {
            let meta = parseClipPayload(r.payloadJSON)
            out.append(Row(
                id: r.id,
                createdAtMs: r.createdAtMs,
                title: meta.title,
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
                kind: .audio
            ))
        }

        rows = out.sorted { $0.createdAtMs > $1.createdAtMs }
    }

    private func attachSelected() {
        guard let row = selectedRow else { return }
        store.notes.setBlockGoalID(blockID: row.id, goalID: goalID)
        dismiss()
    }

    private func parseClipPayload(_ payload: String) -> (title: String, website: String, pdfPath: String, jsonPath: String) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "", "", "") }

        let title = (obj["title"] as? String) ?? ""
        let website = (obj["website"] as? String) ?? ""
        let pdfPath = (obj["pdf_path"] as? String) ?? ""
        let jsonPath = (obj["json_path"] as? String) ?? ""
        return (title, website, pdfPath, jsonPath)
    }

    private func parseAudioPayload(_ payload: String) -> (title: String, transcript: String) {
        guard
            let data = payload.data(using: .utf8),
            let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("", "") }

        let title = (obj["title"] as? String) ?? ""
        let transcript = (obj["transcript"] as? String) ?? ""
        return (title, transcript)
    }

    private func njDate(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }
}
