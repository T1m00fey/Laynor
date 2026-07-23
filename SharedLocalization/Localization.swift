import Foundation

enum LaynorLocalization {
    nonisolated static let appGroupId = "group.Tim.BudyAI"
    nonisolated static let languagePreferenceKey = "laynorAppLanguage"

    nonisolated static var appLanguageCode: String {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "en"
        return normalized(preferred)
    }

    nonisolated static var keyboardLanguageCode: String {
        // The extension can be opened before the main app has had a chance to
        // refresh the shared preference after a device-language change.
        // Prefer Spanish immediately when it is the current device language,
        // instead of getting stuck on a previously saved English value.
        let deviceLanguage = normalized(Locale.preferredLanguages.first ?? "en")
        if deviceLanguage == "es" { return "es" }

        if let saved = UserDefaults(suiteName: appGroupId)?
            .string(forKey: languagePreferenceKey) {
            return normalized(saved)
        }
        return deviceLanguage
    }

    nonisolated static var preferredKeyboardLocale: Locale {
        switch keyboardLanguageCode {
        case "ru": Locale(identifier: "ru_RU")
        case "es": Locale(identifier: "es_ES")
        default: Locale(identifier: "en_US")
        }
    }

    nonisolated static var isRussian: Bool {
        appLanguageCode == "ru"
    }

    nonisolated static func syncKeyboardLanguage() {
        let defaults = UserDefaults(suiteName: appGroupId)
        defaults?.set(appLanguageCode, forKey: languagePreferenceKey)
        defaults?.synchronize()
    }

    nonisolated static func localizedString(for key: String) -> String {
        let isKeyboardExtension = Bundle.main.bundleURL.pathExtension == "appex"
        guard isKeyboardExtension else {
            return Bundle.main.localizedString(forKey: key, value: key, table: nil)
        }

        let language = keyboardLanguageCode
        guard let path = Bundle.main.path(forResource: language, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return key
        }
        return bundle.localizedString(forKey: key, value: key, table: nil)
    }

    private nonisolated static func normalized(_ language: String) -> String {
        let language = language.lowercased()
        if language.hasPrefix("ru") { return "ru" }
        if language.hasPrefix("es") { return "es" }
        return "en"
    }
}

extension String {
    nonisolated func localizedString() -> String {
        LaynorLocalization.localizedString(for: self)
    }
}
