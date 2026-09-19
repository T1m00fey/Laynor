import KeyboardKit
import SwiftUI
import UIKit

final class KeyboardViewController: KeyboardInputViewController {
    private static let appGroupId = "group.Tim.BudyAI"
    private static let hapticsPreferenceKey = "keyboardHapticsEnabled"

    private enum RewritePosition: Equatable {
        case generated
        case original
    }

    private struct RewriteTransaction {
        let original: String
        let generated: String
        var position: RewritePosition
    }

    private let editHistory = KeyboardEditHistory()
    private let commandContext = KeyboardCommandContext()
    private let interactionContext = KeyboardInteractionContext()
    // Resolve shared preferences while the extension is being created, not
    // from a toolbar tap. If the keyboard is visible, these values are ready
    // and confirming a reminder performs no App Group I/O.
    private let installationId = LaynorInstallation.identifier
    private let reminderLeadMinutes = LaynorReminderCenter.leadMinutes
    private var rewriteTransaction: RewriteTransaction?
    private var configuredKeyboardLanguageCode: String?

    override func viewDidLoad() {
        super.viewDidLoad()
        commandContext.setSubmissionHandler { [weak self] instruction in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.rewrite(instruction: instruction)
                self.commandContext.completeSubmission(with: result)
            }
        }
        applyTransparentBackground()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        applyPreferredKeyboardLanguage()
        applyTransparentBackground()
        syncHapticPreference()
    }

    override func viewWillSetupKeyboardKit() {
        setupKeyboardKit(for: .laynor) { [weak self] result in
            guard let self else { return }

            if case .failure(let error) = result {
                print("KeyboardKit setup failed: \(error)")
            }

            self.configureKeyboardStateForRendering()
            let context = self.state.keyboardContext

            // Install the lightweight service before the first render. The
            // standard dictionary service can be relatively expensive on a
            // cold extension launch and used to delay the whole keyboard.
            self.services.autocompleteService = BudyAutocompleteService(locale: context.locale)
            self.services.actionHandler = BudyKeyboardActionHandler(
                controller: self,
                state: self.state,
                services: self.services,
                commandContext: self.commandContext,
                interactionContext: self.interactionContext
            )
            self.syncHapticPreference()

            // Let KeyboardKit install and draw the keyboard first, then load
            // dictionary autocomplete without blocking the initial UI.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
                self?.applyPreferredKeyboardLanguage()
                self?.setupStandardAutocompleteService()
            }
        }
    }

    override func viewWillSetupKeyboardView() {
        // KeyboardKit can ask for the SwiftUI view before its asynchronous
        // setup completion runs. Configure every layout-affecting value here,
        // so the very first rendered frame is already the final keyboard and
        // never has to be replaced after it becomes visible.
        configureKeyboardStateForRendering()
        setupKeyboardView { [weak self] controller in
            BudyKeyboardView(
                services: controller.services,
                state: controller.state,
                editHistory: self?.editHistory ?? KeyboardEditHistory(),
                commandContext: self?.commandContext ?? KeyboardCommandContext(),
                interactionContext: self?.interactionContext ?? KeyboardInteractionContext(),
                onRewrite: { [weak self] style in
                    await self?.rewrite(style: style)
                },
                onParseReminder: { [weak self] in
                    guard let self else {
                        return .failure("keyboard.command.failed".localizedString())
                    }
                    return await self.parseReminder()
                },
                onScheduleReminder: { [weak self] draft, completion in
                    guard let self else {
                        completion(
                            .failure("keyboard.command.failed".localizedString())
                        )
                        return
                    }
                    self.createReminder(
                        from: draft,
                        completion: completion
                    )
                },
                onUndo: { [weak self] in self?.undoRewrite() },
                onRedo: { [weak self] in self?.redoRewrite() },
                onInsertSavedItem: { [weak self] item in
                    self?.insertText(item.value)
                }
            )
        }
    }

    private func rewrite(style: KeyboardRewriteStyle) async -> KeyboardRewriteResult {
        await rewrite { source in
            try await KeyboardRewriteService().rewrite(source, style: style)
        }
    }

    private func rewrite(instruction: String) async -> KeyboardRewriteResult {
        let trimmedInstruction = instruction.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedInstruction.isEmpty else {
            return .failure("keyboard.error.enter_command".localizedString())
        }

        return await rewrite { source in
            try await KeyboardRewriteService().rewrite(
                source,
                instruction: trimmedInstruction
            )
        }
    }

    private func parseReminder() async -> KeyboardReminderParseResult {
        guard hasFullAccess else {
            return .failure("keyboard.error.enable_full_access".localizedString())
        }
        guard let source = currentSourceText() else {
            return .failure("keyboard.error.enter_or_select_text".localizedString())
        }

        do {
            return .success(
                try await KeyboardRewriteService().parseReminder(source)
            )
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func createReminder(
        from draft: LaynorReminderDraft,
        completion: @escaping (KeyboardReminderScheduleResult) -> Void
    ) {
        guard draft.fireDate.timeIntervalSinceNow >= 5 else {
            completion(
                .failure(LaynorReminderError.invalidDate.localizedDescription)
            )
            return
        }

        let preferredNotificationDate = draft.fireDate.addingTimeInterval(
            -TimeInterval(reminderLeadMinutes * 60)
        )
        let reminder = LaynorReminder(
            id: UUID(),
            title: draft.title,
            fireDate: max(
                preferredNotificationDate,
                Date().addingTimeInterval(5)
            ),
            eventDate: draft.fireDate,
            createdAt: Date()
        )

        KeyboardRewriteService().createServerReminder(
            reminder,
            installationId: installationId
        ) { result in
            switch result {
            case .success:
                completion(.success)
            case .failure(let error):
                completion(.failure(error.localizedDescription))
            }
        }
    }

    private func currentSourceText() -> String? {
        if let selected = textDocumentProxy.selectedText,
           !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return selected
        }

        guard let context = textDocumentProxy.documentContextBeforeInput else {
            return nil
        }
        let paragraph = context.components(separatedBy: .newlines).last ?? context
        let source = String(paragraph.suffix(1500))
        return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? nil
            : source
    }

    private func rewrite(
        transform: (String) async throws -> String
    ) async -> KeyboardRewriteResult {
        guard hasFullAccess else {
            return .failure("keyboard.error.enable_full_access".localizedString())
        }

        let selected = textDocumentProxy.selectedText
        let source: String
        let shouldDelete: Bool

        if let selected, !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            source = selected
            shouldDelete = false
        } else if let context = textDocumentProxy.documentContextBeforeInput {
            let paragraph = context.components(separatedBy: .newlines).last ?? context
            source = String(paragraph.suffix(1500))
            shouldDelete = true
        } else {
            return .failure("keyboard.error.enter_or_select_text".localizedString())
        }

        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return .failure("keyboard.error.enter_or_select_text".localizedString())
        }

        do {
            let output = try await transform(source)
            if shouldDelete {
                deleteBackward(times: source.count)
            }
            insertText(output)
            rewriteTransaction = RewriteTransaction(
                original: source,
                generated: output,
                position: .generated
            )
            editHistory.showGeneratedState()
            return .success
        } catch {
            return .failure(error.localizedDescription)
        }
    }

    private func undoRewrite() {
        guard var transaction = rewriteTransaction,
              transaction.position == .generated,
              textDocumentProxy.documentContextBeforeInput?.hasSuffix(transaction.generated) == true else {
            clearRewriteHistory()
            return
        }

        deleteBackward(times: transaction.generated.count)
        insertText(transaction.original)
        transaction.position = .original
        rewriteTransaction = transaction
        editHistory.showOriginalState()
    }

    private func redoRewrite() {
        guard var transaction = rewriteTransaction,
              transaction.position == .original,
              textDocumentProxy.documentContextBeforeInput?.hasSuffix(transaction.original) == true else {
            clearRewriteHistory()
            return
        }

        deleteBackward(times: transaction.original.count)
        insertText(transaction.generated)
        transaction.position = .generated
        rewriteTransaction = transaction
        editHistory.showGeneratedState()
    }

    private func clearRewriteHistory() {
        rewriteTransaction = nil
        editHistory.clear()
    }

    private func applyTransparentBackground() {
        view.backgroundColor = .clear
        view.isOpaque = false
        inputView?.backgroundColor = .clear
        inputView?.isOpaque = false
    }

    private func syncHapticPreference() {
        let defaults = UserDefaults(suiteName: Self.appGroupId)
        let enabled = defaults?.object(forKey: Self.hapticsPreferenceKey) as? Bool ?? true
        guard state.feedbackContext.settings.isHapticFeedbackEnabled != enabled else { return }
        state.feedbackContext.settings.isHapticFeedbackEnabled = enabled
    }

    private func configureKeyboardStateForRendering() {
        applyPreferredKeyboardLanguage()

        let context = state.keyboardContext
        context.isLiquidGlassEnabled = context.isLiquidGlassAvailable
        context.settings.spacebarLongPressBehavior = .moveInputCursor

        state.autocompleteContext.settings.isAutocompleteEnabled = true
        state.autocompleteContext.settings.isAutocorrectEnabled = true
        state.autocompleteContext.settings.isAutoIgnoreEnabled = true
        state.autocompleteContext.settings.isToolbarEnabled = true
        // Inline next-character prediction is expensive and isn't used by our
        // toolbar. Keep word completion and next-word suggestions.
        state.autocompleteContext.settings.isNextCharacterPredictionEnabled = false
        state.autocompleteContext.settings.isNextWordPredictionEnabled = true
        state.autocompleteContext.settings.nextWordPredictionMethod = .local
    }

    private func applyPreferredKeyboardLanguage() {
        let context = state.keyboardContext
        let languageCode = LaynorLocalization.keyboardLanguageCode
        let locale = LaynorLocalization.preferredKeyboardLocale
        let supportedLocales: [Locale]

        switch languageCode {
        case "ru":
            supportedLocales = [Locale(identifier: "ru_RU"), Locale(identifier: "en_US")]
        case "es":
            supportedLocales = [locale]
        default:
            supportedLocales = [locale]
        }

        context.locales = supportedLocales

        let supportedLanguageCodes = Set(supportedLocales.compactMap {
            $0.language.languageCode?.identifier
        })
        let currentLanguageCode = context.locale.language.languageCode?.identifier
        let configurationChanged = configuredKeyboardLanguageCode != languageCode

        // Apply the app language on the first presentation (or after a real
        // device-language change), but preserve a RU/EN choice made with the
        // keyboard button during later layout and autocomplete refreshes.
        if configurationChanged || !supportedLanguageCodes.contains(currentLanguageCode ?? "") {
            context.locale = locale
        }

        configuredKeyboardLanguageCode = languageCode
        services.autocompleteService.locale = context.locale
    }

    private func setupStandardAutocompleteService() {
        let context = state.keyboardContext

        do {
            let autocompleteService = try BudyStandardAutocompleteService(
                autocompleteContext: state.autocompleteContext,
                keyboardContext: context,
                locale: context.locale
            )
            services.autocompleteService = autocompleteService
            requestSupplementaryLexicon { lexicon in
                autocompleteService.registerLexicon(lexicon)
            }
        } catch {
            print("KeyboardKit autocomplete setup failed: \(error)")
        }
    }

}

