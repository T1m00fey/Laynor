import KeyboardKit
import Combine
import SwiftUI

enum KeyboardRewriteResult {
    case success
    case failure(String)
}

enum KeyboardReminderParseResult {
    case success(LaynorReminderDraft)
    case failure(String)
}

enum KeyboardReminderScheduleResult {
    case success
    case failure(String)
}

nonisolated final class KeyboardCommandContext: ObservableObject {
    private enum SubmissionState {
        case idle
        case loading
        case success
        case failure(String)
    }

    static let maximumLength = 200

    let objectWillChange = ObservableObjectPublisher()
    private(set) var isActive = false
    private(set) var text = ""
    private var submissionState: SubmissionState = .idle
    private var submissionHandler: ((String) -> Void)?

    var isSubmitting: Bool {
        if case .loading = submissionState { return true }
        return false
    }

    var errorMessage: String? {
        if case .failure(let message) = submissionState { return message }
        return nil
    }

    var isCompleted: Bool {
        if case .success = submissionState { return true }
        return false
    }

    func setSubmissionHandler(_ handler: @escaping (String) -> Void) {
        submissionHandler = handler
    }

    func begin() {
        objectWillChange.send()
        text = ""
        submissionState = .idle
        isActive = true
    }

    func cancel() {
        objectWillChange.send()
        text = ""
        submissionState = .idle
        isActive = false
    }

    func append(_ value: String) {
        guard isActive, !value.isEmpty else { return }
        let available = Self.maximumLength - text.count
        guard available > 0 else { return }
        objectWillChange.send()
        submissionState = .idle
        text.append(contentsOf: value.prefix(available))
    }

    func deleteBackward() {
        guard isActive, !text.isEmpty else { return }
        objectWillChange.send()
        submissionState = .idle
        text.removeLast()
    }

    func requestSubmission() {
        let instruction = trimmedText
        guard !instruction.isEmpty, !isSubmitting, !isCompleted else { return }
        objectWillChange.send()
        submissionState = .loading
        submissionHandler?(instruction)
    }

    func completeSubmission(with result: KeyboardRewriteResult?) {
        switch result {
        case .success:
            objectWillChange.send()
            submissionState = .success
        case .failure(let message):
            objectWillChange.send()
            submissionState = .failure(message)
        case .none:
            objectWillChange.send()
            submissionState = .failure("keyboard.command.failed".localizedString())
        }
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
final class KeyboardEditHistory: ObservableObject {
    @Published private(set) var canUndo = false
    @Published private(set) var canRedo = false

    func showGeneratedState() {
        canUndo = true
        canRedo = false
    }

    func showOriginalState() {
        canUndo = false
        canRedo = true
    }

    func clear() {
        canUndo = false
        canRedo = false
    }
}

nonisolated final class KeyboardInteractionContext: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    private(set) var isRepeatingBackspace = false

    func beginRepeatingBackspace() {
        guard !isRepeatingBackspace else { return }
        objectWillChange.send()
        isRepeatingBackspace = true
    }

    func endRepeatingBackspace() {
        guard isRepeatingBackspace else { return }
        objectWillChange.send()
        isRepeatingBackspace = false
    }
}

enum KeyboardRewriteStyle: String, CaseIterable, Identifiable {
    case rewrite, correct, concise, professional

    var id: String { rawValue }

    var title: String {
        switch self {
        case .rewrite: "keyboard.action.rewrite".localizedString()
        case .correct: "keyboard.action.correct".localizedString()
        case .concise: "keyboard.action.concise".localizedString()
        case .professional: "keyboard.action.professional".localizedString()
        }
    }

    var icon: String {
        switch self {
        case .rewrite: "wand.and.stars"
        case .correct: "checkmark.circle.fill"
        case .concise: "scissors"
        case .professional: "briefcase.fill"
        }
    }
}

extension KeyboardAction {
    static var budyLocaleSwitch: KeyboardAction {
        .custom(named: "budyLocaleSwitch")
    }
}

struct BudyKeyboardView: View {
    let services: KeyboardServices
    let state: KeyboardState
    let editHistory: KeyboardEditHistory
    let commandContext: KeyboardCommandContext
    let interactionContext: KeyboardInteractionContext
    let onRewrite: (KeyboardRewriteStyle) async -> KeyboardRewriteResult?
    let onParseReminder: () async -> KeyboardReminderParseResult
    let onScheduleReminder: (
        LaynorReminderDraft,
        @escaping (KeyboardReminderScheduleResult) -> Void
    ) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onInsertSavedItem: (LaynorSavedItem) -> Void

    @State private var isShowingSavedItems = false
    @ObservedObject private var keyboardContext: KeyboardContext

    init(
        services: KeyboardServices,
        state: KeyboardState,
        editHistory: KeyboardEditHistory,
        commandContext: KeyboardCommandContext,
        interactionContext: KeyboardInteractionContext,
        onRewrite: @escaping (KeyboardRewriteStyle) async -> KeyboardRewriteResult?,
        onParseReminder: @escaping () async -> KeyboardReminderParseResult,
        onScheduleReminder: @escaping (
            LaynorReminderDraft,
            @escaping (KeyboardReminderScheduleResult) -> Void
        ) -> Void,
        onUndo: @escaping () -> Void,
        onRedo: @escaping () -> Void,
        onInsertSavedItem: @escaping (LaynorSavedItem) -> Void
    ) {
        self.services = services
        self.state = state
        self.editHistory = editHistory
        self.commandContext = commandContext
        self.interactionContext = interactionContext
        self.onRewrite = onRewrite
        self.onParseReminder = onParseReminder
        self.onScheduleReminder = onScheduleReminder
        self.onUndo = onUndo
        self.onRedo = onRedo
        self.onInsertSavedItem = onInsertSavedItem
        _keyboardContext = ObservedObject(wrappedValue: state.keyboardContext)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // Keep the regular keyboard in the layout so switching to a
            // short saved-items list cannot reduce the extension height.
            keyboardBody
                .opacity(isShowingSavedItems ? 0 : 1)
                .allowsHitTesting(!isShowingSavedItems)

            if isShowingSavedItems {
                SavedItemsKeyboardView(
                    onClose: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isShowingSavedItems = false
                        }
                    },
                    onInsert: onInsertSavedItem
                )
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .top).combined(with: .opacity),
                        removal: .move(edge: .top).combined(with: .opacity)
                    )
                )
            }
        }
    }

    private var keyboardBody: some View {
        KeyboardView(
            layout: keyboardLayout,
            services: services,
            buttonContent: { $0.view },
            buttonView: { params in
                // Keep KeyboardKit's layout wrapper so fixed and available
                // widths in the bottom row are respected. Only replace the
                // rendered key and its press feedback.
                params.view
                    .hidden()
                    .allowsHitTesting(false)
                    .overlay {
                        BudyFastKeyboardButton(
                            item: params.item,
                            services: services,
                            state: state,
                            locale: keyboardContext.locale
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
            },
            collapsedView: { $0.view },
            emojiKeyboard: { $0.view },
            toolbar: { params in
                BudyToolbar(
                    keyboardContext: keyboardContext,
                    autocompleteContext: state.autocompleteContext,
                    editHistory: editHistory,
                    commandContext: commandContext,
                    interactionContext: interactionContext,
                    services: services,
                    autocompleteAction: params.autocompleteAction,
                    onRewrite: onRewrite,
                    onParseReminder: onParseReminder,
                    onScheduleReminder: onScheduleReminder,
                    onUndo: onUndo,
                    onRedo: onRedo,
                    onToggleSavedItems: {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                            isShowingSavedItems = true
                        }
                    }
                )
            }
        )
        .keyboardToolbarStyle(
            .init(
                backgroundColor: .clear,
                height: 40,
                minHeight: 40,
                maxHeight: 40
            )
        )
        .keyboardCalloutActions { params in
            guard case .character(let character) = params.action else {
                return params.standardActions()
            }

            let isUppercase = params.context.keyboardCase.isUppercasedOrCapslocked
            let lowercased = character.lowercased()

            if currentKeyboardLanguageCode == "ru", lowercased == "ь" {
                return [
                    .character(isUppercase ? "Ь" : "ь"),
                    .character(isUppercase ? "Ъ" : "ъ")
                ]
            }

            if currentKeyboardLanguageCode == "es",
               let variants = spanishCalloutVariants[lowercased] {
                return variants.map {
                    .character(isUppercase ? $0.uppercased() : $0)
                }
            }

            return params.standardActions()
        }
        .onChange(of: keyboardContext.locale) { _, locale in
            services.autocompleteService.locale = locale
        }
    }

    private var currentKeyboardLanguageCode: String {
        keyboardContext.locale.language.languageCode?.identifier ?? "en"
    }
}

