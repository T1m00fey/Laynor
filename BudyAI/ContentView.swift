import SwiftUI
import UIKit

struct HomeView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    @State private var isShowingOnboarding = false
    @State private var isShowingSetupSheet = false
    @State private var isShowingFeedback = false
    @State private var isShowingSupportAccess = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    hero
                    activationCard
                    functionsOverview
                    supportCard
                    feedbackCard
                    ReadboxCredit()
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 28)
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    HStack(spacing: 9) {
                        BrandImage(size: 34)
//                        Text("Laynor")
//                            .font(.system(size: 19, weight: .bold, design: .rounded))
                    }
                    .contentShape(Rectangle())
                    .onLongPressGesture(minimumDuration: 0.8) {
                        isShowingSupportAccess = true
                    }
                }

            }
            .sheet(isPresented: $isShowingSupportAccess) {
                SupportAccessView()
                    .presentationDetents([.height(330)])
                    .presentationDragIndicator(.visible)
                    .presentationCornerRadius(26)
            }
            .sheet(isPresented: $isShowingSetupSheet) {
                KeyboardSetupSheet {
                    isShowingSetupSheet = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                        openAppSettings()
                    }
                }
                .presentationDetents([.height(510)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(28)
            }
            .sheet(isPresented: $isShowingFeedback) {
                FeedbackView()
            }
            .fullScreenCover(isPresented: $isShowingOnboarding) {
                ProductOnboardingView {
                    hasCompletedOnboarding = true
                    isShowingOnboarding = false
                }
            }
            .onAppear {
                LaynorLocalization.syncKeyboardLanguage()
                guard !hasCompletedOnboarding else { return }
                isShowingOnboarding = true
            }
        }
        .tint(BudyTheme.accentDark)
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("home.hero.title".localizedString())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.9)
                .foregroundStyle(BudyTheme.ink)

            Text("home.hero.subtitle".localizedString())
                .font(.system(size: 16))
                .foregroundStyle(BudyTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, 14)
    }

    private var activationCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(BudyTheme.accent)
                    Image(systemName: "keyboard.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(BudyTheme.ink)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 4) {
                    Text("home.keyboard.title".localizedString())
                        .font(.system(size: 17, weight: .bold, design: .rounded))
                    Text("home.keyboard.subtitle".localizedString())
                        .font(.system(size: 13))
                        .foregroundStyle(BudyTheme.onPrimaryAction.opacity(0.66))
                }
                Spacer(minLength: 0)
            }

            Button {
                isShowingSetupSheet = true
            } label: {
                HStack {
                    Text("home.keyboard.setup".localizedString())
                    Spacer()
                    Image(systemName: "arrow.right")
                }
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BudyTheme.ink)
                .padding(.horizontal, 16)
                .frame(height: 48)
                .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(ProductPressStyle())
        }
        .padding(17)
        .foregroundStyle(BudyTheme.onPrimaryAction)
        .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var functionsOverview: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text("home.features.title".localizedString())
                    .font(.system(size: 21, weight: .bold, design: .rounded))
                Text("home.features.subtitle".localizedString())
                    .font(.system(size: 13))
                    .foregroundStyle(BudyTheme.secondaryInk)
            }

            VStack(spacing: 0) {
                ForEach(RewriteStyle.allCases) { style in
                    CapabilityDescriptionRow(
                        icon: style.icon,
                        title: style.title,
                        description: style.explanation
                    )

                    Divider()
                        .padding(.leading, 48)
                }

                CapabilityDescriptionRow(
                    icon: "bell.badge.fill",
                    title: "home.notifications.title".localizedString(),
                    description: "home.notifications.description".localizedString()
                )

                Divider()
                    .padding(.leading, 48)

                CapabilityDescriptionRow(
                    icon: "text.book.closed.fill",
                    title: "home.dictionary.title".localizedString(),
                    description: "home.dictionary.description".localizedString()
                )
            }
            .padding(.horizontal, 14)
            .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BudyTheme.border, lineWidth: 1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var feedbackCard: some View {
        Button {
            isShowingFeedback = true
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BudyTheme.accentDark)
                    .frame(width: 42, height: 42)
                    .background(BudyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("home.feedback.title".localizedString())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(BudyTheme.ink)
                    Text("home.feedback.subtitle".localizedString())
                        .font(.system(size: 12))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(BudyTheme.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(ProductPressStyle())
    }

    private var supportCard: some View {
        Button {
            NotificationCenter.default.post(name: .laynorOpenSupport, object: nil)
        } label: {
            HStack(spacing: 13) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BudyTheme.accentDark)
                    .frame(width: 42, height: 42)
                    .background(BudyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 13, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("home.support.title".localizedString())
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                        .foregroundStyle(BudyTheme.ink)
                    Text("home.support.subtitle".localizedString())
                        .font(.system(size: 12))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "arrow.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 19, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 19, style: .continuous)
                    .stroke(BudyTheme.border)
            }
            .contentShape(RoundedRectangle(cornerRadius: 19, style: .continuous))
        }
        .buttonStyle(ProductPressStyle())
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct KeyboardSetupSheet: View {
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("keyboard_setup.sheet.title".localizedString())
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(BudyTheme.ink)

                Text("keyboard_setup.sheet.subtitle".localizedString())
                    .font(.system(size: 14))
                    .foregroundStyle(BudyTheme.secondaryInk)
            }

            VStack(spacing: 9) {
                KeyboardSetupRow(
                    number: "1",
                    icon: "gearshape.fill",
                    title: "onboarding.setup.open_settings".localizedString(),
                    subtitle: "onboarding.setup.settings_path".localizedString()
                )
                KeyboardSetupRow(
                    number: "2",
                    icon: "keyboard.fill",
                    title: "onboarding.setup.add_keyboard".localizedString(),
                    subtitle: "onboarding.setup.add_keyboard_hint".localizedString()
                )
                KeyboardSetupRow(
                    number: "3",
                    icon: "network",
                    title: "onboarding.setup.full_access".localizedString(),
                    subtitle: "onboarding.setup.full_access_hint".localizedString()
                )
            }

            Spacer(minLength: 0)

            Button(action: openSettings) {
                HStack {
                    Text("keyboard_setup.sheet.open_settings".localizedString())
                    Spacer()
                    Image(systemName: "arrow.up.right")
                }
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(BudyTheme.onPrimaryAction)
                .padding(.horizontal, 18)
                .frame(height: 54)
                .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            }
            .buttonStyle(ProductPressStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background(BudyTheme.background)
    }
}

private struct KeyboardSetupRow: View {
    let number: String
    let icon: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(BudyTheme.accentSoft)
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BudyTheme.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(BudyTheme.secondaryInk)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Text(number)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.secondaryInk)
                .frame(width: 24, height: 24)
                .background(BudyTheme.field, in: Circle())
        }
        .padding(12)
        .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 17, style: .continuous)
                .stroke(BudyTheme.border, lineWidth: 1)
        }
    }
}

