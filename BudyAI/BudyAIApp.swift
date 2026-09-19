//
//  BudyAIApp.swift
//  BudyAI
//
//  Created by Тимофей Юдин on 15.07.2026.
//

import SwiftUI
import UIKit
import UserNotifications
#if canImport(FirebaseCore)
import FirebaseCore
import FirebaseMessaging
#endif

final class LaynorAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
#if canImport(FirebaseCore)
        if FirebaseApp.app() == nil,
           let path = Bundle.main.path(
            forResource: "GoogleService-Info",
            ofType: "plist"
           ),
           let options = FirebaseOptions(contentsOfFile: path) {
            FirebaseApp.configure(options: options)
            Messaging.messaging().delegate = self
        }
#endif

        Task {
            let status = await LaynorReminderCenter.authorizationStatus()
            guard status == .authorized || status == .provisional || status == .ephemeral else {
                return
            }
            await MainActor.run {
                application.registerForRemoteNotifications()
            }
        }
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
#if canImport(FirebaseMessaging)
        guard FirebaseApp.app() != nil else {
            print("Firebase is not configured: add GoogleService-Info.plist to the BudyAI target")
            return
        }
        Messaging.messaging().apnsToken = deviceToken
        Messaging.messaging().token { token, _ in
            guard let token, !token.isEmpty else { return }
            Task {
                do {
                    try await LaynorPushService.registerDevice(fcmToken: token)
                    await LaynorPushService.uploadPendingReminders()
                } catch {
                    print("Push registration failed: \(error)")
                }
            }
        }
#endif
    }
}

#if canImport(FirebaseMessaging)
extension LaynorAppDelegate: MessagingDelegate {
    func messaging(
        _ messaging: Messaging,
        didReceiveRegistrationToken fcmToken: String?
    ) {
        guard let fcmToken, !fcmToken.isEmpty else { return }
        Task {
            do {
                try await LaynorPushService.registerDevice(fcmToken: fcmToken)
                await LaynorPushService.uploadPendingReminders()
            } catch {
                print("Push registration failed: \(error)")
            }
        }
    }
}
#endif

@main
struct BudyAIApp: App {
    @UIApplicationDelegateAdaptor(LaynorAppDelegate.self) private var appDelegate

    init() {
        LaynorLocalization.syncKeyboardLanguage()
        _ = LaynorInstallation.identifier
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
