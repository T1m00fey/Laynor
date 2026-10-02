import Foundation
import NaturalLanguage

struct LaynorPersonalWord: Codable, Hashable, Identifiable, Sendable {
    let id: UUID
    var word: String
    let languageCode: String
    var selectionCount: Int
    let createdAt: Date
    var lastUsedAt: Date
}

enum LaynorPersonalDictionary {
    static let appGroupId = "group.Tim.BudyAI"
    static let maximumWordLength = 48

    private static let storageKey = "laynor.personalDictionary.v1"
    private static let lock = NSLock()

    static func languageCode(for locale: Locale) -> String {
        let code = locale.language.languageCode?.identifier.lowercased() ?? "en"
        return supportedLanguageCodes.contains(code) ? code : "en"
    }

    /// Detects a manually entered word from its script and language signals.
    static func detectedLanguageCode(for value: String) -> String {
        guard let word = validatedWord(value) else {
            return languageCode(for: Locale(identifier: LaynorLocalization.appLanguageCode))
        }

        let scalars = word.unicodeScalars
        if scalars.contains(where: { (0x0400...0x04FF).contains(Int($0.value)) }) {
            return "ru"
        }

        let spanishMarkers = CharacterSet(charactersIn: "áéíóúüñÁÉÍÓÚÜÑ")
        if scalars.contains(where: spanishMarkers.contains) { return "es" }

        let recognizer = NLLanguageRecognizer()
        recognizer.processString(word)
        if let language = recognizer.dominantLanguage?.rawValue,
           supportedLanguageCodes.contains(language) {
            return language
        }

        return languageCode(for: Locale(identifier: LaynorLocalization.appLanguageCode))
    }

    static func allWords() -> [LaynorPersonalWord] {
        lock.withLock {
            loadWords().sorted(by: wordSort)
        }
    }

    static func words(for languageCode: String) -> [LaynorPersonalWord] {
        let language = normalizedLanguageCode(languageCode)
        return allWords().filter { $0.languageCode == language }
    }

    static func contains(_ word: String, languageCode: String) -> Bool {
        guard let word = validatedWord(word) else { return false }
        let language = normalizedLanguageCode(languageCode)
        let normalized = normalizedWord(word, languageCode: language)
        return lock.withLock {
            loadWords().contains {
                $0.languageCode == language
                    && normalizedWord($0.word, languageCode: language) == normalized
            }
        }
    }

    @discardableResult
    static func learn(
        _ word: String,
        languageCode: String,
        incrementUsage: Bool = true
    ) -> LaynorPersonalWord? {
        guard let word = validatedWord(word) else { return nil }
        let language = normalizedLanguageCode(languageCode)
        let normalized = normalizedWord(word, languageCode: language)
        let now = Date()

        let learned: LaynorPersonalWord = lock.withLock {
            var words = loadWords()
            if let index = words.firstIndex(where: {
                $0.languageCode == language
                    && normalizedWord($0.word, languageCode: language) == normalized
            }) {
                if incrementUsage {
                    words[index].selectionCount += 1
                }
                words[index].lastUsedAt = now
                saveWords(words)
                return words[index]
            }

            let value = LaynorPersonalWord(
                id: UUID(),
                word: word,
                languageCode: language,
                selectionCount: incrementUsage ? 1 : 0,
                createdAt: now,
                lastUsedAt: now
            )
            words.append(value)
            saveWords(words)
            return value
        }

        notifyChange()
        return learned
    }

    static func recordSelection(of word: String, languageCode: String) {
        _ = learn(word, languageCode: languageCode, incrementUsage: true)
    }

    static func remove(id: UUID) {
        let didRemove = lock.withLock {
            var words = loadWords()
            let oldCount = words.count
            words.removeAll { $0.id == id }
            guard words.count != oldCount else { return false }
            saveWords(words)
            return true
        }
        if didRemove { notifyChange() }
    }

