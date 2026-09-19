import SwiftUI

struct DictionaryView: View {
    @Environment(\.scenePhase) private var scenePhase

    @State private var words: [LaynorPersonalWord] = []
    @State private var searchText = ""
    @State private var sortMode: DictionarySortMode = .alphabetical
    @State private var selectedLetter: String?
    @State private var isShowingAdd = false
    @State private var isShowingSavedAdd = false
    @State private var isShowingClearConfirmation = false
    @State private var selectedSection: DictionarySection = .t9

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("dictionary.section.title".localizedString(), selection: $selectedSection) {
                    ForEach(DictionarySection.allCases) { section in
                        Label(section.title, systemImage: section.icon).tag(section)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 10)

                if selectedSection == .t9 {
                    Group {
                        if words.isEmpty {
                            emptyState
                        } else if !hasSearchResults {
                            noSearchResults
                        } else {
                            wordsList
                        }
                    }
                } else {
                    SavedItemsView(searchText: $searchText)
                }
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("dictionary.title".localizedString())
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if selectedSection == .t9 {
                    ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("dictionary.sort.title".localizedString(), selection: $sortMode) {
                            ForEach(DictionarySortMode.allCases) { mode in
                                Label(mode.title, systemImage: mode.icon)
                                    .tag(mode)
                            }
                        }

                        if !availableLetters.isEmpty {
                            Divider()

                            Menu {
                                Button {
                                    selectedLetter = nil
                                } label: {
                                    Label(
                                        "dictionary.alphabet.all".localizedString(),
                                        systemImage: selectedLetter == nil ? "checkmark" : "circle"
                                    )
                                }

                                ForEach(availableLetters, id: \.self) { letter in
                                    Button {
                                        selectedLetter = letter
                                    } label: {
                                        Label(
                                            letter,
                                            systemImage: selectedLetter == letter ? "checkmark" : "circle"
                                        )
                                    }
                                }
                            } label: {
                                Label("dictionary.alphabet.title".localizedString(), systemImage: "textformat.abc")
                            }
                        }

                        if !words.isEmpty {
                            Divider()
                            Button(role: .destructive) {
                                isShowingClearConfirmation = true
                            } label: {
                                Label(
                                    "dictionary.clear".localizedString(),
                                    systemImage: "trash"
                                )
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("dictionary.filters.title".localizedString())
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedSection == .t9 {
                            isShowingAdd = true
                        } else {
                            isShowingSavedAdd = true
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("dictionary.add".localizedString())
                }
            }
            .searchable(
                text: $searchText,
                prompt: selectedSection == .t9 ? "dictionary.search".localizedString() : "dictionary.saved.search".localizedString()
            )
            .confirmationDialog(
                "dictionary.clear.confirm.title".localizedString(),
                isPresented: $isShowingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("dictionary.clear.confirm.action".localizedString(), role: .destructive) {
                    LaynorPersonalDictionary.removeAll()
                }
                Button("common.cancel".localizedString(), role: .cancel) {}
            } message: {
                Text("dictionary.clear.confirm.message".localizedString())
            }
        }
        .tint(BudyTheme.accentDark)
        .sheet(isPresented: $isShowingAdd) {
            AddPersonalWordView { word, languageCode in
                LaynorPersonalDictionary.learn(
                    word,
                    languageCode: languageCode,
                    incrementUsage: false
                )
                isShowingAdd = false
            }
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(26)
        }
        .sheet(isPresented: $isShowingSavedAdd) {
            AddSavedItemView {
                isShowingSavedAdd = false
            }
            .presentationDetents([.height(330)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(26)
        }
        .onAppear(perform: refresh)
        .onReceive(
            NotificationCenter.default.publisher(
                for: .laynorPersonalDictionaryDidChange
            )
        ) { _ in
            refresh()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                refresh()
            }
        }
    }

    private var wordsList: some View {
        List {
            ForEach(DictionaryLanguage.displayOrder, id: \.self) { languageCode in
                let entries = filteredWords(for: languageCode)
                if !entries.isEmpty {
                    Section {
                        ForEach(entries) { entry in
                            DictionaryWordRow(entry: entry)
                                .listRowBackground(BudyTheme.surface)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        LaynorPersonalDictionary.remove(id: entry.id)
                                    } label: {
                                        Label(
                                            "dictionary.delete".localizedString(),
                                            systemImage: "trash"
                                        )
                                    }
                                }
                        }
                    } header: {
                        Text(DictionaryLanguage.title(for: languageCode))
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(BudyTheme.secondaryInk)
                            .textCase(nil)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(BudyTheme.background)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "text.book.closed")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(BudyTheme.accentDark)
                .frame(width: 72, height: 72)
                .background(BudyTheme.accentSoft, in: Circle())

            Text("dictionary.empty.title".localizedString())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.ink)

            Text("dictionary.empty.subtitle".localizedString())
                .font(.system(size: 14))
                .foregroundStyle(BudyTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isShowingAdd = true
            } label: {
                Label(
                    "dictionary.add".localizedString(),
                    systemImage: "plus"
                )
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BudyTheme.onPrimaryAction)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(DictionaryPressStyle())
            .padding(.top, 3)
        }
        .padding(.horizontal, 38)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var noSearchResults: some View {
        ContentUnavailableView.search(text: searchText)
            .foregroundStyle(BudyTheme.secondaryInk)
    }

    private func filteredWords(for languageCode: String) -> [LaynorPersonalWord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let filtered = words.filter { entry in
            let matchesLetter = selectedLetter == nil || firstLetter(of: entry.word) == selectedLetter
            return entry.languageCode == languageCode
                && matchesLetter
                && (query.isEmpty || entry.word.localizedCaseInsensitiveContains(query))
        }

        switch sortMode {
        case .alphabetical:
            return filtered.sorted {
                $0.word.compare(
                    $1.word,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: nil,
                    locale: Locale(identifier: languageCode)
                ) == .orderedAscending
            }
        case .usage:
            return filtered.sorted {
                if $0.selectionCount != $1.selectionCount {
                    return $0.selectionCount > $1.selectionCount
                }
                if $0.lastUsedAt != $1.lastUsedAt {
                    return $0.lastUsedAt > $1.lastUsedAt
                }
                return $0.word.compare(
                    $1.word,
                    options: [.caseInsensitive, .diacriticInsensitive],
                    range: nil,
                    locale: Locale(identifier: languageCode)
                ) == .orderedAscending
            }
        }
    }

    private var availableLetters: [String] {
        var letters: [String] = []
        for languageCode in DictionaryLanguage.displayOrder {
            for entry in words where entry.languageCode == languageCode {
                let letter = firstLetter(of: entry.word)
                if !letters.contains(letter) {
                    letters.append(letter)
                }
            }
        }
        return letters
    }

    private func firstLetter(of word: String) -> String {
        String(word.first ?? Character("A")).uppercased()
    }

    private var hasSearchResults: Bool {
        DictionaryLanguage.displayOrder.contains { !filteredWords(for: $0).isEmpty }
    }

    private func refresh() {
        words = LaynorPersonalDictionary.allWords()
    }
}


private enum DictionarySection: String, CaseIterable, Identifiable {
    case t9
    case saved
    var id: String { rawValue }
    var title: String {
        switch self {
        case .t9: "dictionary.section.t9".localizedString()
        case .saved: "dictionary.section.saved".localizedString()
        }
    }
    var icon: String {
        switch self {
        case .t9: "textformat.abc"
        case .saved: "bookmark"
        }
    }
}

private struct SavedItemsView: View {
    @State private var items: [LaynorSavedItem] = []
    @Binding var searchText: String
    @State private var isShowingClearConfirmation = false

    var body: some View {
        Group {
            if filteredItems.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(BudyTheme.accentDark)
                        .frame(width: 68, height: 68)
                        .background(BudyTheme.accentSoft, in: Circle())
                    Text("dictionary.saved.empty.title".localizedString())
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .foregroundStyle(BudyTheme.ink)
                    Text("dictionary.saved.empty.subtitle".localizedString())
                        .font(.system(size: 14))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(filteredItems) { item in
                        HStack(spacing: 12) {
                            Image(systemName: item.kind.icon)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(BudyTheme.accentDark)
                                .frame(width: 36, height: 36)
                                .background(BudyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.title.isEmpty ? item.value : item.title)
                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                    .foregroundStyle(BudyTheme.ink)
                                    .lineLimit(1)
                                if !item.title.isEmpty {
                                    Text(item.value)
                                        .font(.system(size: 13))
                                        .foregroundStyle(BudyTheme.secondaryInk)
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 6)
                            if item.selectionCount > 0 {
                                Text(String(item.selectionCount))
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(BudyTheme.secondaryInk)
                            }
                        }
                        .padding(.vertical, 5)
                        .listRowBackground(BudyTheme.surface)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                LaynorSavedItemsStore.remove(id: item.id)
                            } label: {
                                Label("dictionary.delete".localizedString(), systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if !items.isEmpty {
                    Button {
                        isShowingClearConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .accessibilityLabel("dictionary.saved.clear".localizedString())
                }
            }
        }
        .confirmationDialog("dictionary.saved.clear.confirm.title".localizedString(), isPresented: $isShowingClearConfirmation, titleVisibility: .visible) {
            Button("dictionary.saved.clear.confirm.action".localizedString(), role: .destructive) {
                LaynorSavedItemsStore.removeAll()
            }
            Button("common.cancel".localizedString(), role: .cancel) {}
        }
        .onAppear { items = LaynorSavedItemsStore.all() }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSavedItemsDidChange)) { _ in
            items = LaynorSavedItemsStore.all()
        }
    }

    private var filteredItems: [LaynorSavedItem] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return items }
        return items.filter { $0.value.localizedCaseInsensitiveContains(query) || $0.title.localizedCaseInsensitiveContains(query) }
    }
}

