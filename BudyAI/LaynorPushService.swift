import Foundation
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

enum LaynorPushService {
    private static let clientKey = "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39"
    private static let baseURL =
        "https://europe-west1-factorial-9c9f3.cloudfunctions.net"

    static func registerDevice(fcmToken: String, supportCode: String? = nil) async throws {
        try await post(
            path: "budyRegisterDevice",
            payload: RegisterDevicePayload(
                installationId: LaynorInstallation.identifier,
                fcmToken: fcmToken,
                locale: Locale.autoupdatingCurrent.identifier,
                timeZone: TimeZone.autoupdatingCurrent.identifier,
                supportCode: supportCode
            )
        )
    }

    static func unregisterSupportDevice() async throws {
        try await post(
            path: "budyUnregisterSupportDevice",
            payload: UnregisterSupportDevicePayload(
                installationId: LaynorInstallation.identifier
            )
        )
    }

#if canImport(FirebaseMessaging)
    static func registerSupportDevice(code: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            Messaging.messaging().token { token, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let token, !token.isEmpty else {
                    continuation.resume(throwing: PushServiceError.invalidResponse)
                    return
                }
                Task {
                    do {
                        try await registerDevice(fcmToken: token, supportCode: code)
                        continuation.resume()
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
#else
    static func registerSupportDevice(code: String) async throws {
        throw PushServiceError.invalidResponse
    }
#endif

    static func cancelReminder(id: UUID) async throws {
        try await post(
            path: "budyCancelReminder",
            payload: CancelReminderPayload(
                installationId: LaynorInstallation.identifier,
                reminderId: id.uuidString.lowercased()
            )
        )
    }

    static func createReminder(_ reminder: LaynorReminder) async throws {
        try await post(
            path: "budyCreateReminder",
            payload: CreateReminderPayload(
                installationId: LaynorInstallation.identifier,
                reminderId: reminder.id.uuidString.lowercased(),
                title: reminder.title,
                eventDate: ISO8601DateFormatter().string(
                    from: reminder.eventDate ?? reminder.fireDate
                ),
                notificationDate: ISO8601DateFormatter().string(
                    from: reminder.fireDate
                ),
                locale: LaynorLocalization.keyboardLanguageCode
            )
        )
    }

    static func reminders() async throws -> [LaynorReminder] {
        let response: ReminderListResponse = try await postForResponse(
            path: "budyListReminders",
            payload: ListRemindersPayload(
                installationId: LaynorInstallation.identifier
            )
        )
        return response.reminders.compactMap { item in
            guard let id = UUID(uuidString: item.id),
                  let eventDate = date(from: item.eventDate),
                  let notificationDate = date(from: item.notificationDate)
            else {
                return nil
            }
            return LaynorReminder(
                id: id,
                title: item.title,
                fireDate: notificationDate,
                eventDate: eventDate,
                createdAt: date(from: item.createdAt) ?? Date()
            )
        }
    }

    static func uploadPendingReminders() async {
        for reminder in LaynorReminderCenter.pendingServerReminders() {
            do {
                try await createReminder(reminder)
                LaynorReminderCenter.markServerQueued(reminder)
            } catch {
                // Keep it pending. A later app activation or token refresh
                // retries the same idempotent Firebase document.
                print("Reminder upload pending: \(error)")
            }
        }
    }

    private static func post<Payload: Encodable>(
        path: String,
        payload: Payload
    ) async throws {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw PushServiceError.invalidURL
        }

        let (_, response) = try await performRequest(url: url, payload: payload)
        guard (200..<300).contains(response.statusCode) else {
            throw PushServiceError.invalidResponse
        }
    }

    private static func postForResponse<Payload: Encodable, Response: Decodable>(
        path: String,
        payload: Payload
    ) async throws -> Response {
        guard let url = URL(string: "\(baseURL)/\(path)") else {
            throw PushServiceError.invalidURL
        }

        let (data, response) = try await performRequest(url: url, payload: payload)
        guard (200..<300).contains(response.statusCode),
              let decoded = try? JSONDecoder().decode(Response.self, from: data)
        else {
            throw PushServiceError.invalidResponse
        }
        return decoded
    }

    private static func performRequest<Payload: Encodable>(
        url: URL,
        payload: Payload
    ) async throws -> (Data, HTTPURLResponse) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw PushServiceError.invalidResponse
        }
        return (data, http)
    }

    private static func date(from value: String?) -> Date? {
        guard let value else { return nil }
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fractional.date(from: value)
            ?? ISO8601DateFormatter().date(from: value)
    }
}

private struct RegisterDevicePayload: Encodable {
    let installationId: String
    let fcmToken: String
    let locale: String
    let timeZone: String
    let supportCode: String?
}

private struct UnregisterSupportDevicePayload: Encodable {
    let installationId: String
}

private struct CancelReminderPayload: Encodable {
    let installationId: String
    let reminderId: String
}

private struct CreateReminderPayload: Encodable {
    let installationId: String
    let reminderId: String
    let title: String
    let eventDate: String
    let notificationDate: String
    let locale: String
}

private struct ListRemindersPayload: Encodable {
    let installationId: String
}

private struct ReminderListResponse: Decodable {
    let reminders: [ReminderListItem]
}

private struct ReminderListItem: Decodable {
    let id: String
    let title: String
    let eventDate: String
    let notificationDate: String
    let createdAt: String?
}

private enum PushServiceError: Error {
    case invalidURL
    case invalidResponse
}
