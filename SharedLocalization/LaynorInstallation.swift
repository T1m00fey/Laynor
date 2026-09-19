import Foundation

enum LaynorInstallation {
    private static let appGroupId = "group.Tim.BudyAI"
    private static let identifierKey = "laynorInstallationIdentifier"

    static var identifier: String {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return UUID().uuidString.lowercased()
        }
        if let existing = defaults.string(forKey: identifierKey), !existing.isEmpty {
            return existing
        }

        let identifier = UUID().uuidString.lowercased()
        defaults.set(identifier, forKey: identifierKey)
        return identifier
    }
}