nonisolated private final class BudyKeyboardActionHandler: StandardKeyboardActionHandler {
    private let commandContext: KeyboardCommandContext
    private let interactionContext: KeyboardInteractionContext
    // KeyboardKit can restore a key's pressed state while the extension is
    // being mounted. Feedback is only valid while an actual gesture is being
    // handled; this gate prevents sounds or haptics from firing on launch.
    private var isHandlingGesture = false

    init(
        controller: any KeyboardController,
        state: KeyboardState,
        services: KeyboardServices,
        commandContext: KeyboardCommandContext,
        interactionContext: KeyboardInteractionContext
    ) {
        self.commandContext = commandContext
        self.interactionContext = interactionContext
        super.init(
            controller: controller,
            keyboardContext: state.keyboardContext,
            keyboardBehavior: services.keyboardBehavior,
            autocompleteContext: state.autocompleteContext,
            autocompleteService: services.autocompleteService,
            emojiContext: state.emojiContext,
            feedbackContext: state.feedbackContext,
            feedbackService: services.feedbackService,
            keyboardAppContext: state.keyboardAppContext,
            spacebarDragGestureHandler: services.spacebarDragGestureHandler
        )
    }

    override func handle(_ action: KeyboardAction) {
        if action == .budyLocaleSwitch {
            super.handle(.nextLocale)
            return
        }

        guard commandContext.isActive, capture(action) else {
            super.handle(action)
            return
        }
    }

    override func handle(_ suggestion: AutocompleteSuggestion) {
        let languageCode = LaynorPersonalDictionary.languageCode(
            for: keyboardContext.locale
        )
        let currentWord = currentDocumentContextBeforeInput?.trailingAutocompleteWord ?? ""
        let selectedWord = suggestion.text.trailingAutocompleteWord
        let selectedCurrentWord = !currentWord.isEmpty
            && selectedWord.compare(
                currentWord,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: nil,
                locale: keyboardContext.locale
            ) == .orderedSame

        if suggestion.isRegular, selectedCurrentWord {
            LaynorPersonalDictionary.learn(
                currentWord,
                languageCode: languageCode
            )
        } else if LaynorPersonalDictionary.contains(
            selectedWord,
            languageCode: languageCode
        ) {
            LaynorPersonalDictionary.recordSelection(
                of: selectedWord,
                languageCode: languageCode
            )
        }

        super.handle(suggestion)
    }

    override func handle(_ gesture: Keyboard.Gesture, on action: KeyboardAction) {
        isHandlingGesture = true
        defer { isHandlingGesture = false }

        if action == .backspace {
            switch gesture {
            case .repeatPress:
                interactionContext.beginRepeatingBackspace()
            case .release:
                interactionContext.endRepeatingBackspace()
            default:
                break
            }
        }

        if action == .budyLocaleSwitch {
            super.handle(gesture, on: .nextLocale)
            return
        }

        guard commandContext.isActive, isCaptured(action) else {
            super.handle(gesture, on: action)
            return
        }

        tryTriggerFeedback(for: gesture, on: action)

        switch gesture {
        case .release:
            _ = capture(action)
        case .repeatPress:
            if action == .backspace {
                commandContext.deleteBackward()
            }
        default:
            break
        }
    }

    override func triggerAudioFeedback(_ feedback: KeyboardAudioFeedback) {
        guard isHandlingGesture else { return }
        super.triggerAudioFeedback(feedback)
    }

    override func triggerHapticFeedback(_ feedback: KeyboardHapticFeedback) {
        guard isHandlingGesture else { return }
        super.triggerHapticFeedback(feedback)
    }

    override func shouldApplyAutocorrectSuggestion(
        before gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) -> Bool {
        guard BudyAutocorrectionPolicy.allowsAutocorrect(
            inputType: keyboardContext.keyboardInputType,
            textBeforeCursor: currentDocumentContextBeforeInput,
            boundaryAction: action
        ) else {
            return false
        }

        if let suggestion = autocompleteContext.suggestions.first(where: \.isAutocorrect),
           !BudyAutocorrectionPolicy.isConfidentCorrection(
                suggestion.text,
                forTextBeforeCursor: currentDocumentContextBeforeInput
           ) {
            return false
        }

        return super.shouldApplyAutocorrectSuggestion(before: gesture, on: action)
    }

    override func shouldPerformAutocomplete(
        after gesture: Keyboard.Gesture,
        on action: KeyboardAction
    ) -> Bool {
        guard BudyAutocorrectionPolicy.allowsAutocomplete(
            inputType: keyboardContext.keyboardInputType,
            textBeforeCursor: currentDocumentContextBeforeInput
        ) else {
            autocompleteContext.reset()
            return false
        }

        return super.shouldPerformAutocomplete(after: gesture, on: action)
    }

    private var currentDocumentContextBeforeInput: String? {
        MainActor.assumeIsolated {
            keyboardContext.textDocumentProxy.documentContextBeforeInput
        }
    }

    private func isCaptured(_ action: KeyboardAction) -> Bool {
        switch action {
        case .character, .characterMargin, .text, .emoji,
             .space, .backspace, .primary, .tab:
            true
        default:
            false
        }
    }

    @discardableResult
    private func capture(_ action: KeyboardAction) -> Bool {
        switch action {
        case .character(let value), .characterMargin(let value), .text(let value):
            commandContext.append(value)
        case .emoji(let emoji):
            commandContext.append(emoji.char)
        case .space:
            commandContext.append(" ")
        case .tab:
            commandContext.append(" ")
        case .backspace:
            commandContext.deleteBackward()
        case .primary:
            commandContext.requestSubmission()
        default:
            return false
        }
        return true
    }
}

