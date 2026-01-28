//
//  NJGPSLoggerPage.swift
//  Notion Journal
//
//  Created by Mac on 2026/1/28.
//


import SwiftUI
import CoreLocation

struct NJGPSLoggerPage: View {
    @ObservedObject private var logger = NJGPSLogger.shared

    var body: some View {
        Form {
            Section("GPS Logger") {
                Toggle(isOn: Binding(get: { logger.enabled }, set: { logger.setEnabled($0) })) {
                    Text("Enable on this device")
                }

                Button("Request Always Location") {
                    logger.requestAlways()
                }

                Button("Refresh Authority") {
                    logger.refreshAuthorityUI()
                }
            }

            Section("Status") {
                row("Auth", authText(logger.auth))
                row("Active writer", logger.isWriter ? "YES" : "NO")
                if !logger.writerLabel.isEmpty {
                    row("Writer device", logger.writerLabel)
                }
                if logger.lastWriteTsMs > 0 {
                    row("Last write", fmtMs(logger.lastWriteTsMs))
                }
                if !logger.lastError.isEmpty {
                    Text(logger.lastError).font(.footnote).foregroundStyle(.secondary)
                }
            }

            Section("Log") {
                Text("iCloud: Documents/GPS/YYYY/MM/YYYY-MM-DD.ndjson")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("GPS Logger")
    }

    private func row(_ k: String, _ v: String) -> some View {
        HStack {
            Text(k)
            Spacer()
            Text(v).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func authText(_ s: CLAuthorizationStatus) -> String {
        switch s {
        case .notDetermined: return "notDetermined"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorizedWhenInUse: return "whenInUse"
        case .authorizedAlways: return "always"
        @unknown default: return "unknown"
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