private struct BudyFastKeyboardButton: View {
    let item: KeyboardLayoutItem
    let services: KeyboardServices
    let state: KeyboardState
    let locale: Locale

    @Environment(\.colorScheme) private var colorScheme
    @State private var isPressed = false
    @State private var isVisuallyPressed = false
    @State private var visualReleaseTask: Task<Void, Never>?

    var body: some View {
        Keyboard.Button(
            action: handledAction,
            actionHandler: services.actionHandler,
            repeatTimer: services.repeatGestureTimer,
            calloutContext: needsSecondaryCallout ? state.calloutContext : nil,
            edgeInsets: item.edgeInsets,
            isPressed: $isPressed
        ) { standardContent in
            keyLabel(standardContent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(keySurface)
                .contentShape(RoundedRectangle(cornerRadius: 8.5, style: .continuous))
        }
        .scaleEffect(isVisuallyPressed ? 0.94 : 1)
        .animation(
            .easeOut(duration: isVisuallyPressed ? 0.045 : 0.13),
            value: isVisuallyPressed
        )
        .onChange(of: isPressed) { _, pressed in
            visualReleaseTask?.cancel()

            if pressed {
                isVisuallyPressed = true
            } else {
                visualReleaseTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(75))
                    guard !Task.isCancelled else { return }
                    isVisuallyPressed = false
                }
            }
        }
        .onDisappear {
            visualReleaseTask?.cancel()
        }
    }

    private var keySurface: some View {
        let shape = RoundedRectangle(cornerRadius: 8.5, style: .continuous)
        return shape
            .fill(keyFillColor)
            .overlay {
                shape.fill(Color.white.opacity(isVisuallyPressed ? 0.30 : 0))
            }
            .overlay {
                shape.stroke(
                    Color.white.opacity(
                        isVisuallyPressed
                            ? (colorScheme == .dark ? 0.32 : 0.76)
                            : (colorScheme == .dark ? 0.08 : 0.12)
                    ),
                    lineWidth: isVisuallyPressed ? 0.8 : 0.5
                )
            }
    }

    private var keyFillColor: Color {
        if colorScheme == .dark {
            return isVisuallyPressed
                ? Color(red: 0.29, green: 0.29, blue: 0.30)
                : Color(red: 0.235, green: 0.235, blue: 0.245)
        }
        return Color.white.opacity(isVisuallyPressed ? 0.66 : 0.46)
    }

    @ViewBuilder
    private func keyLabel<Content: View>(_ content: Content) -> some View {
        switch item.action {
        case .character(let character):
            Text(character)
                .font(.system(size: 21, weight: .regular, design: .default))

        case .space:
            ZStack(alignment: .bottomTrailing) {
                Color.clear
                Text(spaceLanguageLabel)
                    .font(.system(size: 10, weight: .regular, design: .default))
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 7)
                    .padding(.bottom, 3)
            }

        case .shift(let keyboardCase):
            Image(systemName: keyboardCase.isUppercasedOrCapslocked ? "shift.fill" : "shift")
                .font(.system(size: 15, weight: .medium))

        case .backspace:
            Image(systemName: "delete.left")
                .font(.system(size: 17, weight: .medium))

        case .budyLocaleSwitch:
            // Show the layout that will be activated by the tap. The current
            // layout is already indicated on the spacebar.
            Text(locale.language.languageCode?.identifier == "ru" ? "EN" : "РУ")
                .font(.system(size: 14, weight: .semibold))

        default:
            content
        }
    }

    private var spaceLanguageLabel: String {
        switch locale.language.languageCode?.identifier {
        case "ru": "ру"
        case "es": "es"
        default: "en"
        }
    }

    private var handledAction: KeyboardAction {
        item.action
    }

    private var needsSecondaryCallout: Bool {
        guard case .character(let character) = item.action else { return false }
        let lowercased = character.lowercased()
        if locale.language.languageCode?.identifier == "ru" {
            return lowercased == "ь"
        }
        if locale.language.languageCode?.identifier == "es" {
            return spanishCalloutVariants[lowercased] != nil
        }
        return false
    }
}

