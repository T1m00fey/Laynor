import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss

    @AppStorage(
        "keyboardHapticsEnabled",
        store: UserDefaults(suiteName: "group.Tim.BudyAI")
    ) private var isKeyboardHapticsEnabled = true

    let onShowSetup: () -> Void

    @State private var connectionState: ConnectionState = .idle
    @State private var isFeedbackPresented = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    keyboardCard
                    serviceCard
                    feedbackCard
                    privacyCard
                    aboutCard
                    ReadboxCredit()
                }
                .padding(18)
                .padding(.bottom, 20)
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("common.settings".localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localizedString()) { dismiss() }
                        .fontWeight(.semibold)
                }
            }
        }
        .dismissKeyboardOnOutsideTap()
        .tint(BudyTheme.accentDark)
        .sheet(isPresented: $isFeedbackPresented) {
            FeedbackView()
        }
    }

    private var keyboardCard: some View {
        SettingsSection(title: "settings.keyboard.section".localizedString()) {
            VStack(spacing: 0) {
                SettingsRow(
                    icon: "keyboard.fill",
                    color: BudyTheme.accentDark,
                    title: "settings.keyboard.setup.title".localizedString(),
                    subtitle: "settings.keyboard.setup.subtitle".localizedString(),
                    trailingIcon: "chevron.right"
                ) {
                    onShowSetup()
                }

                Divider().padding(.leading, 54)

                SettingsToggleRow(
                    icon: "iphone.radiowaves.left.and.right",
                    color: BudyTheme.accentDark,
                    title: "settings.keyboard.haptics.title".localizedString(),
                    subtitle: "settings.keyboard.haptics.subtitle".localizedString(),
                    isOn: $isKeyboardHapticsEnabled
                )

                Divider().padding(.leading, 54)

                SettingsRow(
                    icon: "gearshape.fill",
                    color: .gray,
                    title: "settings.keyboard.iphone.title".localizedString(),
                    subtitle: "settings.keyboard.iphone.subtitle".localizedString(),
                    trailingIcon: "arrow.up.right"
                ) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
    }

    private var serviceCard: some View {
        SettingsSection(title: "settings.service.section".localizedString()) {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(statusColor.opacity(0.13))
                    Image(systemName: statusIcon)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(statusColor)
                }
                .frame(width: 46, height: 46)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.system(size: 15, weight: .bold))
                    Text(statusSubtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(BudyTheme.secondaryInk)
                }

                Spacer()

                Button(action: checkConnection) {
                    if connectionState == .checking {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .frame(width: 38, height: 38)
                .background(BudyTheme.field, in: Circle())
                .disabled(connectionState == .checking)
                .accessibilityLabel("settings.service.check".localizedString())
            }
            .padding(16)
        }
    }

    private var privacyCard: some View {
        SettingsSection(title: "settings.privacy.section".localizedString()) {
            VStack(alignment: .leading, spacing: 13) {
                Label("settings.privacy.title".localizedString(), systemImage: "lock.shield.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BudyTheme.ink)

                Text("settings.privacy.description".localizedString())
                    .font(.system(size: 13))
                    .foregroundStyle(BudyTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(17)
        }
    }

    private var feedbackCard: some View {
        SettingsSection(title: "settings.feedback.section".localizedString()) {
            SettingsRow(
                icon: "bubble.left.and.text.bubble.right.fill",
                color: BudyTheme.accentDark,
                title: "settings.feedback.title".localizedString(),
                subtitle: "settings.feedback.subtitle".localizedString(),
                trailingIcon: "chevron.right"
            ) {
                isFeedbackPresented = true
            }
        }
    }

    private var aboutCard: some View {
        SettingsSection(title: "settings.about.section".localizedString()) {
            VStack(spacing: 0) {
                InfoRow(title: "settings.about.version".localizedString(), value: appVersion)
                Divider().padding(.leading, 16)
//                InfoRow(title: "settings.about.languages".localizedString(), value: "settings.about.languages_value".localizedString())
//                Divider().padding(.leading, 16)
                InfoRow(title: "settings.about.processing".localizedString(), value: "settings.about.processing_value".localizedString())
            }
        }
    }

    private var statusColor: Color {
        switch connectionState {
        case .failed: BudyTheme.ink
        case .connected: BudyTheme.accentDark
        case .idle, .checking: BudyTheme.ink
        }
    }

    private var statusIcon: String {
        switch connectionState {
        case .failed: "exclamationmark"
        case .connected: "checkmark"
        case .idle, .checking: "sparkles"
        }
    }

    private var statusTitle: String {
        switch connectionState {
        case .idle: "settings.status.idle.title".localizedString()
        case .checking: "settings.status.checking.title".localizedString()
        case .connected: "settings.status.connected.title".localizedString()
        case .failed: "settings.status.failed.title".localizedString()
        }
    }

    private var statusSubtitle: String {
        switch connectionState {
        case .idle: "settings.status.idle.subtitle".localizedString()
        case .checking: "settings.status.checking.subtitle".localizedString()
        case .connected: "settings.status.connected.subtitle".localizedString()
        case .failed: "settings.status.failed.subtitle".localizedString()
        }
    }

    private var appVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func checkConnection() {
        connectionState = .checking

        Task {
            do {
                guard let url = URL(string: BudyConfiguration.firebaseURL) else {
                    throw URLError(.badURL)
                }
                var request = URLRequest(url: url)
                request.httpMethod = "GET"
                request.timeoutInterval = 10
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode < 500,
                      http.statusCode != 404 else {
                    throw URLError(.badServerResponse)
                }
                connectionState = .connected
            } catch {
                connectionState = .failed
            }
        }
    }
}

private struct SettingsSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(BudyTheme.secondaryInk)
                .padding(.leading, 4)

            content
                .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(BudyTheme.border)
                }
        }
    }
}