private struct ProductOnboardingView: View {
    let onComplete: () -> Void

    @State private var page = 0

    var body: some View {
        ZStack {
            BudyTheme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    BrandMark(size: 38)
                    Text("Laynor")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                    Spacer()
                    if page < 2 {
                        Button("onboarding.skip".localizedString()) { onComplete() }
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(BudyTheme.secondaryInk)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 12)

                TabView(selection: $page) {
                    OnboardingPage(
                        eyebrow: "onboarding.first.eyebrow".localizedString(),
                        title: "onboarding.first.title".localizedString(),
                        subtitle: "onboarding.first.subtitle".localizedString(),
                        artwork: AnyView(OnboardingKeyboardArtwork())
                    )
                    .tag(0)

                    OnboardingPage(
                        eyebrow: "onboarding.second.eyebrow".localizedString(),
                        title: "onboarding.second.title".localizedString(),
                        subtitle: "onboarding.second.subtitle".localizedString(),
                        artwork: AnyView(OnboardingAppsArtwork())
                    )
                    .tag(1)

                    OnboardingSetupPage()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: page)

                HStack(spacing: 7) {
                    ForEach(0..<3, id: \.self) { index in
                        Capsule()
                            .fill(index == page ? BudyTheme.ink : BudyTheme.ink.opacity(0.14))
                            .frame(width: index == page ? 24 : 7, height: 7)
                    }
                }
                .animation(.spring(response: 0.3), value: page)
                .padding(.bottom, 18)

                Button {
                    if page < 2 {
                        withAnimation { page += 1 }
                    } else {
                        onComplete()
                    }
                } label: {
                    HStack {
                        Text(page == 2 ? "common.done".localizedString() : "common.continue".localizedString())

                        Spacer()

                        Image(systemName: page == 2 ? "checkmark" : "arrow.right")
                    }
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(BudyTheme.onPrimaryAction)
                    .padding(.horizontal, 18)
                    .frame(height: 54)
                    .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
                }
                .buttonStyle(ProductPressStyle())
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
        }
        .tint(BudyTheme.accentDark)
    }
}