private extension BudyKeyboardView {
    var keyboardLayout: KeyboardLayout {
        var layout = KeyboardLayout.standard(for: keyboardContext)
        let standardInsets = layout.configuration.edgeInsets
        layout.configuration.edgeInsets = EdgeInsets(
            top: standardInsets.top,
            leading: 4,
            bottom: standardInsets.bottom,
            trailing: 4
        )
        // The custom toolbar used to add about 10pt compared with the native
        // iOS prediction strip. Keep it inside the same compact slot.
        // Give the toolbar a real 40pt slot, then compensate across the four
        // key rows so the complete keyboard keeps the same reported height.
        layout.configuration.inputToolbarHeight = 40
        layout.configuration.rowHeight -= 2.5

        if keyboardContext.keyboardType.isAlphabetic,
           LaynorLocalization.keyboardLanguageCode == "ru" {
            let localeAction = KeyboardAction.budyLocaleSwitch
            if layout.bottomRow?.contains(where: { $0.action == localeAction }) != true {
                let bottomRowIndex = layout.itemRows.count - 1
                var bottomRow = layout.itemRows[bottomRowIndex]
                if let template = bottomRow.first {
                    var localeItem = layout.createIdealItem(
                        for: localeAction,
                        width: .points(42)
                    )
                    localeItem.size = .init(
                        width: .points(42),
                        height: template.size.height
                    )
                    localeItem.edgeInsets = template.edgeInsets
                    bottomRow.insert(localeItem, at: min(1, bottomRow.count))
                    layout.itemRows[bottomRowIndex] = bottomRow
                }
            }
        }

        guard keyboardContext.keyboardType.isAlphabetic,
              let characterRows else { return layout }

        let letters = characterRows.map { row in
            row.map { letter in
                layout.createIdealItem(
                    for: .character(cased(letter)),
                    width: .input
                )
            }
        }

        guard layout.itemRows.count >= 4 else { return layout }

        let shift = layout.createIdealItem(
            for: .shift(keyboardContext.keyboardCase),
            width: .input
        )
        let backspace = layout.createIdealItem(for: .backspace, width: .input)
        let thirdRow = [shift] + letters[2] + [backspace]

        layout.itemRows = [
            letters[0],
            letters[1],
            thirdRow,
            layout.itemRows[layout.itemRows.count - 1]
        ]
        return layout
    }

