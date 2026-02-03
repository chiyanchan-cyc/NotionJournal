import SwiftUI

struct NJHealthLoggerPage: View {
    @ObservedObject private var logger = NJHealthLogger.shared

    var body: some View {
        Form {
            Section("Permission") {
                Button("Request Health Access") {
                    NJHealthLogger.shared.requestAuthorization()
                }

                Button("Refresh Authority") {
                    NJHealthLogger.shared.refreshAuthorityUI()
                }
            }

            Section("Health Logger") {
                Toggle(isOn: Binding(get: { logger.enabled }, set: { NJHealthLogger.shared.setEnabled($0) })) {
                    Text("Enable on this device")
                }

                Toggle(isOn: Binding(get: { logger.healthRecordsEnabled }, set: { NJHealthLogger.shared.setHealthRecordsEnabled($0) })) {
                    Text("Enable Health Records (Medications)")
                }
                .disabled(!logger.healthRecordsAvailable)
                .foregroundStyle(logger.healthRecordsAvailable ? .primary : .secondary)

                Button("Sync Now") {
                    NJHealthLogger.shared.syncNow()
                }
            }

            Section("Status") {
                row("Auth", logger.auth.rawValue)
                row("Active writer", logger.isWriter ? "YES" : "NO")
                if !logger.writerLabel.isEmpty {
                    row("Writer device", logger.writerLabel)
                }
                row("Health Records", logger.healthRecordsAvailable ? (logger.healthRecordsEnabled ? "ENABLED" : "AVAILABLE") : "NO")
                if logger.lastSyncTsMs > 0 {
                    row("Last sync", fmtMs(logger.lastSyncTsMs))
                }
                if !logger.lastSyncSummary.isEmpty {
                    Text(logger.lastSyncSummary).font(.footnote).foregroundStyle(.secondary)
                }
                if !logger.lastError.isEmpty {
                    Text(logger.lastError).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Health Logger")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
            Spacer()
            Text(v).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func fmtMs(_ ms: Int64) -> String {
        let d = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: d)
    }
}
