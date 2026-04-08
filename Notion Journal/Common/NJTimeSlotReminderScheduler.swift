import Foundation
import UserNotifications

enum NJTimeSlotReminderScheduler {
    private static let prefix = "nj.timeslot.overrun."
    private static let firstReminderMinutes = 30
    private static let repeatReminderMinutes = 15
    private static let maxReminderCount = 12

    static func reschedule(slots: [NJTimeSlotRecord], now: Date = Date()) {
        let center = UNUserNotificationCenter.current()

        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                schedule(slots: slots, now: now, center: center)
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    schedule(slots: slots, now: now, center: center)
                }
            case .denied:
                center.removePendingNotificationRequests(withIdentifiers: pendingIdentifiers(for: slots))
            @unknown default:
                return
            }
        }
    }

    private static func schedule(slots: [NJTimeSlotRecord], now: Date, center: UNUserNotificationCenter) {
        let activeSlots = slots.filter { $0.deleted == 0 }
        center.getPendingNotificationRequests { requests in
            let existing = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !existing.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: existing)
            }

            let nowMs = Int64(now.timeIntervalSince1970 * 1000.0)
            for slot in activeSlots {
                let endDate = Date(timeIntervalSince1970: TimeInterval(slot.endAtMs) / 1000.0)
                for step in 0..<maxReminderCount {
                    let minutesLate = firstReminderMinutes + (step * repeatReminderMinutes)
                    let triggerDate = endDate.addingTimeInterval(TimeInterval(minutesLate * 60))
                    guard triggerDate.timeIntervalSince1970 * 1000.0 > Double(nowMs) else { continue }

                    let content = UNMutableNotificationContent()
                    content.title = slot.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Time activity still running" : slot.title
                    content.body = bodyText(minutesLate: minutesLate)
                    content.sound = .default

                    let interval = triggerDate.timeIntervalSince(now)
                    guard interval >= 1 else { continue }

                    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
                    let request = UNNotificationRequest(
                        identifier: identifier(for: slot.timeSlotID, step: step),
                        content: content,
                        trigger: trigger
                    )
                    center.add(request)
                }
            }
        }
    }

    private static func bodyText(minutesLate: Int) -> String {
        if minutesLate == firstReminderMinutes {
            return "This activity ended 30 minutes ago. End it if you are done."
        }
        return "This activity is now \(minutesLate) minutes past its planned end."
    }

    private static func pendingIdentifiers(for slots: [NJTimeSlotRecord]) -> [String] {
        slots.flatMap { slot in
            (0..<maxReminderCount).map { step in
                identifier(for: slot.timeSlotID, step: step)
            }
        }
    }

    private static func identifier(for timeSlotID: String, step: Int) -> String {
        "\(prefix)\(timeSlotID).\(step)"
    }
}
