import SwiftUI
import Security

enum SupportAccessSession {
    private static let service = "com.laynor.support.access"
    private static let account = "operator-code"

    static var code: String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func grant(code: String) {
        let data = Data(code.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        SecItemAdd(query.merging([kSecValueData as String: data]) { _, new in new } as CFDictionary, nil)
    }

    static func revoke() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

private struct SupportAccessResponse: Decodable {
    let ok: Bool
    let role: String?
}

private struct SupportAccessRequest: Encodable {
    let action: String
    let code: String
}

private enum SupportAccessError: LocalizedError {
    case invalidURL
    case invalidResponse
    case denied

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "support.access.error.url".localizedString()
        case .invalidResponse: return "support.access.error.response".localizedString()
        case .denied: return "support.access.error.denied".localizedString()
        }
    }
}

private struct SupportAccessService {
    func authenticate(code: String) async throws -> String {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else { throw SupportAccessError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(SupportAccessRequest(action: "support_auth", code: code))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SupportAccessError.invalidResponse }
        guard http.statusCode == 200 else {
            if http.statusCode == 400 || http.statusCode == 403 { throw SupportAccessError.denied }
            throw SupportAccessError.invalidResponse
        }
        let value = try JSONDecoder().decode(SupportAccessResponse.self, from: data)
        guard value.ok else { throw SupportAccessError.denied }
        return value.role ?? "support"
    }
}

struct SupportAccessView: View {
    @AppStorage("laynor.support.access.granted") private var accessGranted = false
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var role = "support"
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showsError = false
    @State private var showsSuccess = false

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                if accessGranted {
                    Label("support.access.active".localizedString(), systemImage: "checkmark.shield.fill")
                        .font(.system(size: 19, weight: .bold, design: .rounded))
                        .foregroundStyle(Color(red: 0.20, green: 0.62, blue: 0.37))
                    Text("support.access.role".localizedString() + ": " + role)
                        .foregroundStyle(BudyTheme.secondaryInk)
                    Button("support.access.logout".localizedString()) {
                        Task {
                            try? await LaynorPushService.unregisterSupportDevice()
                            accessGranted = false
                            SupportAccessSession.revoke()
                            dismiss()
                        }
                    }
                } else {
                    Text("support.access.subtitle".localizedString())
                        .font(.system(size: 14))
                        .foregroundStyle(BudyTheme.secondaryInk)
                    SecureField("support.access.placeholder".localizedString(), text: $code)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
                        .font(.system(size: 22, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .frame(height: 52)
                        .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .onChange(of: code) { _, value in code = String(value.filter { $0.isNumber }.prefix(12)) }
                    Button { authenticate() } label: {
                        HStack {
                            if isLoading { ProgressView().tint(BudyTheme.onPrimaryAction) }
                            Text("support.access.login".localizedString())
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(BudyTheme.onPrimaryAction)
                        .padding(.horizontal, 17)
                        .frame(height: 50)
                        .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(code.count < 4 || isLoading)
                    .opacity(code.count < 4 || isLoading ? 0.5 : 1)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("support.access.title".localizedString())
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(BudyTheme.accentDark)
        .alert("support.access.error.title".localizedString(), isPresented: $showsError) {
            Button("common.ok".localizedString(), role: .cancel) {}
        } message: { Text(errorMessage) }
        .alert("support.access.success.title".localizedString(), isPresented: $showsSuccess) {
            Button("common.continue".localizedString()) {
                openSupportInbox()
            }
        } message: {
            Text("support.access.success.subtitle".localizedString())
        }
    }

    private func authenticate() {
        isLoading = true
        Task {
            do {
                role = try await SupportAccessService().authenticate(code: code)
                SupportAccessSession.grant(code: code)
                try? await LaynorPushService.registerSupportDevice(code: code)
                accessGranted = true
                showsSuccess = true
            }
            catch { errorMessage = error.localizedDescription; showsError = true }
            isLoading = false
        }
    }

    private func openSupportInbox() {
        NotificationCenter.default.post(name: .laynorOpenSupportOperator, object: nil)
        dismiss()
    }
}
