import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tag(AppTab.home)
                .tabItem {
                    Label(
                        "tab.home".localizedString(),
                        systemImage: selectedTab == .home ? "house.fill" : "house"
                    )
                }

            DictionaryView()
                .tag(AppTab.dictionary)
                .tabItem {
                    Label(
                        "tab.dictionary".localizedString(),
                        systemImage: selectedTab == .dictionary ? "text.book.closed.fill" : "text.book.closed"
                    )
                }

            SupportView()
                .tag(AppTab.support)
                .tabItem {
                    Label(
                        "tab.support".localizedString(),
                        systemImage: selectedTab == .support ? "bubble.left.and.bubble.right.fill" : "bubble.left.and.bubble.right"
                    )
                }

            SettingsTabView()
                .tag(AppTab.settings)
                .tabItem {
                    Label(
                        "tab.settings".localizedString(),
                        systemImage: selectedTab == .settings ? "gearshape.fill" : "gearshape"
                    )
                }

        }
        .tint(BudyTheme.accentDark)
        .onReceive(NotificationCenter.default.publisher(for: .laynorOpenSupportOperator)) { _ in
            selectedTab = .support
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorOpenSupport)) { _ in
            selectedTab = .support
        }
    }
}

private enum AppTab {
    case home
    case dictionary
    case support
    case settings
}

private struct SettingsTabView: View {
    @State private var isShowingSetupSheet = false

    var body: some View {
        SettingsView(showsDoneButton: false) {
            isShowingSetupSheet = true
        }
        .sheet(isPresented: $isShowingSetupSheet) {
            KeyboardSetupSheet {
                isShowingSetupSheet = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
            .presentationDetents([.height(510)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(28)
        }
    }
}