    var characterRows: [[String]]? {
        switch currentKeyboardLanguageCode {
        case "ru": [
            ["й", "ц", "у", "к", "е", "н", "г", "ш", "щ", "з", "х"],
            ["ф", "ы", "в", "а", "п", "р", "о", "л", "д", "ж", "э"],
            ["я", "ч", "с", "м", "и", "т", "ь", "б", "ю"]
        ]
        case "es": [
            ["q", "w", "e", "r", "t", "y", "u", "i", "o", "p"],
            ["a", "s", "d", "f", "g", "h", "j", "k", "l", "ñ"],
            ["z", "x", "c", "v", "b", "n", "m"]
        ]
        default: nil
        }
    }

    func cased(_ letter: String) -> String {
        let locale = keyboardContext.locale
        return keyboardContext.keyboardCase.isUppercasedOrCapslocked
            ? letter.uppercased(with: locale)
            : letter.lowercased(with: locale)
    }
}

private let spanishCalloutVariants: [String: [String]] = [
    "a": ["a", "á"],
    "e": ["e", "é"],
    "i": ["i", "í"],
    "n": ["n", "ñ"],
    "o": ["o", "ó"],
    "u": ["u", "ú", "ü"]
]

private struct SavedItemsKeyboardView: View {
    let onClose: () -> Void
    let onInsert: (LaynorSavedItem) -> Void

    @State private var items: [LaynorSavedItem] = []
    @State private var isContentVisible = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("keyboard.saved.title".localizedString())
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "keyboard")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 38, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("keyboard.saved.close".localizedString())
            }
            .padding(.horizontal, 14)
            .frame(height: 44)

            if items.isEmpty {
                ContentUnavailableView(
                    "keyboard.saved.empty.title".localizedString(),
                    systemImage: "bookmark",
                    description: Text("keyboard.saved.empty.subtitle".localizedString())
                )
            } else {
                ScrollView {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 145), spacing: 8)],
                        spacing: 8
                    ) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            Button {
                                LaynorSavedItemsStore.recordSelection(item)
                                onInsert(item)
                            } label: {
                                HStack(spacing: 9) {
                                    Image(systemName: item.kind.icon)
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 20)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.title.isEmpty ? item.value : item.title)
                                            .font(.system(size: 14, weight: .semibold))
                                            .lineLimit(1)
                                        if !item.title.isEmpty {
                                            Text(item.value)
                                                .font(.system(size: 11))
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 10)
                                .frame(height: 50)
                                .background(
                                    Color(uiColor: .systemBackground).opacity(0.48),
                                    in: RoundedRectangle(cornerRadius: 10, style: .continuous)
                                )
                            }
                            .buttonStyle(.plain)
                            .environment(\.layoutDirection, .leftToRight)
                            .opacity(isContentVisible ? 1 : 0)
                            .offset(y: isContentVisible ? 0 : 9)
                            .scaleEffect(isContentVisible ? 1 : 0.97)
                            .animation(
                                .spring(response: 0.34, dampingFraction: 0.84)
                                    .delay(Double(index) * 0.035),
                                value: isContentVisible
                            )
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.bottom, 8)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.primary)
        .onAppear {
            refresh()
            isContentVisible = false
            DispatchQueue.main.async {
                isContentVisible = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSavedItemsDidChange)) { _ in
            refresh()
        }
    }

    private func refresh() {
        items = LaynorSavedItemsStore.all()
    }
}