nonisolated private enum BudyAutocorrectionPolicy {
    static func allowsAutocomplete(
        inputType: Keyboard.InputType,
        textBeforeCursor: String?
    ) -> Bool {
        guard inputType.prefersNaturalLanguageAutocomplete else { return false }
        guard let token = currentToken(in: textBeforeCursor), !token.isEmpty else { return true }
        return !isProtectedToken(token)
    }

    static func allowsAutocorrect(
        inputType: Keyboard.InputType,
        textBeforeCursor: String?,
        boundaryAction: KeyboardAction
    ) -> Bool {
        guard allowsAutocomplete(
            inputType: inputType,
            textBeforeCursor: textBeforeCursor
        ) else { return false }

        if let boundary = boundaryText(for: boundaryAction),
           boundary.rangeOfCharacter(from: protectedBoundaryCharacters) != nil {
            return false
        }

        guard let token = currentToken(in: textBeforeCursor) else { return true }

        // A dot after a Latin token is very often the beginning of an e-mail,
        // domain or username. Don't commit a dictionary correction before we
        // get a chance to see the following `@` or domain component.
        if boundaryText(for: boundaryAction)?.contains(".") == true,
           isLikelyLatinIdentifierPrefix(token) {
            return false
        }

        let letters = token.filter(\.isLetter)

        // Two-letter words are especially ambiguous for a dictionary-based
        // checker: an intentional abbreviation such as "чм" can otherwise
        // be changed to "чем" as soon as the user enters a separator.
        guard letters.count >= 3 else { return false }

        // Keep codes, mixed identifiers and deliberately cased names intact.
        if token.contains(where: \.isNumber) { return false }
        let uppercaseCount = letters.filter(\.isUppercase).count
        if uppercaseCount > 1 && uppercaseCount < letters.count { return false }

        return true
    }

    static func isConfidentCorrection(
        _ correction: String,
        forTextBeforeCursor textBeforeCursor: String?
    ) -> Bool {
        guard let token = currentToken(in: textBeforeCursor) else { return false }
        let word = token.trailingAutocompleteWord
        let candidate = correction.trailingAutocompleteWord
        guard !word.isEmpty, !candidate.isEmpty else { return false }

        let source = word.lowercased()
        let target = candidate.lowercased()
        guard source != target else { return false }

        let maximumDistance: Int
        switch source.count {
        case 0...5:
            maximumDistance = 1
        default:
            maximumDistance = 2
        }

        guard abs(source.count - target.count) <= maximumDistance else { return false }
        return editDistance(from: source, to: target) <= maximumDistance
    }

    private static func currentToken(in text: String?) -> String? {
        guard let text, text.last?.isWhitespace == false else { return nil }
        return text
            .split(whereSeparator: { $0.isWhitespace || $0.isNewline })
            .last
            .map(String.init)
    }

    private static func isProtectedToken(_ token: String) -> Bool {
        token.rangeOfCharacter(from: protectedTokenCharacters) != nil
            || token.contains(where: \.isNumber)
    }

    private static func isLikelyLatinIdentifierPrefix(_ token: String) -> Bool {
        guard token.count >= 2 else { return false }
        return token.unicodeScalars.allSatisfy { scalar in
            switch scalar.value {
            case 48...57, 65...90, 97...122, 45:
                true
            default:
                false
            }
        }
    }

    private static func editDistance(from source: String, to target: String) -> Int {
        let lhs = Array(source)
        let rhs = Array(target)
        guard !lhs.isEmpty else { return rhs.count }
        guard !rhs.isEmpty else { return lhs.count }

        var previous = Array(0...rhs.count)
        for (leftIndex, leftCharacter) in lhs.enumerated() {
            var current = Array(repeating: 0, count: rhs.count + 1)
            current[0] = leftIndex + 1

            for (rightIndex, rightCharacter) in rhs.enumerated() {
                let substitutionCost = leftCharacter == rightCharacter ? 0 : 1
                current[rightIndex + 1] = min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + substitutionCost
                )
            }
            previous = current
        }
        return previous[rhs.count]
    }

    private static func boundaryText(for action: KeyboardAction) -> String? {
        switch action {
        case .character(let value), .characterMargin(let value), .text(let value):
            value
        default:
            nil
        }
    }

    private static let protectedTokenCharacters = CharacterSet(
        charactersIn: "@._+/\\:#="
    )
    // Punctuation should finish the word the user actually typed, not accept
    // an autocorrect candidate. Autocorrection is still committed by space,
    // while `чм?`, names, codes and other unknown tokens remain untouched.
    private static let protectedBoundaryCharacters = CharacterSet(
        charactersIn: "@._+/\\:#=,!?;…()[]{}<>\"'“”‘’«»—–-"
    )
}

