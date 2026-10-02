import SwiftUI
import UIKit

struct ContentView: View {
    @State private var selectedTab: AppTab = .home
    @State private var unreadSupportCount = 0
    

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

            SupportView(unreadCount: $unreadSupportCount)
                .tag(AppTab.support)
                .badge(unreadSupportCount > 0 ? unreadSupportCount : 0)
                .tabItem {
                    Label(
                        "tab.support".localizedString(),
                        systemImage: selectedTab == .support
                            ? "bubble.left.and.bubble.right.fill"
                            : "bubble.left.and.bubble.right"
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
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportDidChange)) { _ in
            refreshUnreadSupportCount()
        }
        .onAppear {
            refreshUnreadSupportCount()
        }
    }

    private func refreshUnreadSupportCount() {
        unreadSupportCount = SupportStore.allThreads().reduce(0) {
            $0 + $1.unreadSupportMessageCount
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
