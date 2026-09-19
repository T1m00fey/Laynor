import Foundation
import UserNotifications

struct LaynorReminderDraft: Codable, Equatable, Sendable {
    let title: String
    let fireDate: Date
}

struct LaynorReminder: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let title: String
    /// Actual notification delivery time.
    let fireDate: Date
    /// Time of the event extracted from the user's text.
    let eventDate: Date?
    let createdAt: Date
}

enum LaynorReminderError: LocalizedError {
    case notificationsDenied
    case invalidDate
    case storageUnavailable

    var errorDescription: String? {
        switch self {
        case .notificationsDenied:
            "keyboard.reminder.notifications_denied".localizedString()
        case .invalidDate:
            "keyboard.reminder.invalid_date".localizedString()
        case .storageUnavailable:
            "keyboard.reminder.storage_failed".localizedString()
        }
    }
}

enum LaynorReminderCenter {
    private static let appGroupId = "group.Tim.BudyAI"
    private static let remindersKey = "laynorScheduledReminders"
    private static let remindersFileName = "laynor-reminders.json"
    private static let serverQueuedReminderIdsKey = "laynorServerQueuedReminderIds"
    static let leadTimeKey = "reminderLeadMinutes"
    static let defaultLeadMinutes = 15

    static var leadMinutes: Int {
        let defaults = UserDefaults(suiteName: appGroupId)
        guard defaults?.object(forKey: leadTimeKey) != nil else {
            return defaultLeadMinutes
        }
        return max(0, defaults?.integer(forKey: leadTimeKey) ?? defaultLeadMinutes)
    }

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    static func requestAuthorizationIfNeeded(allowSystemPrompt: Bool = true) async throws {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus

        switch status {
        case .authorized, .provisional, .ephemeral:
            return
        case .notDetermined:
            guard allowSystemPrompt else {
                throw LaynorReminderError.notificationsDenied
            }
            let granted = try await center.requestAuthorization(options: [.alert, .sound])
            guard granted else { throw LaynorReminderError.notificationsDenied }
        case .denied:
            throw LaynorReminderError.notificationsDenied
        @unknown default:
            throw LaynorReminderError.notificationsDenied
        }
    }

    @discardableResult
    static func schedule(
        _ draft: LaynorReminderDraft,
        allowAuthorizationPrompt: Bool = true
    ) async throws -> LaynorReminder {
        let reminder = try stage(draft)

        do {
            try await requestAuthorizationIfNeeded(
                allowSystemPrompt: allowAuthorizationPrompt
            )
            try await addNotification(for: reminder)
            return reminder
        } catch {
            // The reminder remains staged in the shared store and the main
            // app can finish scheduling it the next time it becomes active.
            throw error
        }
    }

    /// Persists a reminder without touching UserNotifications. This is the
    /// only operation performed by the keyboard extension.
    @discardableResult
    static func stage(_ draft: LaynorReminderDraft) throws -> LaynorReminder {
        let reminder = try prepare(draft)
        try persist(reminder)
        return reminder
    }

    /// Creates a server payload without performing any App Group I/O.
    static func prepare(_ draft: LaynorReminderDraft) throws -> LaynorReminder {
        guard draft.fireDate.timeIntervalSinceNow >= 5 else {
            throw LaynorReminderError.invalidDate
        }

        let preferredFireDate = draft.fireDate.addingTimeInterval(
            -TimeInterval(leadMinutes * 60)
        )
        let notificationDate = max(
            preferredFireDate,
            Date().addingTimeInterval(5)
        )
        let reminder = LaynorReminder(
            id: UUID(),
            title: draft.title,
            fireDate: notificationDate,
            eventDate: draft.fireDate,
            createdAt: Date()
        )
        return reminder
    }

    /// Schedules every staged reminder that does not yet have a pending
    /// system notification. Call this only from the containing application.
    static func synchronizePendingNotifications() async {
        let center = UNUserNotificationCenter.current()
        let status = await center.notificationSettings().authorizationStatus
        guard status == .authorized || status == .provisional || status == .ephemeral else {
            return
        }

        let pendingIdentifiers = await pendingNotificationIdentifiers(center)
        let now = Date()

        for storedReminder in scheduledReminders()
        where !pendingIdentifiers.contains(storedReminder.id.uuidString) {
            var reminder = storedReminder

            if reminder.fireDate <= now,
               (reminder.eventDate ?? reminder.fireDate) > now {
                reminder = LaynorReminder(
                    id: reminder.id,
                    title: reminder.title,
                    fireDate: now.addingTimeInterval(5),
                    eventDate: reminder.eventDate,
                    createdAt: reminder.createdAt
                )
                try? persist(reminder)
            }

            try? await addNotification(for: reminder)
        }
    }