nonisolated private extension Keyboard.InputType {
    var prefersNaturalLanguageAutocomplete: Bool {
        switch self {
        case .text, .webSearch:
            true
        case .emailAddress, .url, .emojiSearch:
            false
        @unknown default:
            true
        }
    }
}

nonisolated private final class BudyStandardAutocompleteService: StandardAutocompleteService {
    override func shouldAutocorrect(_ word: String) -> Bool {
        let languageCode = LaynorPersonalDictionary.languageCode(for: locale)
        if LaynorPersonalDictionary.contains(word, languageCode: languageCode) {
            return false
        }

        guard BudyAutocorrectionPolicy.allowsAutocorrect(
            inputType: keyboardContext.keyboardInputType,
            textBeforeCursor: word,
            boundaryAction: .space
        ) else { return false }

        return super.shouldAutocorrect(word)
    }

    override func autocompleteSuggestions(
        for text: String
    ) async throws -> [AutocompleteSuggestion] {
        let suggestions = try await super.autocompleteSuggestions(for: text)
        return BudyPersonalAutocomplete.merge(
            suggestions,
            for: text.trailingAutocompleteWord,
            locale: locale
        )
    }

    override func nextWordPredictionResult(for text: String) async throws -> AutocompleteResult? {
        if let result = try? await super.nextWordPredictionResult(for: text),
           !result.suggestions.isEmpty {
            return result
        }

        let suggestions = BudyNextWordFallback.suggestions(for: text, locale: locale)
        guard !suggestions.isEmpty else { return nil }
        return AutocompleteResult(inputText: text, suggestions: suggestions)
    }
}