    static func remove(_ word: String, languageCode: String) {
        guard let word = validatedWord(word) else { return }
        let language = normalizedLanguageCode(languageCode)
        let normalized = normalizedWord(word, languageCode: language)
        let didRemove = lock.withLock {
            var words = loadWords()
            let oldCount = words.count
            words.removeAll {
                $0.languageCode == language
                    && normalizedWord($0.word, languageCode: language) == normalized
            }
            guard words.count != oldCount else { return false }
            saveWords(words)
            return true
        }
        if didRemove { notifyChange() }
    }

    static func removeAll() {
        lock.withLock {
            defaults.removeObject(forKey: storageKey)
        }
        notifyChange()
    }

    static func suggestions(
        for input: String,
        languageCode: String,
        limit: Int = 3
    ) -> [LaynorPersonalWord] {
        guard limit > 0, let input = validatedWord(input) else { return [] }
        let language = normalizedLanguageCode(languageCode)
        let normalizedInput = normalizedWord(input, languageCode: language)

        return words(for: language)
            .compactMap { entry -> (LaynorPersonalWord, Int)? in
                let candidate = normalizedWord(entry.word, languageCode: language)
                if candidate.hasPrefix(normalizedInput) {
                    return (entry, candidate == normalizedInput ? 0 : 1)
                }

                guard normalizedInput.count >= 3, entry.selectionCount >= 3 else {
                    return nil
                }
                let comparablePrefix = String(candidate.prefix(normalizedInput.count))
                guard editDistance(normalizedInput, comparablePrefix) <= 1 else {
                    return nil
                }
                return (entry, 2)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                if $0.0.selectionCount != $1.0.selectionCount {
                    return $0.0.selectionCount > $1.0.selectionCount
                }
                return $0.0.lastUsedAt > $1.0.lastUsedAt
            }
            .prefix(limit)
            .map(\.0)
    }

    static func isConfidentAutocorrection(
        _ candidate: LaynorPersonalWord,
        for input: String
    ) -> Bool {
        guard candidate.selectionCount >= 3, input.count >= 4 else { return false }
        let language = candidate.languageCode
        let source = normalizedWord(input, languageCode: language)
        let target = normalizedWord(candidate.word, languageCode: language)
        // A personal suggestion may complete a typo, but should not delete
        // characters from an unknown token without an explicit tap.
        guard source != target, target.count >= source.count,
              abs(source.count - target.count) <= 1 else {
            return false
        }
        return editDistance(source, target) <= 1
    }

    static func validatedWord(_ value: String) -> String? {
        let word = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty, word.count <= maximumWordLength else { return nil }
        guard word.unicodeScalars.contains(where: CharacterSet.letters.contains) else {
            return nil
        }
        guard word.unicodeScalars.allSatisfy(allowedCharacters.contains) else {
            return nil
        }
        return word
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupId) ?? .standard
    }

    private static func loadWords() -> [LaynorPersonalWord] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([LaynorPersonalWord].self, from: data)) ?? []
    }

    private static func saveWords(_ words: [LaynorPersonalWord]) {
        guard let data = try? JSONEncoder().encode(words) else { return }
        defaults.set(data, forKey: storageKey)
    }

    private static func notifyChange() {
        NotificationCenter.default.post(
            name: .laynorPersonalDictionaryDidChange,
            object: nil
        )
    }

    private static func normalizedLanguageCode(_ value: String) -> String {
        let code = value.lowercased().split(separator: "-").first.map(String.init) ?? "en"
        return supportedLanguageCodes.contains(code) ? code : "en"
    }

    private static func normalizedWord(_ word: String, languageCode: String) -> String {
        word.folding(options: [.diacriticInsensitive], locale: Locale(identifier: languageCode))
            .lowercased(with: Locale(identifier: languageCode))
    }

    private static func wordSort(_ left: LaynorPersonalWord, _ right: LaynorPersonalWord) -> Bool {
        if left.languageCode != right.languageCode {
            return left.languageCode < right.languageCode
        }
        return left.word.localizedCaseInsensitiveCompare(right.word) == .orderedAscending
    }

    private static func editDistance(_ left: String, _ right: String) -> Int {
        let lhs = Array(left)
        let rhs = Array(right)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for (leftIndex, leftCharacter) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = leftIndex + 1
            for (rightIndex, rightCharacter) in rhs.enumerated() {
                let substitution = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + substitution
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static let supportedLanguageCodes = Set(["ru", "en", "es"])
    private static let allowedCharacters = CharacterSet.letters
        .union(.decimalDigits)
        .union(CharacterSet(charactersIn: "-'’"))
}


struct LaynorSavedItem: Codable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case word
        case email
        case phone
        case text

        var icon: String {
            switch self {
            case .word: "textformat"
            case .email: "envelope"
            case .phone: "phone"
            case .text: "text.quote"
            }
        }
    }

    let id: UUID
    var title: String
    var value: String
    let kind: Kind
    var selectionCount: Int
    let createdAt: Date
    var lastUsedAt: Date
}

