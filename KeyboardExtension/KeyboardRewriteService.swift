import Foundation

struct KeyboardRewriteService {
    private let defaultURL = "https://europe-west1-factorial-9c9f3.cloudfunctions.net/budyRewrite"
    private let clientKey = "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39"

    func rewrite(_ text: String, style: KeyboardRewriteStyle) async throws -> String {
        try await rewrite(text, style: style.rawValue, instruction: nil)
    }

    func rewrite(_ text: String, instruction: String) async throws -> String {
        try await rewrite(text, style: "custom", instruction: instruction)
    }

    func parseReminder(_ text: String) async throws -> LaynorReminderDraft {
        guard let url = URL(string: defaultURL) else {
            throw KeyboardServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            FirebaseReminderPayload(
                text: text,
                style: "reminder",
                language: LaynorLocalization.keyboardLanguageCode,
                currentDate: ISO8601DateFormatter().string(from: Date()),
                timeZone: TimeZone.autoupdatingCurrent.identifier
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw KeyboardServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(FirebaseErrorResponse.self, from: data)
            if backendError?.error == "REMINDER_DATE_REQUIRED" {
                throw KeyboardServiceError.api(
                    "keyboard.reminder.date_required".localizedString()
                )
            }
            throw KeyboardServiceError.api(
                backendError?.error ?? "Firebase error: \(http.statusCode)"
            )
        }

        let decoded = try JSONDecoder().decode(FirebaseReminderResponse.self, from: data)
        guard
            !decoded.reminder.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            let fireDate = Self.reminderDateFormatter.date(from: decoded.reminder.fireDate)
                ?? Self.fallbackReminderDateFormatter.date(from: decoded.reminder.fireDate)
        else {
            throw KeyboardServiceError.invalidResponse
        }

        return LaynorReminderDraft(
            title: decoded.reminder.title,
            fireDate: fireDate
        )
    }

    func createServerReminder(
        _ reminder: LaynorReminder,
        installationId: String = LaynorInstallation.identifier
    ) async throws {
        let request = try makeCreateReminderRequest(
            reminder,
            installationId: installationId
        )
        let (data, response) = try await URLSession.shared.data(for: request)
        try validateCreateReminderResponse(data: data, response: response)
    }

    /// Completion-handler variant for the keyboard confirmation action.
    /// Avoiding an unstructured Swift concurrency task here keeps the
    /// extension's confirmation path as small as a regular URLSession call.
    func createServerReminder(
        _ reminder: LaynorReminder,
        installationId: String,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let request: URLRequest
        do {
            request = try makeCreateReminderRequest(
                reminder,
                installationId: installationId
            )
        } catch {
            completion(.failure(error))
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                completion(.failure(error))
                return
            }
            guard let response else {
                completion(.failure(KeyboardServiceError.invalidResponse))
                return
            }

            do {
                try validateCreateReminderResponse(
                    data: data ?? Data(),
                    response: response
                )
                completion(.success(()))
            } catch {
                completion(.failure(error))
            }
        }
        .resume()
    }

    /// Starts the upload without tying the keyboard UI lifetime to a network
    /// request. The backend write is idempotent by reminder ID, so the main
    /// app can safely retry it later.
    func enqueueServerReminder(
        _ reminder: LaynorReminder,
        installationId: String = LaynorInstallation.identifier
    ) {
        guard let request = try? makeCreateReminderRequest(
            reminder,
            installationId: installationId
        ) else {
            return
        }
        URLSession.shared.dataTask(with: request).resume()
    }

    private func makeCreateReminderRequest(
        _ reminder: LaynorReminder,
        installationId: String
    ) throws -> URLRequest {
        let endpoint = defaultURL.replacingOccurrences(
            of: "/budyRewrite",
            with: "/budyCreateReminder"
        )
        guard let url = URL(string: endpoint) else {
            throw KeyboardServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(
            FirebaseCreateReminderPayload(
                installationId: installationId,
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
        return request
    }

    private func validateCreateReminderResponse(
        data: Data,
        response: URLResponse
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw KeyboardServiceError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(FirebaseErrorResponse.self, from: data)
            if backendError?.error == "DEVICE_NOT_REGISTERED" {
                throw KeyboardServiceError.api(
                    "keyboard.reminder.device_not_registered".localizedString()
                )
            }
            throw KeyboardServiceError.api(
                backendError?.error ?? "Firebase error: \(http.statusCode)"
            )
        }
    }

    private func rewrite(
        _ text: String,
        style: String,
        instruction: String?
    ) async throws -> String {
        guard let url = URL(string: defaultURL) else {
            throw KeyboardServiceError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(
            FirebasePayload(
                text: text,
                style: style,
                language: "auto",
                instruction: instruction
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw KeyboardServiceError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(FirebaseErrorResponse.self, from: data)
            throw KeyboardServiceError.api(backendError?.error ?? "Firebase error: \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(FirebaseTextResponse.self, from: data)
        let rewritten = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewritten.isEmpty else { throw KeyboardServiceError.invalidResponse }
        return rewritten
    }

    private static let reminderDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let fallbackReminderDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

private struct FirebasePayload: Encodable {
    let text: String
    let style: String
    let language: String
    let instruction: String?
}

private struct FirebaseTextResponse: Decodable { let text: String }
private struct FirebaseReminderPayload: Encodable {
    let text: String
    let style: String
    let language: String
    let currentDate: String
    let timeZone: String
}
private struct FirebaseCreateReminderPayload: Encodable {
    let installationId: String
    let reminderId: String
    let title: String
    let eventDate: String
    let notificationDate: String
    let locale: String
}
private struct FirebaseReminderResponse: Decodable {
    let reminder: FirebaseReminder
}
private struct FirebaseReminder: Decodable {
    let title: String
    let fireDate: String
}
private struct FirebaseErrorResponse: Decodable { let error: String }

private enum KeyboardServiceError: LocalizedError {
    case invalidURL
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "keyboard.error.firebase_url".localizedString()
        case .invalidResponse: "keyboard.error.firebase_response".localizedString()
        case .api(let message): message
        }
    }
}