private struct SettingsRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    let trailingIcon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(BudyTheme.secondaryInk)
                }

                Spacer()

                Image(systemName: trailingIcon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BudyTheme.secondaryInk.opacity(0.65))
            }
            .foregroundStyle(BudyTheme.ink)
            .padding(.horizontal, 14)
            .frame(minHeight: 62)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProductSettingsPressStyle())
    }
}

private struct SettingsToggleRow: View {
    let icon: String
    let color: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(color, in: RoundedRectangle(cornerRadius: 10, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(BudyTheme.secondaryInk)
                }
            }
        }
        .tint(BudyTheme.accentDark)
        .foregroundStyle(BudyTheme.ink)
        .padding(.horizontal, 14)
        .frame(minHeight: 62)
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 14))
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(BudyTheme.secondaryInk)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

private struct ProductSettingsPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? BudyTheme.field.opacity(0.7) : .clear)
    }
}

private enum ConnectionState {
    case idle
    case checking
    case connected
    case failed
}

struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var selectedType: FeedbackType = .suggestion
    @State private var message = ""
    @State private var contact = ""
    @State private var submissionState: FeedbackSubmissionState = .idle
    @State private var errorMessage = ""
    @State private var showsError = false
    @FocusState private var focusedField: FeedbackField?

    private let messageLimit = 2_000
    private let contactLimit = 200

    var body: some View {
        NavigationStack {
            Group {
                if submissionState == .sent {
                    successView
                } else {
                    formView
                }
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("feedback.title".localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localizedString()) { dismiss() }
                        .disabled(submissionState == .sending)
                }
            }
        }
        .tint(BudyTheme.accentDark)
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(submissionState == .sending)
        .alert("feedback.error.title".localizedString(), isPresented: $showsError) {
            Button("common.ok".localizedString(), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var formView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("feedback.heading".localizedString())
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(BudyTheme.ink)
                    Text("feedback.subtitle".localizedString())
                        .font(.system(size: 15))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                feedbackTypePicker

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("feedback.message.title".localizedString())

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("feedback.message.placeholder".localizedString())
                                .font(.system(size: 16))
                                .foregroundStyle(BudyTheme.secondaryInk.opacity(0.75))
                                .padding(.horizontal, 16)
                                .padding(.vertical, 15)
                                .allowsHitTesting(false)
                        }

                        TextEditor(text: $message)
                            .font(.system(size: 16))
                            .foregroundStyle(BudyTheme.ink)
                            .scrollContentBackground(.hidden)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .frame(minHeight: 150)
                            .focused($focusedField, equals: .message)
                    }
                    .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(focusedField == .message ? BudyTheme.accentDark.opacity(0.8) : BudyTheme.border, lineWidth: focusedField == .message ? 1.5 : 1)
                    }

                    Text("\(message.count)/\(messageLimit)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }

                VStack(alignment: .leading, spacing: 8) {
                    fieldLabel("feedback.contact.title".localizedString())
                    TextField("feedback.contact.placeholder".localizedString(), text: $contact)
                        .focused($focusedField, equals: .contact)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.emailAddress)
                        .font(.system(size: 15))
                        .padding(.horizontal, 16)
                        .frame(height: 52)
                        .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(BudyTheme.border)
                        }
                }

                Label("feedback.privacy".localizedString(), systemImage: "lock.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(BudyTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                Button(action: submit) {
                    HStack(spacing: 9) {
                        if submissionState == .sending {
                            ProgressView()
                                .tint(BudyTheme.onPrimaryAction)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Text(submissionState == .sending ? "feedback.sending".localizedString() : "feedback.send".localizedString())
                            .font(.system(size: 16, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(BudyTheme.onPrimaryAction)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.45)
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .onChange(of: message) { _, value in
            if value.count > messageLimit { message = String(value.prefix(messageLimit)) }
        }
        .onChange(of: contact) { _, value in
            if value.count > contactLimit { contact = String(value.prefix(contactLimit)) }
        }
    }

    private var feedbackTypePicker: some View {
        HStack(spacing: 8) {
            ForEach(FeedbackType.allCases) { type in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selectedType = type }
                } label: {
                    VStack(spacing: 7) {
                        Image(systemName: type.icon)
                            .font(.system(size: 16, weight: .semibold))
                        Text(type.title)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedType == type ? BudyTheme.accentDark : BudyTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(selectedType == type ? BudyTheme.accentSoft : BudyTheme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 17, style: .continuous)
                            .stroke(selectedType == type ? BudyTheme.accentDark.opacity(0.45) : BudyTheme.border)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var successView: some View {
        VStack(spacing: 18) {
            Spacer()
            ZStack {
                Circle()
                    .fill(BudyTheme.accentSoft)
                    .frame(width: 92, height: 92)
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .transition(.scale.combined(with: .opacity))

            Text("feedback.success.title".localizedString())
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.ink)
            Text("feedback.success.subtitle".localizedString())
                .font(.system(size: 15))
                .foregroundStyle(BudyTheme.secondaryInk)
                .multilineTextAlignment(.center)

            Spacer()

            Button("common.done".localizedString()) { dismiss() }
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.onPrimaryAction)
                .frame(maxWidth: .infinity)
                .frame(height: 56)
                .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(24)
    }

    private func fieldLabel(_ title: String) -> some View {
        Text(title.uppercased())
            .font(.system(size: 11, weight: .bold))
            .tracking(0.7)
            .foregroundStyle(BudyTheme.secondaryInk)
    }

    private var canSubmit: Bool {
        message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
            && submissionState != .sending
    }

    private func submit() {
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanContact = contact.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanMessage.count >= 3 else { return }

        submissionState = .sending
        focusedField = nil
        Task {
            do {
                try await FeedbackService().submit(
                    type: selectedType,
                    message: cleanMessage,
                    contact: cleanContact
                )
                withAnimation(.spring(response: 0.42, dampingFraction: 0.82)) {
                    submissionState = .sent
                }
            } catch {
                submissionState = .idle
                errorMessage = error.localizedDescription
                showsError = true
            }
        }
    }
}

private enum FeedbackSubmissionState {
    case idle
    case sending
    case sent
}

private enum FeedbackField: Hashable {
    case message
    case contact
}