enum LaynorSavedItemsStore {
    private static let storageKey = "laynor.savedItems.v1"
    private static let lock = NSLock()
    private static let appGroupId = LaynorPersonalDictionary.appGroupId

    static func all() -> [LaynorSavedItem] {
        lock.withLock { load().sorted { left, right in
            if left.lastUsedAt != right.lastUsedAt { return left.lastUsedAt > right.lastUsedAt }
            return left.value.localizedCaseInsensitiveCompare(right.value) == .orderedAscending
        } }
    }

    @discardableResult
    static func add(title: String, value: String) -> LaynorSavedItem? {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanValue.isEmpty, cleanValue.count <= 500 else { return nil }
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let now = Date()
        let item: LaynorSavedItem = lock.withLock {
            var items = load()
            if let index = items.firstIndex(where: { $0.value.caseInsensitiveCompare(cleanValue) == .orderedSame }) {
                items[index].title = cleanTitle
                save(items)
                return items[index]
            }
            let value = LaynorSavedItem(
                id: UUID(),
                title: cleanTitle,
                value: cleanValue,
                kind: detectKind(cleanValue),
                selectionCount: 0,
                createdAt: now,
                lastUsedAt: now
            )
            items.append(value)
            save(items)
            return value
        }
        notifyChange()
        return item
    }

    static func recordSelection(_ item: LaynorSavedItem) {
        lock.withLock {
            var items = load()
            guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
            items[index].selectionCount += 1
            items[index].lastUsedAt = Date()
            save(items)
        }
        notifyChange()
    }

    static func remove(id: UUID) {
        let changed = lock.withLock {
            var items = load()
            let count = items.count
            items.removeAll { $0.id == id }
            guard count != items.count else { return false }
            save(items)
            return true
        }
        if changed { notifyChange() }
    }

    static func removeAll() {
        lock.withLock { defaults.removeObject(forKey: storageKey) }
        notifyChange()
    }

    private static func detectKind(_ value: String) -> LaynorSavedItem.Kind {
        if value.range(of: #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#, options: [.regularExpression, .caseInsensitive]) != nil { return .email }
        if value.range(of: #"^[+()0-9][0-9 ()\-]{5,}$"#, options: .regularExpression) != nil { return .phone }
        if value.contains(where: { $0.isWhitespace }) { return .text }
        return .word
    }

    private static var defaults: UserDefaults { UserDefaults(suiteName: appGroupId) ?? .standard }
    private static func load() -> [LaynorSavedItem] {
        guard let data = defaults.data(forKey: storageKey) else { return [] }
        return (try? JSONDecoder().decode([LaynorSavedItem].self, from: data)) ?? []
    }
    private static func save(_ items: [LaynorSavedItem]) {
        guard let data = try? JSONEncoder().encode(items) else { return }
        defaults.set(data, forKey: storageKey)
    }
    private static func notifyChange() {
        NotificationCenter.default.post(name: .laynorSavedItemsDidChange, object: nil)
    }
}

extension Notification.Name {
    static let laynorPersonalDictionaryDidChange = Notification.Name(
        "laynor.personalDictionary.didChange"
    )
    static let laynorSavedItemsDidChange = Notification.Name(
        "laynor.savedItems.didChange"
    )
}
