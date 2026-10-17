import Foundation
import UserNotifications

/// Local reminders before the bank consent expires. No push, no server.
enum ConsentReminders {
    static let daysBefore = [14, 3]

    static func schedule(validUntil: Date) async {
        let center = UNUserNotificationCenter.current()
        guard (try? await center.requestAuthorization(options: [.alert, .sound])) == true else { return }
        cancel()
        for days in daysBefore {
            let fireDate = Calendar.current.date(byAdding: .day, value: -days, to: validUntil)!
            guard fireDate > Date() else { continue }
            let content = UNMutableNotificationContent()
            content.title = String(localized: "Bank access expires soon")
            content.body = String(localized: "Open Tjugofemte and reconnect your bank within \(days) days to keep seeing new transactions.")
            var components = Calendar.current.dateComponents([.year, .month, .day], from: fireDate)
            components.hour = 9
            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: "consent-\(days)", content: content, trigger: trigger))
        }
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: daysBefore.map { "consent-\($0)" })
    }
}