private struct BudyToolbar: View {
    @ObservedObject var keyboardContext: KeyboardContext
    @ObservedObject var autocompleteContext: AutocompleteContext
    @ObservedObject var editHistory: KeyboardEditHistory
    @ObservedObject var commandContext: KeyboardCommandContext
    @ObservedObject var interactionContext: KeyboardInteractionContext
    let services: KeyboardServices
    let autocompleteAction: (AutocompleteSuggestion) -> Void
    let onRewrite: (KeyboardRewriteStyle) async -> KeyboardRewriteResult?
    let onParseReminder: () async -> KeyboardReminderParseResult
    let onScheduleReminder: (
        LaynorReminderDraft,
        @escaping (KeyboardReminderScheduleResult) -> Void
    ) -> Void
    let onUndo: () -> Void
    let onRedo: () -> Void
    let onToggleSavedItems: () -> Void

    @State private var isShowingAI = false
    @State private var isRewriting = false
    @State private var selectedStyle: KeyboardRewriteStyle?
    @State private var message: String?
    @State private var isSuccessMessage = false
    @State private var reminderDraft: LaynorReminderDraft?
    @State private var isPreparingReminder = false
    @State private var isSchedulingReminder = false
    @State private var toolbarShakeProgress: CGFloat = 0
    @State private var isCommandCursorVisible = true

