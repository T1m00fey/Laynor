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
}

private struct FirebasePayload: Encodable {
    let text: String
    let style: String
    let language: String
    let instruction: String?
}

private struct FirebaseTextResponse: Decodable { let text: String }
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
