import Foundation
import SwiftUI
import UIKit

extension View {
    func dismissKeyboardOnOutsideTap() -> some View {
        background(KeyboardDismissTapInstaller())
    }
}

private struct KeyboardDismissTapInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.install(in: view.window)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.install(in: uiView.window)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func install(in window: UIWindow?) {
            guard let window else { return }
            guard installedWindow !== window else { return }
            uninstall()

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)
            installedWindow = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer {
                installedWindow?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            installedWindow = nil
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextField || current is UITextView {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        @objc private func dismissKeyboard() {
            installedWindow?.endEditing(true)
        }
    }
}

enum BudyTheme {
    static let background = adaptive(
        light: UIColor(red: 0.968, green: 0.971, blue: 0.978, alpha: 1),
        dark: UIColor(red: 0.045, green: 0.050, blue: 0.064, alpha: 1)
    )
    static let surface = adaptive(
        light: .white,
        dark: UIColor(red: 0.095, green: 0.102, blue: 0.124, alpha: 1)
    )
    static let field = adaptive(
        light: UIColor(red: 0.925, green: 0.931, blue: 0.942, alpha: 1),
        dark: UIColor(red: 0.145, green: 0.153, blue: 0.180, alpha: 1)
    )
    static let border = adaptive(
        light: UIColor(white: 0, alpha: 0.09),
        dark: UIColor(white: 1, alpha: 0.10)
    )
    static let ink = adaptive(
        light: UIColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1),
        dark: UIColor(red: 0.945, green: 0.952, blue: 0.975, alpha: 1)
    )
    static let secondaryInk = adaptive(
        light: UIColor(red: 0.37, green: 0.39, blue: 0.43, alpha: 1),
        dark: UIColor(red: 0.65, green: 0.67, blue: 0.72, alpha: 1)
    )
    static let accent = adaptive(
        light: UIColor(red: 0.40, green: 0.46, blue: 0.91, alpha: 1),
        dark: UIColor(red: 0.48, green: 0.57, blue: 1.00, alpha: 1)
    )
    static let accentDark = adaptive(
        light: UIColor(red: 0.30, green: 0.35, blue: 0.78, alpha: 1),
        dark: UIColor(red: 0.58, green: 0.65, blue: 1.00, alpha: 1)
    )
    static let accentSoft = adaptive(
        light: UIColor(red: 0.94, green: 0.945, blue: 0.995, alpha: 1),
        dark: UIColor(red: 0.115, green: 0.130, blue: 0.235, alpha: 1)
    )
    static let primaryAction = adaptive(
        light: UIColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1),
        dark: UIColor(red: 0.945, green: 0.952, blue: 0.975, alpha: 1)
    )
    static let onPrimaryAction = adaptive(
        light: .white,
        dark: UIColor(red: 0.055, green: 0.063, blue: 0.078, alpha: 1)
    )
    static let brandSurface = Color(red: 0.055, green: 0.063, blue: 0.078)

    private static func adaptive(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum RewriteStyle: String, CaseIterable, Identifiable, Codable {
    case rewrite
    case correct
    case concise
    case professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewrite: "mode.rewrite.title".localizedString()
        case .correct: "mode.correct.title".localizedString()
        case .concise: "mode.concise.title".localizedString()
        case .professional: "mode.professional.title".localizedString()
        }
    }

    var icon: String {
        switch self {
        case .rewrite: "wand.and.stars"
        case .correct: "checkmark.circle.fill"
        case .concise: "scissors"
        case .professional: "briefcase.fill"
        }
    }

}

enum BudyConfiguration {
    static let firebaseURL = "https://europe-west1-factorial-9c9f3.cloudfunctions.net/budyRewrite"
    static let feedbackURL = "https://europe-west1-factorial-9c9f3.cloudfunctions.net/budyFeedback"
    static let clientKey = "8e20f7353e04590aa7e550840116ac322eaa30bda8e28c39"
}

enum FeedbackType: String, CaseIterable, Identifiable, Codable {
    case suggestion
    case issue
    case review

    var id: String { rawValue }

    var title: String {
        "feedback.type.\(rawValue)".localizedString()
    }

    var icon: String {
        switch self {
        case .suggestion: "lightbulb.fill"
        case .issue: "exclamationmark.triangle.fill"
        case .review: "heart.fill"
        }
    }
}

struct FeedbackService {
    func submit(type: FeedbackType, message: String, contact: String) async throws {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else {
            throw FeedbackError.invalidURL
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let payload = FeedbackRequest(
            type: type.rawValue,
            message: message,
            contact: contact.isEmpty ? nil : contact,
            locale: LaynorLocalization.appLanguageCode,
            appVersion: version
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(FeedbackErrorResponse.self, from: data)
            throw FeedbackError.api(backendError?.error ?? "feedback.error.generic".localizedString())
        }
    }
}

private struct FeedbackRequest: Encodable {
    let type: String
    let message: String
    let contact: String?
    let locale: String
    let appVersion: String
}

private struct FeedbackErrorResponse: Decodable { let error: String }

enum FeedbackError: LocalizedError {
    case invalidURL
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL: "error.firebase.invalid_url".localizedString()
        case .invalidResponse: "error.firebase.invalid_response".localizedString()
        case .api(let message): message
        }
    }
}

struct RewriteService {
    func rewrite(_ text: String, style: RewriteStyle) async throws -> String {
        guard let url = URL(string: BudyConfiguration.firebaseURL) else {
            throw RewriteError.invalidFirebaseURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 25
        request.httpBody = try JSONEncoder().encode(FirebaseRewriteRequest(text: text, style: style.rawValue, language: "auto"))
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(FirebaseRewriteResponse.self, from: data)
        let rewritten = decoded.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rewritten.isEmpty else { throw RewriteError.invalidResponse }
        return rewritten
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw RewriteError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(FirebaseErrorResponse.self, from: data)
            let fallback = String(
                format: "error.firebase.status".localizedString(),
                http.statusCode
            )
            throw RewriteError.api(backendError?.error ?? fallback)
        }
    }
}

private struct FirebaseRewriteRequest: Encodable {
    let text: String
    let style: String
    let language: String
}

private struct FirebaseRewriteResponse: Decodable { let text: String }
private struct FirebaseErrorResponse: Decodable { let error: String }

enum RewriteError: LocalizedError {
    case invalidFirebaseURL
    case invalidResponse
    case api(String)

    var errorDescription: String? {
        switch self {
        case .invalidFirebaseURL:
            "error.firebase.invalid_url".localizedString()
        case .invalidResponse:
            "error.firebase.invalid_response".localizedString()
        case .api(let message): message
        }
    }
}