    var body: some View {
        ZStack {
            if let reminderDraft {
                reminderConfirmation(reminderDraft)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            } else if commandContext.isActive {
                commandInput
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: 18, y: 0)
                                .combined(with: .scale(scale: 0.96, anchor: .trailing))
                                .combined(with: .opacity),
                            removal: .offset(x: 10, y: 0)
                                .combined(with: .scale(scale: 0.98, anchor: .trailing))
                                .combined(with: .opacity)
                        )
                    )
            } else {
                HStack(spacing: 7) {
                    brandButton
                    historyButtons
                    savedItemsButton

                    ZStack(alignment: .leading) {
                        if canShowT9 {
                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    t9ToolbarContent
                                        .frame(width: geometry.size.width)
                                        .opacity(isShowingAI ? 0 : 1)
                                        .allowsHitTesting(!isShowingAI)
                                        .animation(
                                            isShowingAI
                                                ? .easeOut(duration: 0.14)
                                                : .easeIn(duration: 0.2).delay(0.18),
                                            value: isShowingAI
                                        )

                                    aiToolbarContent
                                        .frame(width: geometry.size.width)
                                        .offset(
                                            x: isShowingAI
                                                ? 0
                                                : -geometry.size.width
                                        )
                                        .allowsHitTesting(isShowingAI)
                                        .animation(
                                            .spring(response: 0.46, dampingFraction: 0.9),
                                            value: isShowingAI
                                        )
                                }
                            }
                        } else {
                            aiToolbarContent
                                .id("ai-empty-t9-toolbar")
                                .transition(.opacity)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .clipped()
                    .modifier(BudyToolbarShakeEffect(progress: toolbarShakeProgress))
                    .animation(.easeInOut(duration: 0.24), value: canShowT9)

                    if isRewriting || isPreparingReminder {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 22)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .offset(x: -10, y: 0)
                            .combined(with: .scale(scale: 0.98, anchor: .leading))
                            .combined(with: .opacity),
                        removal: .offset(x: -16, y: 0)
                            .combined(with: .scale(scale: 0.97, anchor: .leading))
                            .combined(with: .opacity)
                    )
                )
            }
        }
        .animation(
            .spring(response: 0.34, dampingFraction: 0.86),
            value: commandContext.isActive || reminderDraft != nil
        )
        .padding(.horizontal, 8)
        // A real 40pt container gives the 30pt controls 5pt of breathing room
        // above and below. This avoids clipping by host apps that clip the
        // toolbar to its declared height.
        .frame(height: 40, alignment: .center)
        .offset(y: 1)
    }

    private func reminderConfirmation(_ draft: LaynorReminderDraft) -> some View {
        HStack(spacing: 7) {
            Button {
                guard !isSchedulingReminder else { return }
                reminderDraft = nil
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .frame(width: 34, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isSchedulingReminder)
            .accessibilityLabel("keyboard.reminder.cancel".localizedString())

            VStack(alignment: .leading, spacing: 1) {
                Text(draft.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(reminderDateText(draft.fireDate))
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(toolbarCapsule)

            Group {
                if isSchedulingReminder {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.white)
                } else {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
                .frame(width: 30, height: 30)
                .background(Color.black.opacity(0.9), in: Circle())
                .contentShape(Circle())
                // This intentionally isn't a SwiftUI Button. In several host
                // apps its button gesture was forwarded into KeyboardKit and
                // iOS replaced the extension with the system keyboard.
                .onTapGesture {
                    confirmReminder(draft)
                }
                .accessibilityElement()
                .accessibilityAddTraits(.isButton)
                .accessibilityLabel("keyboard.reminder.confirm".localizedString())
        }
        .padding(.horizontal, 8)
    }

    private func reminderDateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = keyboardContext.locale
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var commandInput: some View {
        HStack(spacing: 6) {
            Button {
                guard !commandContext.isSubmitting else { return }
                message = nil
                commandContext.cancel()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    // Keep the glyph compact, but use Apple's recommended
                    // touch width so quick taps around it aren't missed.
                    .frame(width: 44, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(commandContext.isSubmitting)

            HStack(spacing: 7) {
                Image(systemName: "text.cursor")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 0) {
                            commandTextContent

                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("commandInputEnd")
                        }
                        .font(.system(size: 13, weight: .medium))
                        .frame(minWidth: 1, alignment: .leading)
                    }
                    .onChange(of: commandContext.text) { _, _ in
                        proxy.scrollTo("commandInputEnd", anchor: .trailing)
                    }
                }

                if commandContext.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity.combined(with: .scale(scale: 0.88)))
                } else if commandContext.isCompleted {
                    HStack(spacing: 4) {
                        Text("keyboard.status.done".localizedString())
                        Image(systemName: "checkmark.circle.fill")
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(red: 0.40, green: 0.46, blue: 0.91))
                    .fixedSize()
                    .transition(
                        .asymmetric(
                            insertion: .offset(x: 8)
                                .combined(with: .scale(scale: 0.9, anchor: .trailing))
                                .combined(with: .opacity),
                            removal: .offset(x: 5)
                                .combined(with: .scale(scale: 0.96, anchor: .trailing))
                                .combined(with: .opacity)
                        )
                    )
                } else {
                    Text("\(commandContext.text.count)/\(KeyboardCommandContext.maximumLength)")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .background(toolbarCapsule)

            Button {
                commandContext.requestSubmission()
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle().fill(
                            canSubmitCustomCommand
                                ? Color.black.opacity(0.9)
                                : Color.black.opacity(0.24)
                            )
                        )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .disabled(!canSubmitCustomCommand)
        }
        .onAppear {
            startCommandCursorAnimation()
        }
        .onChange(of: commandContext.isCompleted) { _, isCompleted in
            guard isCompleted else { return }

            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(1_250))
                guard commandContext.isCompleted else { return }
                commandContext.cancel()
            }
        }
        .animation(
            .spring(response: 0.32, dampingFraction: 0.84),
            value: commandContext.isCompleted
        )
    }

    @ViewBuilder
    private var commandTextContent: some View {
        if let error = commandContext.errorMessage {
            Text(error)
                .foregroundStyle(.primary)
        } else if commandContext.text.isEmpty {
            commandCursor
            Text("keyboard.command.placeholder".localizedString())
                .foregroundStyle(.secondary)
        } else {
            Text(commandContext.text)
                .foregroundStyle(.primary)
            commandCursor
        }
    }

    private var commandCursor: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(Color.primary)
            .frame(width: 1.5, height: 17)
            .offset(x: commandContext.text.isEmpty ? 0 : -0.5)
            .opacity(isCommandCursorVisible ? 1 : 0.12)
    }

    private func startCommandCursorAnimation() {
        isCommandCursorVisible = true
        withAnimation(.easeInOut(duration: 0.52).repeatForever(autoreverses: true)) {
            isCommandCursorVisible = false
        }
    }

    private var canSubmitCustomCommand: Bool {
        !commandContext.isSubmitting
            && !commandContext.isCompleted
            && !commandContext.trimmedText.isEmpty
    }

    private var brandButton: some View {
        Button {
            guard canShowT9 else {
                withAnimation(.linear(duration: 0.3)) {
                    toolbarShakeProgress += 1
                }
                return
            }

            isShowingAI.toggle()
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.black.opacity(0.9))
                Image(systemName: isShowingAI && canShowT9 ? "keyboard" : "sparkles")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color(red: 0.46, green: 0.54, blue: 1.0))
            }
            .frame(width: 30, height: 30)
            .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(brandButtonAccessibilityLabel)
    }

    private var brandButtonAccessibilityLabel: String {
        guard canShowT9 else {
            return "keyboard.accessibility.tools_open".localizedString()
        }
        return isShowingAI
            ? "keyboard.accessibility.show_suggestions".localizedString()
            : "keyboard.accessibility.show_tools".localizedString()
    }

    private var savedItemsButton: some View {
        Button(action: onToggleSavedItems) {
            Image(systemName: "bookmark")
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .background(toolbarCapsule)
        .accessibilityLabel("keyboard.saved.open".localizedString())
    }

    private var historyButtons: some View {
        HStack(spacing: 0) {
            historyButton(
                systemName: "arrow.uturn.backward",
                isEnabled: editHistory.canUndo,
                accessibilityLabel: "keyboard.accessibility.undo".localizedString(),
                action: onUndo
            )

            Divider()
                .frame(height: 18)
                .opacity(0.24)

            historyButton(
                systemName: "arrow.uturn.forward",
                isEnabled: editHistory.canRedo,
                accessibilityLabel: "keyboard.accessibility.redo".localizedString(),
                action: onRedo
            )
        }
        .frame(width: 68, height: 30)
        .background(toolbarCapsule)
    }

    private func historyButton(
        systemName: String,
        isEnabled: Bool,
        accessibilityLabel: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 13, weight: .semibold))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.28)
        .accessibilityLabel(accessibilityLabel)
    }

    private var t9ToolbarContent: some View {
        let suggestions = visibleT9Suggestions

        return HStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { index in
                ZStack {
                    if suggestions.indices.contains(index) {
                        let suggestion = suggestions[index]
                        Button {
                            autocompleteAction(suggestion)
                        } label: {
                            Text(suggestion.title)
                                .font(.system(
                                    size: 15,
                                    weight: suggestion.isAutocorrect ? .semibold : .regular
                                ))
                                .lineLimit(1)
                                .minimumScaleFactor(0.72)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    } else {
                        Color.clear
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if index < 2 {
                    Divider()
                        .frame(height: 21)
                        .opacity(0.32)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var hasT9Suggestions: Bool {
        !visibleT9Suggestions.isEmpty
    }

    private var canShowT9: Bool {
        hasT9Suggestions && !interactionContext.isRepeatingBackspace
    }

    private var visibleT9Suggestions: [AutocompleteSuggestion] {
        Array(
            autocompleteContext.suggestions
                .filter { !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                .prefix(3)
        )
    }

    @ViewBuilder
    private var aiToolbarContent: some View {
        if !keyboardContext.hasFullAccess {
            Label("keyboard.full_access.allow".localizedString(), systemImage: "lock.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.46, blue: 0.91))
                .frame(maxWidth: .infinity)
        } else if let message {
            if isSuccessMessage {
                HStack(spacing: 5) {
                    Text(message)
                    Image(systemName: "checkmark.circle.fill")
                }
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(red: 0.40, green: 0.46, blue: 0.91))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.trailing, 4)
                .transition(
                    .asymmetric(
                        insertion: .offset(x: 10)
                            .combined(with: .scale(scale: 0.92, anchor: .trailing))
                            .combined(with: .opacity),
                        removal: .offset(x: 14)
                            .combined(with: .scale(scale: 0.97, anchor: .trailing))
                            .combined(with: .opacity)
                    )
                )
            } else {
                Text(message)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .transition(.opacity)
            }
        } else {
            styleButtons
                .transition(.opacity)
        }
    }

    private var styleButtons: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                Button {
                    message = nil
                    commandContext.begin()
                } label: {
                    Label("keyboard.command.custom".localizedString(), systemImage: "text.cursor")
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 13)
                        .frame(height: 30)
                        .contentShape(Capsule())
                }
                .foregroundStyle(.primary)
                .background(toolbarCapsule)
                .buttonStyle(.plain)
                .disabled(isRewriting || isPreparingReminder)

                ForEach(KeyboardRewriteStyle.allCases) { style in
                    Button {
                        rewrite(style)
                    } label: {
                        Label(style.title, systemImage: style.icon)
                            .font(.system(size: 13, weight: .semibold))
                            .padding(.horizontal, 13)
                            .frame(height: 30)
                            .contentShape(Capsule())
                    }
                    .foregroundStyle(.primary)
                    .background(toolbarCapsule)
                    .buttonStyle(.plain)
                    .disabled(isRewriting || isPreparingReminder)
                }
            }
        }
    }

    private var toolbarCapsule: some View {
        Capsule()
            .fill(Color(uiColor: .systemBackground).opacity(0.38))
    }

    private func rewrite(_ style: KeyboardRewriteStyle) {
        guard !isRewriting else { return }
        isRewriting = true
        selectedStyle = style
        message = nil
        isSuccessMessage = false

        Task { @MainActor in
            let result = await onRewrite(style)
            switch result {
            case .success:
                withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                    selectedStyle = nil
                    isRewriting = false
                    isSuccessMessage = true
                    message = "keyboard.status.done".localizedString()
                }
                try? await Task.sleep(for: .milliseconds(1_350))
                // Dismiss the status first, while the AI toolbar is still in
                // place. Otherwise the toolbar's own left slide overrides the
                // status transition and makes "Готово" leave to the left.
                withAnimation(.easeOut(duration: 0.28)) {
                    message = nil
                }
                try? await Task.sleep(for: .milliseconds(300))
                isSuccessMessage = false
                withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                    isShowingAI = false
                }
            case .failure(let error):
                withAnimation(.easeInOut(duration: 0.2)) {
                    selectedStyle = nil
                    isRewriting = false
                    isSuccessMessage = false
                    message = error
                }
                try? await Task.sleep(for: .seconds(2))
                withAnimation(.easeOut(duration: 0.22)) {
                    message = nil
                }
            case .none:
                selectedStyle = nil
                isRewriting = false
                break
            }
        }
    }

    private func prepareReminder() {
        guard !isPreparingReminder, !isRewriting else { return }
        isPreparingReminder = true
        message = nil
        isSuccessMessage = false

        Task { @MainActor in
            let result = await onParseReminder()
            isPreparingReminder = false

            switch result {
            case .success(let draft):
                withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                    reminderDraft = draft
                }
            case .failure(let error):
                showReminderError(error)
            }
        }
    }

    private func confirmReminder(_ draft: LaynorReminderDraft) {
        guard !isSchedulingReminder else { return }
        isSchedulingReminder = true

        onScheduleReminder(draft) { result in
            DispatchQueue.main.async {
                finishReminderConfirmation(with: result)
            }
        }
    }

    @MainActor
    private func finishReminderConfirmation(
        with result: KeyboardReminderScheduleResult
    ) {
        isSchedulingReminder = false

        guard case .success = result else {
            if case .failure(let error) = result {
                showReminderError(error)
            }
            return
        }

        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            reminderDraft = nil
            isSuccessMessage = true
            message = "keyboard.reminder.scheduled".localizedString()
        }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(1_350))
            withAnimation(.easeOut(duration: 0.28)) {
                message = nil
            }
            try? await Task.sleep(for: .milliseconds(300))
            isSuccessMessage = false
            withAnimation(.spring(response: 0.4, dampingFraction: 0.9)) {
                isShowingAI = false
            }
        }
    }

    private func showReminderError(_ error: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            isSuccessMessage = false
            message = error
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            withAnimation(.easeOut(duration: 0.22)) {
                message = nil
            }
        }
    }

}

private struct BudyToolbarShakeEffect: GeometryEffect {
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let offset = sin(progress * .pi * 6) * 4
        return ProjectionTransform(CGAffineTransform(translationX: offset, y: 0))
    }
}
