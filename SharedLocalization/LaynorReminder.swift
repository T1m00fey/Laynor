import Foundation
import UserNotifications

struct LaynorReminderDraft: Codable, Equatable, Sendable {
    let title: String
    let fireDate: Date
}

struct LaynorReminder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    let fireDate: Date
    let createdAt: Date
}

enum LaynorReminderError: LocalizedError {
    case notificationsDenied
    case invalidDate

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            "keyboard.reminder.notifications_denied".localizedString()
        case .invalidDate:
            "keyboard.reminder.invalid_date".localizedString()
        }
    }
}

enum LaynorReminderCenter {
    private static let appGroupId = "group.Tim.BudyAI"
    private static let remindersKey = "laynorScheduledReminders"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorizationIfNeeded() async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        switch status {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { throw LaynorReminderError.notificationsDenied }
        case .denied:
            throw LaynorReminderError.notificationsDenied
        @unknown default:
            throw LaynorReminderError.notificationsDenied
        }
    }

    @discardableResult
    static func schedule(_ draft: LaynorReminderDraft) async throws -> LaynorReminder {
        guard draft.fireDate.timeIntervalSinceNow >= 5 else {
            throw LaynorReminderError.invalidDate
        }

        try await requestAuthorizationIfNeeded()

        let reminder = LaynorReminder(
            id: UUID(),
            title: draft.title,
            fireDate: draft.fireDate,
            createdAt: Date()
        )

        let content = UNMutableNotificationContent()
        content.title = "reminder.notification.title".localizedString()
        content.body = reminder.title
        content.sound = .default
        content.userInfo = ["laynorReminderId": reminder.id.uuidString]

        let components = Calendar.autoupdatingCurrent.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: reminder.fireDate
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: reminder.id.uuidString,
            content: content,
            trigger: trigger
        )

        try await UNUserNotificationCenter.current().add(request)
        persist(reminder)
        return reminder
    }

    static func scheduledReminders() -> [LaynorReminder] {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let data = defaults.data(forKey: remindersKey),
            let reminders = try? JSONDecoder().decode([LaynorReminder].self, from: data)
        else {
            return []
        }

        return reminders
            .filter { $0.fireDate > Date() }
            .sorted { $0.fireDate < $1.fireDate }
    }

    static func cancel(_ reminder: LaynorReminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
        save(scheduledReminders().filter { $0.id != reminder.id })
    }

    private static func persist(_ reminder: LaynorReminder) {
        var reminders = scheduledReminders()
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        save(reminders)
    }

    private static func save(_ reminders: [LaynorReminder]) {
        guard
            let defaults = UserDefaults(suiteName: appGroupId),
            let data = try? JSONEncoder().encode(reminders)
        else {
            return
        }
        defaults.set(data, forKey: remindersKey)
    }
}
