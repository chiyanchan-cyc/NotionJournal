import SwiftUI
import CoreLocation

struct NJGPSStatusBadge: View {
    @ObservedObject private var logger = NJGPSLogger.shared
    @State private var showLoggerSheet = false

    var body: some View {
        Button {
            logger.refreshAuthorityUI()
            showLoggerSheet = true
        } label: {
            Image(systemName: statusSymbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(statusColor)
                .padding(8)
                .background(
                    Circle()
                        .fill(statusColor.opacity(0.14))
                )
                .overlay(
                    Circle()
                        .stroke(statusColor.opacity(0.35), lineWidth: 1)
                )
                .accessibilityLabel(statusTitle)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showLoggerSheet) {
            NavigationStack {
                NJGPSLoggerPage()
            }
        }
        .task {
            logger.refreshAuthorityUI()
        }
        .contextMenu {
            Label(statusTitle, systemImage: statusSymbol)
            if !statusSubtitle.isEmpty {
                Text(statusSubtitle)
            }
            Divider()
            Button("Open GPS Logger") {
                showLoggerSheet = true
            }
            if !logger.isWriter && !logger.writerLabel.isEmpty {
                Text("Writer: \(logger.writerLabel)")
            }
        }
    }

    private var statusTitle: String {
        if isHealthy {
            return "iPhone GPS active"
        }
        if !logger.enabled {
            return "Turn on GPS logger"
        }
        switch logger.auth {
        case .restricted, .denied:
            return "Allow GPS always"
        case .notDetermined:
            return "Set GPS permission"
        default:
            break
        }
        if !logger.isWriter {
            return logger.writerLabel.isEmpty ? "This iPhone is not the GPS logger" : "GPS logger is active on another device"
        }
        return "GPS needs attention"
    }

    private var statusSubtitle: String {
        if isHealthy, logger.lastWriteTsMs > 0 {
            return "Last write \(relativeDate(logger.lastWriteTsMs))"
        }
        if !logger.isWriter && !logger.writerLabel.isEmpty {
            return "Current writer: \(logger.writerLabel)"
        }
        if !logger.lastError.isEmpty {
            return logger.lastError
        }
        return ""
    }

    private var statusSymbol: String {
        isHealthy ? "location.fill" : "location.slash.fill"
    }

    private var statusColor: Color {
        isHealthy ? .green : .red
    }

    private var isHealthy: Bool {
        logger.enabled &&
        (logger.auth == .authorizedAlways || logger.auth == .authorizedWhenInUse) &&
        logger.isWriter
    }

    private func relativeDate(_ ms: Int64) -> String {
        let date = Date(timeIntervalSince1970: TimeInterval(ms) / 1000.0)
        return date.formatted(.relative(presentation: .named))
    }
}
