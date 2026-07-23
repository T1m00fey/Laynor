//
//  BudyAIApp.swift
//  BudyAI
//
//  Created by Тимофей Юдин on 15.07.2026.
//

import SwiftUI

@main
struct BudyAIApp: App {
    init() {
        LaynorLocalization.syncKeyboardLanguage()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