private struct OnboardingPage: View {
    let eyebrow: String
    let title: String
    let subtitle: String
    let artwork: AnyView

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Spacer(minLength: 18)
            artwork
                .frame(maxWidth: .infinity)
            Spacer(minLength: 12)
            Text(eyebrow)
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(BudyTheme.accentDark)
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.8)
                .foregroundStyle(BudyTheme.ink)
            Text(subtitle)
                .font(.system(size: 16))
                .foregroundStyle(BudyTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 20)
        }
        .padding(.horizontal, 22)
    }
}

private struct OnboardingSetupPage: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer(minLength: 20)
            Text("onboarding.setup.eyebrow".localizedString())
                .font(.system(size: 11, weight: .black))
                .tracking(1.5)
                .foregroundStyle(BudyTheme.accentDark)
            Text("onboarding.setup.title".localizedString())
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .tracking(-0.8)

            VStack(spacing: 10) {
                SetupStep(number: "1", title: "onboarding.setup.open_settings".localizedString(), subtitle: "onboarding.setup.settings_path".localizedString())
                SetupStep(number: "2", title: "onboarding.setup.add_keyboard".localizedString(), subtitle: "onboarding.setup.add_keyboard_hint".localizedString())
                SetupStep(number: "3", title: "onboarding.setup.full_access".localizedString(), subtitle: "onboarding.setup.full_access_hint".localizedString())
            }

            Button {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            } label: {
                Label("onboarding.setup.open_iphone_settings".localizedString(), systemImage: "arrow.up.right.square")
                    .font(.system(size: 15, weight: .bold))
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .foregroundStyle(BudyTheme.ink)
                    .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(BudyTheme.border)
                    }
            }
            .buttonStyle(ProductPressStyle())

            Spacer(minLength: 20)
        }
        .padding(.horizontal, 22)
    }
}

private struct OnboardingKeyboardArtwork: View {
    private var rows: [String] {
        switch LaynorLocalization.appLanguageCode {
        case "ru":
            ["Й Ц У К Е Н Г Ш Щ", "Ф Ы В А П Р О Л Д", "Я Ч С М И Т Ь Б Ю"]
        case "es":
            ["Q W E R T Y U I O P", "A S D F G H J K L Ñ", "Z X C V B N M"]
        default:
            ["Q W E R T Y U I O P", "A S D F G H J K L", "Z X C V B N M"]
        }
    }

    private var languageLabel: String {
        switch LaynorLocalization.appLanguageCode {
        case "ru": "РУ"
        case "es": "ES"
        default: "EN"
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 7) {
                BrandMark(size: 34)
                Text(languageLabel).font(.system(size: 12, weight: .bold)).padding(.horizontal, 11).frame(height: 34).background(BudyTheme.surface.opacity(0.55), in: Capsule())
                Text("mode.rewrite.title".localizedString()).font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).frame(height: 34).background(BudyTheme.surface.opacity(0.55), in: Capsule())
                Text("mode.correct.title".localizedString()).font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).frame(height: 34).background(BudyTheme.surface.opacity(0.55), in: Capsule())
                Text("mode.concise.title".localizedString()).font(.system(size: 12, weight: .bold)).padding(.horizontal, 12).frame(height: 34).background(BudyTheme.surface.opacity(0.55), in: Capsule())
            }

            ForEach(rows, id: \.self) { row in
                Text(row)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                    .tracking(8)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(BudyTheme.surface.opacity(0.72), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            }
        }
        .padding(14)
        .background(
            LinearGradient(
                colors: [BudyTheme.surface.opacity(0.78), BudyTheme.accent.opacity(0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 26, style: .continuous)
        )
        .rotationEffect(.degrees(-2))
        .shadow(color: .black.opacity(0.08), radius: 24, y: 12)
    }
}