private struct AddSavedItemView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var value = ""
    let onAdd: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("dictionary.saved.title.placeholder".localizedString(), text: $title)
                    TextField("dictionary.saved.value.placeholder".localizedString(), text: $value, axis: .vertical)
                        .lineLimit(1...4)
                        .autocorrectionDisabled()
                } header: {
                    Text("dictionary.saved.add.title".localizedString())
                }
            }
            .scrollContentBackground(.hidden)
            .background(BudyTheme.background)
            .navigationTitle("dictionary.saved.add".localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localizedString()) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localizedString()) {
                        LaynorSavedItemsStore.add(title: title, value: value)
                        onAdd()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .tint(BudyTheme.accentDark)
    }
}

private struct DictionaryPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.86 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

private struct DictionaryWordRow: View {
    let entry: LaynorPersonalWord

    var body: some View {
        HStack(spacing: 13) {
            Text(String(entry.word.first ?? Character("A")).uppercased())
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.accentDark)
                .frame(width: 38, height: 38)
                .background(BudyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(entry.word)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(BudyTheme.ink)
                    .lineLimit(1)

            }

            Spacer(minLength: 8)

            if entry.selectionCount > 1 {
                Text(
                    String(
                        format: "dictionary.usage_count".localizedString(),
                        entry.selectionCount
                    )
                )
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(BudyTheme.secondaryInk)
                .multilineTextAlignment(.trailing)
            }
        }
        .padding(.vertical, 5)
    }
}

