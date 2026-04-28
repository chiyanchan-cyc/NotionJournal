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
                removeAllOverrunNotifications(center: center) {
                    schedule(slots: slots, now: now, center: center)
                }
            case .notDetermined:
                center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                    guard granted else { return }
                    removeAllOverrunNotifications(center: center) {
                        schedule(slots: slots, now: now, center: center)
                    }
                }
            case .denied:
                removeAllOverrunNotifications(center: center, completion: nil)
            @unknown default:
                return
            }
        }
    }

    static func cancelAll() {
        removeAllOverrunNotifications(center: UNUserNotificationCenter.current(), completion: nil)
    }

    private static func schedule(slots: [NJTimeSlotRecord], now: Date, center: UNUserNotificationCenter) {
        let activeSlots = slots.filter { reminderEligible(for: $0, now: now) }
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

    private static func bodyText(minutesLate: Int) -> String {
        if minutesLate == firstReminderMinutes {
            return "This activity ended 30 minutes ago. End it if you are done."
        }
        return "This activity is now \(minutesLate) minutes past its planned end."
    }

    private static func reminderEligible(for slot: NJTimeSlotRecord, now: Date) -> Bool {
        guard slot.deleted == 0 else { return false }

        // Watch timers are already completed when they arrive on iPhone.
        // They should be logged, but never re-enter the overrun reminder flow.
        let notes = slot.notes.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if notes.contains("from watch tracker") {
            return false
        }

        // A slot updated at or after its own end time is treated as already finished.
        // Watch-tracked sessions land in this state when the user ends the tracker.
        if slot.updatedAtMs >= slot.endAtMs {
            return false
        }

        return true
    }

    private static func pendingIdentifiers(for slots: [NJTimeSlotRecord]) -> [String] {
        slots.flatMap { slot in
            (0..<maxReminderCount).map { step in
                identifier(for: slot.timeSlotID, step: step)
            }
        }
    }

    private static func removeAllOverrunNotifications(
        center: UNUserNotificationCenter,
        completion: (() -> Void)?
    ) {
        center.getPendingNotificationRequests { requests in
            let pending = requests.map(\.identifier).filter { $0.hasPrefix(prefix) }
            if !pending.isEmpty {
                center.removePendingNotificationRequests(withIdentifiers: pending)
            }

            center.getDeliveredNotifications { notifications in
                let delivered = notifications
                    .map(\.request.identifier)
                    .filter { $0.hasPrefix(prefix) }
                if !delivered.isEmpty {
                    center.removeDeliveredNotifications(withIdentifiers: delivered)
                }
                completion?()
            }
        }
    }

    private static func identifier(for timeSlotID: String, step: Int) -> String {
        "\(prefix)\(timeSlotID).\(step)"
    }
}
