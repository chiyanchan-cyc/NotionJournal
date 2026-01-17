import SwiftUI

struct NJDebugSQLConsole: View {
    let db: SQLiteDB

    @State private var sql: String = "SELECT name FROM sqlite_master;"
    @State private var output: String = ""
    @State private var ranAt: Date?

    @State private var topHeight: CGFloat = 220
    @State private var isMaximized: Bool = false
    @State private var copiedAt: Date?

    @State private var showNukeConfirm: Bool = false

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geo in
            let totalH = geo.size.height
            let headerH: CGFloat = 44
            let toolbarH: CGFloat = 44
            let dividerH: CGFloat = 10
            let minTop: CGFloat = 120
            let maxTop: CGFloat = max(minTop, totalH - headerH - toolbarH - dividerH - 120)
            let effectiveTop = isMaximized ? maxTop : min(max(topHeight, minTop), maxTop)

            VStack(spacing: 0) {
                HStack(spacing: 10) {
                    HStack(spacing: 8) {
                        Button(action: { dismiss() }) {
                            Circle().fill(Color.red).frame(width: 12, height: 12)
                        }.buttonStyle(.plain)

                        Button(action: { }) {
                            Circle().fill(Color.yellow).frame(width: 12, height: 12)
                        }.buttonStyle(.plain)

                        Button(action: { isMaximized.toggle() }) {
                            Circle().fill(Color.green).frame(width: 12, height: 12)
                        }.buttonStyle(.plain)
                    }

                    Text("SQLite Console")
                        .font(.headline)

                    Spacer()

                    if let ranAt {
                        Text("Last run: \(ranAt.formatted())")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    if let copiedAt {
                        Text("Copied: \(copiedAt.formatted(date: .omitted, time: .standard))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: headerH)

                Divider()

                TextEditor(text: $sql)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(8)
                    .background(Color.gray.opacity(0.06))
                    .frame(height: effectiveTop)

                ZStack {
                    Rectangle()
                        .fill(Color.gray.opacity(0.12))
                    Image(systemName: "line.3.horizontal")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(height: dividerH)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { v in
                            if isMaximized { isMaximized = false }
                            topHeight = min(maxTop, max(minTop, effectiveTop + v.translation.height))
                        }
                )

                HStack(spacing: 12) {
                    Button("Run") { run() }

                    Button("Copy") { copyOutput() }
                        .disabled(output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button(role: .destructive) { showNukeConfirm = true } label: {
                        Text("NUKE + CK RESET")
                    }

                    Spacer()

                    Button("Close") { dismiss() }
                }
                .padding(.horizontal, 12)
                .frame(height: toolbarH)

                Divider()

                TextEditor(text: .constant(output))
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                    .disabled(true)
                    .padding(8)
                    .background(Color.gray.opacity(0.04))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle("DB Console")
        .alert("Nuke local DB and reset CloudKit cursors?", isPresented: $showNukeConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("NUKE", role: .destructive) { nukeAndResetCK() }
        } message: {
            Text("This wipes local tables and clears CK cursors so next bootstrap pulls everything from CloudKit again.")
        }
    }

    private func run() {
        ranAt = Date()
        let rows = db.queryRows(sql)
        guard !rows.isEmpty else {
            output = "No rows returned."
            return
        }
        let keys = rows.first!.keys.sorted()
        var lines: [String] = []
        lines.append(keys.joined(separator: " | "))
        lines.append(String(repeating: "-", count: 80))
        for row in rows {
            let line = keys.map { "\(row[$0] ?? "NULL")" }.joined(separator: " | ")
            lines.append(line)
        }
        output = lines.joined(separator: "\n")
    }

    private func copyOutput() {
        let text = output
        guard !text.isEmpty else { return }

        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
        #endif

        copiedAt = Date()
    }

    private func nukeAndResetCK() {
        DBSchemaInstaller.hardRecreateSchema(db: db)
        db.resetCloudKitCursors()
        db.exec("DELETE FROM nj_kv WHERE k IN ('ck_bootstrap_done', 'ck_bootstrap_v');")
        output = [
            "OK: Local DB nuked, CK cursors cleared.",
            "Next: Relaunch app or trigger bootstrap pull.",
            "",
            "Run this to verify empty local:",
            "SELECT COUNT(*) AS cnt FROM nj_notebook;",
            "SELECT COUNT(*) AS cnt FROM nj_tab;",
            "SELECT COUNT(*) AS cnt FROM nj_note;",
            "",
            "Then wait for CK bootstrap and re-check counts."
        ].joined(separator: "\n")
        ranAt = Date()
    }
}