    private static func addNotification(for reminder: LaynorReminder) async throws {
        let content = UNMutableNotificationContent()
        content.title = "reminder.notification.title".localizedString()
        content.body = reminder.title
        content.sound = .default
        content.interruptionLevel = .timeSensitive
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
    }

    private static func pendingNotificationIdentifiers(
        _ center: UNUserNotificationCenter
    ) async -> Set<String> {
        await withCheckedContinuation { continuation in
            center.getPendingNotificationRequests { requests in
                continuation.resume(
                    returning: Set(requests.map(\.identifier))
                )
            }
        }
    }

    static func scheduledReminders() -> [LaynorReminder] {
        let fileData = remindersFileURL().flatMap {
            try? Data(contentsOf: $0)
        }
        let legacyData = UserDefaults(suiteName: appGroupId)?
            .data(forKey: remindersKey)
        guard let data = fileData ?? legacyData,
              let reminders = try? JSONDecoder().decode(
                [LaynorReminder].self,
                from: data
              ) else {
            return []
        }

        let now = Date()
        return reminders
            // Keep the item visible until the event itself, even when its
            // notification has already fired because of the lead time.
            .filter { ($0.eventDate ?? $0.fireDate) > now }
            .sorted {
                ($0.eventDate ?? $0.fireDate) < ($1.eventDate ?? $1.fireDate)
            }
    }

    static func cancel(_ reminder: LaynorReminder) {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [reminder.id.uuidString])
        try? save(scheduledReminders().filter { $0.id != reminder.id })
        removeServerQueueMarker(for: reminder)
    }

    static func removeStaged(_ reminder: LaynorReminder) {
        try? save(scheduledReminders().filter { $0.id != reminder.id })
        removeServerQueueMarker(for: reminder)
    }

    /// Reminders are first written to the App Group and then uploaded to
    /// Firebase. Keeping the upload state separate makes the keyboard action
    /// instant and lets the containing app retry interrupted network calls.
    static func pendingServerReminders() -> [LaynorReminder] {
        let queuedIds = serverQueuedReminderIds()
        return scheduledReminders().filter {
            !queuedIds.contains($0.id.uuidString.lowercased())
        }
    }

    static func markServerQueued(_ reminder: LaynorReminder) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        var ids = serverQueuedReminderIds()
        ids.insert(reminder.id.uuidString.lowercased())
        defaults.set(Array(ids), forKey: serverQueuedReminderIdsKey)
    }

    private static func persist(_ reminder: LaynorReminder) throws {
        var reminders = scheduledReminders()
        reminders.removeAll { $0.id == reminder.id }
        reminders.append(reminder)
        try save(reminders)
    }

    private static func save(_ reminders: [LaynorReminder]) throws {
        guard let url = remindersFileURL(),
              let data = try? JSONEncoder().encode(reminders) else {
            throw LaynorReminderError.storageUnavailable
        }
        do {
            try data.write(to: url, options: .atomic)
            // Remove the old preferences payload after a successful migration.
            UserDefaults(suiteName: appGroupId)?
                .removeObject(forKey: remindersKey)
        } catch {
            throw LaynorReminderError.storageUnavailable
        }
    }

    private static func remindersFileURL() -> URL? {
        FileManager.default
            .containerURL(
                forSecurityApplicationGroupIdentifier: appGroupId
            )?
            .appendingPathComponent(remindersFileName, isDirectory: false)
    }

    private static func serverQueuedReminderIds() -> Set<String> {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return []
        }
        return Set(
            defaults.stringArray(forKey: serverQueuedReminderIdsKey) ?? []
        )
    }

    private static func removeServerQueueMarker(for reminder: LaynorReminder) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        var ids = serverQueuedReminderIds()
        ids.remove(reminder.id.uuidString.lowercased())
        defaults.set(Array(ids), forKey: serverQueuedReminderIdsKey)
    }
}