nonisolated private final class BudyAutocompleteService: AutocompleteService {
    var locale: Locale

    init(locale: Locale) {
        self.locale = locale
    }

    var canIgnoreWords: Bool { false }
    var canLearnWords: Bool { false }
    var ignoredWords: [String] { [] }
    var learnedWords: [String] { [] }

    func hasIgnoredWord(_ word: String) -> Bool { false }
    func hasLearnedWord(_ word: String) -> Bool { false }
    func ignoreWord(_ word: String) {}
    func learnWord(_ word: String) {}
    func removeIgnoredWord(_ word: String) {}
    func unlearnWord(_ word: String) {}

    func autocomplete(_ text: String) async throws -> AutocompleteResult {
        let word = text.trailingAutocompleteWord
        if word.isEmpty, text.last?.isWhitespace == true {
            return AutocompleteResult(
                inputText: text,
                suggestions: BudyNextWordFallback.suggestions(for: text, locale: locale)
            )
        }

        guard word.count >= 2 else {
            return AutocompleteResult(inputText: text, suggestions: [])
        }

        let language = locale.identifier
        let suggestions = await Self.makeSuggestions(for: word, language: language)
        return AutocompleteResult(inputText: text, suggestions: suggestions)
    }

    @MainActor
    private static func makeSuggestions(
        for word: String,
        language: String
    ) -> [AutocompleteSuggestion] {
        let checker = UITextChecker()
        let range = NSRange(location: 0, length: (word as NSString).length)
        let misspelled = checker.rangeOfMisspelledWord(
            in: word,
            range: range,
            startingAt: 0,
            wrap: false,
            language: language
        ).location != NSNotFound

        let guesses = misspelled
            ? checker.guesses(
                forWordRange: range,
                in: word,
                language: language
              ) ?? []
            : []
        let completions = checker.completions(
            forPartialWordRange: range,
            in: word,
            language: language
        ) ?? []

        var result = [
            AutocompleteSuggestion(
                text: word,
                type: .regular,
                title: "«\(word)»"
            )
        ]
        var used = Set([word.lowercased()])

        if let correction = guesses.first,
           used.insert(correction.lowercased()).inserted {
            result.append(
                AutocompleteSuggestion(text: correction, type: .autocorrect)
            )
        }

        for completion in completions + guesses.dropFirst() {
            guard result.count < 3 else { break }
            guard used.insert(completion.lowercased()).inserted else { continue }
            result.append(
                AutocompleteSuggestion(text: completion, type: .regular)
            )
        }

        return BudyPersonalAutocomplete.merge(
            result,
            for: word,
            locale: Locale(identifier: language)
        )
    }
}