private struct AddPersonalWordView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var word = ""
    @State private var languageCode = LaynorPersonalDictionary.detectedLanguageCode(for: "")

    let onAdd: (String, String) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField(
                        "dictionary.word.placeholder".localizedString(),
                        text: $word
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    HStack {
                        Text("dictionary.language".localizedString())
                            .foregroundStyle(BudyTheme.secondaryInk)
                        Spacer()
                        Text(DictionaryLanguage.title(for: languageCode))
                            .foregroundStyle(BudyTheme.ink)
                    }
                } header: {
                    Text("dictionary.add.title".localizedString())
                }
            }
            .scrollContentBackground(.hidden)
            .background(BudyTheme.background)
            .navigationTitle("dictionary.add".localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localizedString()) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done".localizedString()) {
                        onAdd(word, languageCode)
                    }
                    .disabled(LaynorPersonalDictionary.validatedWord(word) == nil)
                }
            }
        }
        .tint(BudyTheme.accentDark)
        .onChange(of: word) { _, newValue in
            languageCode = LaynorPersonalDictionary.detectedLanguageCode(for: newValue)
        }
    }
}


private enum DictionarySortMode: String, CaseIterable, Identifiable {
    case alphabetical
    case usage

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: "dictionary.sort.alphabetical".localizedString()
        case .usage: "dictionary.sort.usage".localizedString()
        }
    }

    var icon: String {
        switch self {
        case .alphabetical: "textformat.abc"
        case .usage: "chart.bar.fill"
        }
    }
}

private enum DictionaryLanguage: String, CaseIterable, Identifiable {
    case ru
    case en
    case es

    var id: String { rawValue }

    static let displayOrder = ["en", "ru", "es"]

    var title: String {
        Self.title(for: rawValue)
    }

    static func title(for languageCode: String) -> String {
        switch languageCode {
        case "ru": "dictionary.language.ru".localizedString()
        case "es": "dictionary.language.es".localizedString()
        default: "dictionary.language.en".localizedString()
        }
    }
}
