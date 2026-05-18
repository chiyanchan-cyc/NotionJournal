import Foundation
import UserNotifications

enum NJInvestmentWatchlistNotifier {
    static func notifyCriticalNews(title: String, source: String, summary: String) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                scheduleCriticalNews(center: center, title: title, source: source, summary: summary)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    scheduleCriticalNews(center: center, title: title, source: source, summary: summary)
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    static func notify(
        symbol: String,
        name: String,
        priceText: String,
        levelText: String,
        severity: String,
        decisionQuestion: String
    ) {
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule(
                    center: center,
                    symbol: symbol,
                    name: name,
                    priceText: priceText,
                    levelText: levelText,
                    severity: severity,
                    decisionQuestion: decisionQuestion
                )
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    schedule(
                        center: center,
                        symbol: symbol,
                        name: name,
                        priceText: priceText,
                        levelText: levelText,
                        severity: severity,
                        decisionQuestion: decisionQuestion
                    )
                }
            case .denied:
                return
            @unknown default:
                return
            }
        }
    }

    private static func schedule(
        center: UNUserNotificationCenter,
        symbol: String,
        name: String,
        priceText: String,
        levelText: String,
        severity: String,
        decisionQuestion: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "\(symbol) \(severity) alert"
        content.body = "\(name) reached \(priceText), triggering \(levelText). \(decisionQuestion)"
        content.sound = .default
        content.categoryIdentifier = "NJ_INVESTMENT_WATCHLIST"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "nj.investment.watchlist.\(symbol).\(severity).\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }

    private static func scheduleCriticalNews(
        center: UNUserNotificationCenter,
        title: String,
        source: String,
        summary: String
    ) {
        let content = UNMutableNotificationContent()
        content.title = "Critical investment news"
        content.body = [title, source, summary].filter { !$0.isEmpty }.joined(separator: " - ")
        content.sound = .default
        content.categoryIdentifier = "NJ_INVESTMENT_CRITICAL_NEWS"

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "nj.investment.critical.news.\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: trigger
        )
        center.add(request)
    }
}