nonisolated private enum BudyPersonalAutocomplete {
    static func merge(
        _ suggestions: [AutocompleteSuggestion],
        for input: String,
        locale: Locale
    ) -> [AutocompleteSuggestion] {
        guard !input.isEmpty else { return suggestions }
        let languageCode = LaynorPersonalDictionary.languageCode(for: locale)
        let personalWords = LaynorPersonalDictionary.suggestions(
            for: input,
            languageCode: languageCode,
            limit: 3
        )
        let inputKey = normalized(input, locale: locale)
        let isKnownWord = LaynorPersonalDictionary.contains(
            input,
            languageCode: languageCode
        )

        var baseSuggestions = suggestions
        if isKnownWord {
            baseSuggestions.removeAll(where: \.isAutocorrect)
        }

        var merged: [AutocompleteSuggestion] = []
        var used = Set<String>()

        if let original = baseSuggestions.first(where: {
            normalized($0.text.trailingAutocompleteWord, locale: locale) == inputKey
        }) {
            append(original, to: &merged, used: &used, locale: locale)
        }

        for entry in personalWords {
            let candidateKey = normalized(entry.word, locale: locale)
            guard candidateKey != inputKey else { continue }
            let type: AutocompleteSuggestionType = LaynorPersonalDictionary
                .isConfidentAutocorrection(entry, for: input)
                ? .autocorrect
                : .regular
            append(
                AutocompleteSuggestion(
                    text: entry.word,
                    type: type,
                    source: input,
                    additionalInfo: ["laynorPersonalWord": entry.id.uuidString]
                ),
                to: &merged,
                used: &used,
                locale: locale
            )
        }

        for suggestion in baseSuggestions {
            append(suggestion, to: &merged, used: &used, locale: locale)
        }

        return Array(merged.prefix(3))
    }

    private static func append(
        _ suggestion: AutocompleteSuggestion,
        to result: inout [AutocompleteSuggestion],
        used: inout Set<String>,
        locale: Locale
    ) {
        let key = normalized(suggestion.text, locale: locale)
        guard !key.isEmpty, used.insert(key).inserted else { return }
        result.append(suggestion)
    }

    private static func normalized(_ value: String, locale: Locale) -> String {
        value.folding(options: [.diacriticInsensitive], locale: locale)
            .lowercased(with: locale)
    }
}

