import SwiftUI
import CoreLocation
import UIKit

struct NJGPSLoggerPage: View {
    @ObservedObject private var logger = NJGPSLogger.shared

    var body: some View {
        Form {
            Section("Permission") {
                Button("Request While Using") {
                    NJGPSLogger.shared.requestWhenInUse()
                }

                Button("Request Always") {
                    NJGPSLogger.shared.requestAlways()
                }

                Button("Open Settings") {
                    if let u = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(u)
                    }
                }
            }

            Section("GPS Logger") {
                Toggle(isOn: Binding(get: { logger.enabled }, set: { NJGPSLogger.shared.setEnabled($0) })) {
                    Text("Enable on this device")
                }

                Picker("Power", selection: Binding(get: { logger.power }, set: { NJGPSLogger.shared.setPower($0) })) {
                    ForEach(NJGPSLogger.NJGPSPower.allCases) { p in
                        Text(p.title).tag(p)
                    }
                }

                Button("Refresh Authority") {
                    NJGPSLogger.shared.refreshAuthorityUI()
                }

                NavigationLink("View Tracks") {
                    NJGPSLogViewerPage()
                }

                Button("Rebuild Transit Summary (Today)") {
                    NJGPSLogger.shared.rebuildTransitSummaryToday()
                }

                Button("Backfill Transit (30 days)") {
                    NJGPSLogger.shared.rebuildTransitSummary(daysBack: 30)
                }
            }


            // In the Status section of NJGPSLoggerPage.swift
            Section("Status") {
                row("Auth", authText(logger.auth))
                row("Active writer", logger.isWriter ? "YES" : "NO")
                if !logger.writerLabel.isEmpty {
                    row("Writer device", logger.writerLabel)
                    
                    // Add button only when another device is the writer
                    if !logger.isWriter {
                        Button("Take Over (Clear Lock)") {
                            NJGPSLogger.shared.forceClearLock()
                        }
                        .foregroundColor(.orange)
                    }
                }
                if logger.lastWriteTsMs > 0 {
                    row("Last write", fmtMs(logger.lastWriteTsMs))
                }
                if !logger.lastError.isEmpty {
                    Text(logger.lastError).font(.footnote).foregroundStyle(.secondary)
                }
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