private struct OnboardingAppsArtwork: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(BudyTheme.accentSoft)
                .frame(width: 250, height: 250)
            BrandMark(size: 84)
                .shadow(color: .black.opacity(0.16), radius: 20, y: 10)

            AppBubble(icon: "message.fill", color: BudyTheme.accent).offset(x: -112, y: -60)
            AppBubble(icon: "envelope.fill", color: BudyTheme.brandSurface).offset(x: 112, y: -38)
            AppBubble(icon: "paperplane.fill", color: BudyTheme.accentDark).offset(x: -92, y: 92)
            AppBubble(icon: "note.text", color: BudyTheme.secondaryInk).offset(x: 96, y: 92)
        }
        .frame(height: 290)
    }
}

private struct AppBubble: View {
    let icon: String
    let color: Color

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 58, height: 58)
            .background(color, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
            .shadow(color: color.opacity(0.26), radius: 14, y: 7)
    }
}

private struct SetupStep: View {
    let number: String
    let title: String
    let subtitle: String

    var body: some View {
        HStack(spacing: 13) {
            Text(number)
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(BudyTheme.accentDark)
                .frame(width: 38, height: 38)
                .background(BudyTheme.accentSoft, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 15, weight: .bold))
                Text(subtitle).font(.system(size: 12)).foregroundStyle(BudyTheme.secondaryInk)
            }
            Spacer(minLength: 0)
        }
        .padding(13)
        .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
    }
}

private struct BrandImage: View {
    let size: CGFloat
    
    var body: some View {
        Image(systemName: "sparkles")
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundStyle(BudyTheme.accent)
    }
}

private struct BrandMark: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.31, style: .continuous)
                .fill(BudyTheme.brandSurface)
            
            BrandImage(size: size)
        }
        .frame(width: size, height: size)
    }
}

private struct CapabilityDescriptionRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BudyTheme.accentDark)
                .frame(width: 36, height: 36)
                .background(BudyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BudyTheme.ink)
                Text(description)
                    .font(.system(size: 13))
                    .foregroundStyle(BudyTheme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, 1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
    }
}

private struct ProductPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

struct ReadboxCredit: View {
    var body: some View {
        Link(destination: URL(string: "https://readbox.online")!) {
            HStack(spacing: 7) {
                Circle()
                    .fill(BudyTheme.accent)
                    .frame(width: 6, height: 6)

                HStack(spacing: 4) {
                    Text("by")
                        .fontWeight(.medium)
                        .foregroundStyle(BudyTheme.secondaryInk)
                    Text("ReadBox")
                        .fontWeight(.bold)
                        .foregroundStyle(BudyTheme.ink)
                }

                Rectangle()
                    .fill(BudyTheme.border)
                    .frame(width: 1, height: 14)

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .font(.system(size: 13, design: .rounded))
            .padding(.leading, 13)
            .padding(.trailing, 11)
            .frame(height: 38)
            .background(BudyTheme.surface, in: Capsule())
            .overlay {
                Capsule()
                    .stroke(BudyTheme.border, lineWidth: 1)
            }
            .contentShape(Capsule())
        }
        .buttonStyle(ReadboxCreditPressStyle())
        .accessibilityLabel("settings.about.developer".localizedString())
    }
}

private struct ReadboxCreditPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.76 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}

private extension RewriteStyle {
    var explanation: String {
        switch self {
        case .rewrite:
            "mode.rewrite.description".localizedString()
        case .correct:
            "mode.correct.description".localizedString()
        case .concise:
            "mode.concise.description".localizedString()
        case .professional:
            "mode.professional.description".localizedString()
        }
    }

    var actionTitle: String {
        switch self {
        case .rewrite: "mode.rewrite.title".localizedString()
        case .correct: "mode.correct.action".localizedString()
        case .concise: "mode.concise.action".localizedString()
        case .professional: "mode.professional.action".localizedString()
        }
    }
}