nonisolated private enum BudyNextWordFallback {
    static func suggestions(for text: String, locale: Locale) -> [AutocompleteSuggestion] {
        guard text.last?.isWhitespace == true else { return [] }

        let words = text
            .lowercased()
            .split { !$0.isLetter && $0 != "-" && $0 != "'" && $0 != "’" }
            .map(String.init)
        guard let lastWord = words.last else { return [] }

        let language = locale.language.languageCode?.identifier
        let variants: [String]
        switch language {
        case "ru":
            variants = russian[lastWord] ?? russianDefault
        case "es":
            variants = spanish[lastWord] ?? spanishDefault
        default:
            variants = english[lastWord] ?? englishDefault
        }

        return variants.prefix(3).map {
            AutocompleteSuggestion(text: $0, type: .regular)
        }
    }

    private static let russian: [String: [String]] = [
        "а": ["что", "если", "как"],
        "в": ["общем", "этом", "том"],
        "вы": ["можете", "знаете", "хотите"],
        "да": ["это", "конечно", "всё"],
        "для": ["этого", "меня", "того"],
        "если": ["это", "нужно", "будет"],
        "и": ["это", "тогда", "ещё"],
        "как": ["это", "будто", "можно"],
        "мне": ["кажется", "нужно", "нравится"],
        "можно": ["сделать", "будет", "ли"],
        "мы": ["можем", "будем", "должны"],
        "на": ["самом", "этом", "следующей"],
        "не": ["знаю", "нужно", "могу"],
        "но": ["это", "если", "пока"],
        "он": ["может", "был", "уже"],
        "она": ["может", "была", "уже"],
        "так": ["что", "как", "и"],
        "у": ["меня", "нас", "вас"],
        "что": ["это", "можно", "нужно"],
        "это": ["очень", "можно", "было"],
        "я": ["думаю", "хочу", "могу"]
    ]

    private static let english: [String: [String]] = [
        "and": ["then", "I", "the"],
        "are": ["you", "the", "we"],
        "can": ["you", "we", "be"],
        "for": ["the", "this", "you"],
        "how": ["are", "do", "can"],
        "i": ["think", "want", "can"],
        "if": ["you", "we", "it"],
        "in": ["the", "this", "a"],
        "is": ["the", "it", "a"],
        "it": ["is", "was", "can"],
        "not": ["sure", "only", "yet"],
        "of": ["the", "this", "course"],
        "that": ["is", "you", "we"],
        "the": ["same", "best", "new"],
        "to": ["the", "be", "make"],
        "we": ["can", "need", "should"],
        "what": ["is", "do", "you"],
        "you": ["can", "are", "need"]
    ]

    private static let spanish: [String: [String]] = [
        "de": ["la", "los", "esta"],
        "el": ["mismo", "texto", "día"],
        "en": ["el", "la", "este"],
        "es": ["muy", "una", "el"],
        "la": ["misma", "primera", "información"],
        "me": ["parece", "gustaría", "puedes"],
        "no": ["sé", "puedo", "es"],
        "para": ["que", "el", "poder"],
        "podemos": ["hacerlo", "hablar", "ver"],
        "por": ["favor", "eso", "ahora"],
        "que": ["es", "no", "puede"],
        "si": ["quieres", "es", "puedes"],
        "un": ["poco", "nuevo", "buen"],
        "una": ["vez", "forma", "buena"],
        "y": ["también", "el", "la"],
        "yo": ["creo", "quiero", "puedo"]
    ]

    private static let russianDefault = ["и", "в", "не"]
    private static let englishDefault = ["the", "and", "to"]
    private static let spanishDefault = ["de", "la", "que"]
}

private extension String {
    nonisolated var trailingAutocompleteWord: String {
        String(reversed().prefix { character in
            character.isLetter || character == "-" || character == "'" || character == "’"
        }.reversed())
    }
}

private extension KeyboardApp {
    static var laynor: KeyboardApp {
        .init(
            name: "Laynor",
            appGroupId: "group.Tim.BudyAI",
            locales: [
                Locale(identifier: "ru_RU"),
                Locale(identifier: "en_US"),
                Locale(identifier: "es_ES")
            ]
        )
    }
}
