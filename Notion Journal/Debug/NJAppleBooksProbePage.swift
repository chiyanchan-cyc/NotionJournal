import SwiftUI
import SQLite3

struct NJAppleBooksProbeResult: Identifiable {
    let id = UUID()
    let label: String
    let path: String
    let exists: Bool
    let readable: Bool
    let sqliteStatus: String
    let detail: String
}

enum NJAppleBooksProbe {
    static let knownIPhoneBooksContainer = "/private/var/mobile/Containers/Data/Application/90FFAB9D-3F90-4EA8-BEA2-A2D1223F2198"

    static var candidatePaths: [(String, String)] {
        let ownHome = NSHomeDirectory()
        return [
            ("App sandbox home", ownHome),
            ("App documents", "\(ownHome)/Documents"),
            ("Books sessions DB (known iPhone container)", "\(knownIPhoneBooksContainer)/Documents/BCRecentlyOpenedBooksDB/BCRecentlyOpenedBooksDB.sqlite"),
            ("Books library DB (known iPhone container)", "\(knownIPhoneBooksContainer)/Documents/BKLibrary/BKLibrary-1-091020131601.sqlite"),
            ("Books annotations DB (known iPhone container)", "\(knownIPhoneBooksContainer)/Documents/AEAnnotation/AEAnnotation_v10312011_1727_local.sqlite"),
            ("iOS app containers root", "/private/var/mobile/Containers/Data/Application"),
            ("iOS app groups root", "/private/var/mobile/Containers/Shared/AppGroup"),
            ("Books app group guess", "/private/var/mobile/Containers/Shared/AppGroup/group.com.apple.iBooks")
        ]
    }

    static func run() -> [NJAppleBooksProbeResult] {
        let results = candidatePaths.map { label, path in
            probe(label: label, path: path)
        }
        for result in results {
            print(
                "NJ_BOOKS_PROBE label=\"\(result.label)\" exists=\(result.exists ? 1 : 0) readable=\(result.readable ? 1 : 0) sqlite=\"\(result.sqliteStatus)\" path=\"\(result.path)\" detail=\"\(result.detail)\""
            )
        }
        return results
    }

    private static func probe(label: String, path: String) -> NJAppleBooksProbeResult {
        let fm = FileManager.default
        var isDirectory: ObjCBool = false
        let exists = fm.fileExists(atPath: path, isDirectory: &isDirectory)
        let readable = fm.isReadableFile(atPath: path)

        if isDirectory.boolValue {
            do {
                let items = try fm.contentsOfDirectory(atPath: path)
                return NJAppleBooksProbeResult(
                    label: label,
                    path: path,
                    exists: exists,
                    readable: readable,
                    sqliteStatus: "directory",
                    detail: "items=\(items.prefix(8).joined(separator: ",")) count=\(items.count)"
                )
            } catch {
                return NJAppleBooksProbeResult(
                    label: label,
                    path: path,
                    exists: exists,
                    readable: readable,
                    sqliteStatus: "directory denied",
                    detail: error.localizedDescription
                )
            }
        }

        guard path.hasSuffix(".sqlite") else {
            return NJAppleBooksProbeResult(
                label: label,
                path: path,
                exists: exists,
                readable: readable,
                sqliteStatus: "not sqlite",
                detail: exists ? "file exists" : "not visible from this app sandbox"
            )
        }

        return sqliteProbe(label: label, path: path, exists: exists, readable: readable)
    }

    private static func sqliteProbe(label: String, path: String, exists: Bool, readable: Bool) -> NJAppleBooksProbeResult {
        var db: OpaquePointer?
        let flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_URI
        let rc = sqlite3_open_v2(path, &db, flags, nil)
        defer {
            if let db {
                sqlite3_close(db)
            }
        }

        guard rc == SQLITE_OK, let db else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "sqlite handle unavailable"
            return NJAppleBooksProbeResult(
                label: label,
                path: path,
                exists: exists,
                readable: readable,
                sqliteStatus: "open rc=\(rc)",
                detail: message
            )
        }

        let sessionCount = scalarString(db: db, sql: "SELECT COUNT(*) FROM ZBCASSETREADINGSESSION;")
        let latestSession = scalarString(
            db: db,
            sql: "SELECT datetime(MAX(ZTIMEOPENED) + 978307200, 'unixepoch', 'localtime') FROM ZBCASSETREADINGSESSION;"
        )
        let assetCount = scalarString(db: db, sql: "SELECT COUNT(*) FROM ZBKLIBRARYASSET;")
        let annotationCount = scalarString(db: db, sql: "SELECT COUNT(*) FROM ZAEANNOTATION;")

        let parts = [
            sessionCount.map { "sessions=\($0)" },
            latestSession.map { "latestSession=\($0)" },
            assetCount.map { "assets=\($0)" },
            annotationCount.map { "annotations=\($0)" }
        ].compactMap { $0 }

        return NJAppleBooksProbeResult(
            label: label,
            path: path,
            exists: exists,
            readable: readable,
            sqliteStatus: "open ok",
            detail: parts.isEmpty ? "opened, but known Books tables not found" : parts.joined(separator: " ")
        )
    }

    private static func scalarString(db: OpaquePointer, sql: String) -> String? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else {
            return nil
        }

        if let text = sqlite3_column_text(stmt, 0) {
            return String(cString: text)
        }
        return nil
    }
}

struct NJAppleBooksProbePage: View {
    @State private var results: [NJAppleBooksProbeResult] = []
    @State private var lastRun: Date?

    var body: some View {
        Form {
            Section("Probe") {
                Button("Run Apple Books Probe") {
                    results = NJAppleBooksProbe.run()
                    lastRun = Date()
                }

                if let lastRun {
                    Text("Last run \(format(lastRun))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Results") {
                if results.isEmpty {
                    Text("Run the probe while attached to Xcode. Console lines start with NJ_BOOKS_PROBE.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(results) { result in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(result.label)
                                .font(.headline)
                            Text(result.sqliteStatus)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text("exists \(result.exists ? "YES" : "NO") · readable \(result.readable ? "YES" : "NO")")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(result.path)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .textSelection(.enabled)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("Apple Books Probe")
        .toolbar {
            Button("Run") {
                results = NJAppleBooksProbe.run()
                lastRun = Date()
            }
        }
    }

    private func format(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}
