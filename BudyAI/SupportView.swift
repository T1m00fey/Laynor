import Foundation
import SwiftUI

enum SupportChatActivity {
    private static let lock = NSLock()
    private static var activeThreadID: UUID?

    static func open(threadID: UUID) {
        lock.withLock {
            activeThreadID = threadID
        }
    }

    static func close(threadID: UUID) {
        lock.withLock {
            if activeThreadID == threadID {
                activeThreadID = nil
            }
        }
    }

    static func isOpen(threadID value: String) -> Bool {
        guard let threadID = UUID(uuidString: value) else { return false }
        return lock.withLock { activeThreadID == threadID }
    }
}

private enum SupportStorage {
    static let appGroupId = "group.Tim.BudyAI"
    static let key = "laynor.support.threads.v1"
}

enum SupportCategory: String, Codable, CaseIterable, Identifiable {
    case issue
    case question
    case suggestion
    case other

    var id: String { rawValue }

    var title: String {
        "support.category.\(rawValue)".localizedString()
    }

    var icon: String {
        switch self {
        case .issue: "exclamationmark.triangle.fill"
        case .question: "questionmark.circle.fill"
        case .suggestion: "lightbulb.fill"
        case .other: "bubble.left.and.bubble.right.fill"
        }
    }

    var feedbackType: FeedbackType {
        switch self {
        case .issue: .issue
        case .suggestion: .suggestion
        case .question, .other: .suggestion
        }
    }
}

enum SupportMessageAuthor: String, Codable {
    case user
    case support
}

enum SupportDeliveryState: String, Codable, Hashable {
    case pending
    case sending
    case sent
    case read
    case failed
}

enum SupportThreadStatus: String, Codable, Hashable {
    case awaitingSupport = "awaiting_support"
    case awaitingUser = "awaiting_user"
    case closed

    init(serverValue: String, isClosed: Bool) {
        if isClosed || serverValue == Self.closed.rawValue {
            self = .closed
        } else if serverValue == Self.awaitingUser.rawValue {
            self = .awaitingUser
        } else {
            self = .awaitingSupport
        }
    }

    var title: String {
        "support.status.\(rawValue)".localizedString()
    }

    var color: Color {
        switch self {
        case .awaitingSupport:
            return Color(red: 0.84, green: 0.57, blue: 0.12)
        case .awaitingUser:
            return BudyTheme.accentDark
        case .closed:
            return Color(red: 0.20, green: 0.62, blue: 0.37)
        }
    }
}

struct SupportMessage: Codable, Hashable, Identifiable {
    let id: UUID
    let text: String
    let author: SupportMessageAuthor
    let createdAt: Date
    var deliveryState: SupportDeliveryState
}

struct SupportThread: Codable, Hashable, Identifiable {
    let id: UUID
    var category: SupportCategory
    var subject: String
    var messages: [SupportMessage]
    let createdAt: Date
    var updatedAt: Date
    var isClosed: Bool
    var status: SupportThreadStatus
    var serverUnreadSupportCount: Int?
    var lastMessagePreview: String?

    private enum CodingKeys: String, CodingKey {
        case id, category, subject, messages, createdAt, updatedAt, isClosed, status, serverUnreadSupportCount, lastMessagePreview
    }

    init(
        id: UUID, category: SupportCategory, subject: String,
        messages: [SupportMessage], createdAt: Date, updatedAt: Date,
        isClosed: Bool, status: SupportThreadStatus,
        serverUnreadSupportCount: Int? = nil,
        lastMessagePreview: String? = nil
    ) {
        self.id = id
        self.category = category
        self.subject = subject
        self.messages = messages
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isClosed = isClosed
        self.status = status
        self.serverUnreadSupportCount = serverUnreadSupportCount
        self.lastMessagePreview = lastMessagePreview
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        category = try values.decode(SupportCategory.self, forKey: .category)
        subject = try values.decode(String.self, forKey: .subject)
        messages = try values.decode([SupportMessage].self, forKey: .messages)
        createdAt = try values.decode(Date.self, forKey: .createdAt)
        updatedAt = try values.decode(Date.self, forKey: .updatedAt)
        isClosed = try values.decode(Bool.self, forKey: .isClosed)
        status = try values.decodeIfPresent(SupportThreadStatus.self, forKey: .status)
            ?? (isClosed ? .closed : .awaitingSupport)
        serverUnreadSupportCount = try values.decodeIfPresent(Int.self, forKey: .serverUnreadSupportCount)
        lastMessagePreview = try values.decodeIfPresent(String.self, forKey: .lastMessagePreview)
    }

    var lastMessage: SupportMessage? { messages.last }

    var unreadSupportMessageCount: Int {
        if let serverUnreadSupportCount { return serverUnreadSupportCount }
        return messages.reduce(into: 0) { count, message in
            if message.author == .support, message.deliveryState != .read {
                count += 1
            }
        }
    }
}

private struct SupportThreadSummary: Decodable {
    let id: String
    let subject: String
    let category: String
    let status: String
    let lastMessagePreview: String
    let lastMessageAuthor: String
    let createdAt: String
    let updatedAt: String
    let unreadForUserCount: Int

    private enum CodingKeys: String, CodingKey {
        case id, subject, category, status, lastMessagePreview, lastMessageAuthor
        case createdAt, updatedAt, unreadForUserCount
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "other"
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "awaiting_support"
        lastMessagePreview = try values.decodeIfPresent(String.self, forKey: .lastMessagePreview) ?? ""
        lastMessageAuthor = try values.decodeIfPresent(String.self, forKey: .lastMessageAuthor) ?? "user"
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        unreadForUserCount = try values.decodeIfPresent(Int.self, forKey: .unreadForUserCount) ?? 0
    }
}

private struct SupportUserListResponse: Decodable {
    let threads: [SupportThreadSummary]
}

struct SupportSyncMessage: Decodable {
    let id: String
    let author: String
    let text: String
    let createdAt: String
}

private struct SupportSyncResponse: Decodable {
    let messages: [SupportSyncMessage]
    let readMessageIds: [String]
    let status: String

    private enum CodingKeys: String, CodingKey {
        case messages, readMessageIds, status
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        messages = try values.decodeIfPresent([SupportSyncMessage].self, forKey: .messages) ?? []
        readMessageIds = try values.decodeIfPresent([String].self, forKey: .readMessageIds) ?? []
        status = try values.decodeIfPresent(String.self, forKey: .status) ?? "awaiting_support"
    }
}

private struct SupportMarkReadRequest: Encodable {
    let action = "support_mark_read"
    let threadId: String
    let installationId: String
}

// The inbox and an opened thread can be alive at the same time in a
// NavigationStack. Coalesce their sync request so an older response cannot
// arrive after a newer one and overwrite the local status.
private actor SupportSyncCoordinator {
    static let shared = SupportSyncCoordinator()
    private var inFlight: [UUID: Task<Void, Error>] = [:]

    func sync(threadID: UUID) async throws {
        if let task = inFlight[threadID] {
            try await task.value
            return
        }

        let task = Task {
            try await SupportRemoteService().performSync(threadID: threadID)
        }
        inFlight[threadID] = task
        defer { inFlight[threadID] = nil }
        try await task.value
    }

}

enum SupportStore {
    private static let lock = NSLock()

    static func allThreads() -> [SupportThread] {
        lock.withLock {
            load().sorted { $0.updatedAt > $1.updatedAt }
        }
    }

    @discardableResult
    static func create(
        category: SupportCategory,
        subject: String,
        message: String
    ) -> SupportThread? {
        let cleanSubject = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanMessage = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanSubject.count >= 2, cleanSubject.count <= 120,
              cleanMessage.count >= 3, cleanMessage.count <= 2_000 else {
            return nil
        }

        let now = Date()
        let thread = SupportThread(
            id: UUID(),
            category: category,
            subject: cleanSubject,
            messages: [
                SupportMessage(
                    id: UUID(),
                    text: cleanMessage,
                    author: .user,
                    createdAt: now,
                    deliveryState: .pending
                )
            ],
            createdAt: now,
            updatedAt: now,
            isClosed: false,
            status: .awaitingSupport
        )

        lock.withLock {
            var threads = load()
            threads.append(thread)
            save(threads)
        }
        notifyChange()
        return thread
    }

    @discardableResult
    static func appendMessage(threadID: UUID, text: String) -> SupportMessage? {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleanText.count >= 1, cleanText.count <= 2_000 else { return nil }

        let now = Date()
        let message = SupportMessage(
            id: UUID(),
            text: cleanText,
            author: .user,
            createdAt: now,
            deliveryState: .pending
        )

        let didAppend = lock.withLock {
            var threads = load()
            guard let index = threads.firstIndex(where: { $0.id == threadID }),
                  !threads[index].isClosed else { return false }
            threads[index].messages.append(message)
            threads[index].updatedAt = now
            if threads[index].status != .awaitingUser {
                threads[index].status = .awaitingSupport
            }
            save(threads)
            return true
        }
        guard didAppend else { return nil }
        notifyChange()
        return message
    }

    static func setDelivery(
        threadID: UUID,
        messageID: UUID,
        state: SupportDeliveryState
    ) {
        lock.withLock {
            var threads = load()
            guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }),
                  let messageIndex = threads[threadIndex].messages.firstIndex(where: { $0.id == messageID }) else {
                return
            }
            threads[threadIndex].messages[messageIndex].deliveryState = state
            threads[threadIndex].updatedAt = Date()
            save(threads)
        }
        notifyChange()
    }

    static func applySync(
        threadID: UUID,
        messages remoteMessages: [SupportSyncMessage],
        readMessageIDs: Set<UUID>,
        status serverStatus: String
    ) {
        lock.withLock {
            var threads = load()
            guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else { return }

            threads[threadIndex].status = SupportThreadStatus(
                serverValue: serverStatus,
                isClosed: threads[threadIndex].isClosed
            )
            threads[threadIndex].isClosed = threads[threadIndex].status == .closed

            for messageIndex in threads[threadIndex].messages.indices {
                let message = threads[threadIndex].messages[messageIndex]
                if message.author == .user, readMessageIDs.contains(message.id) {
                    threads[threadIndex].messages[messageIndex].deliveryState = .read
                } else if message.author == .support,
                          readMessageIDs.contains(message.id) {
                    threads[threadIndex].messages[messageIndex].deliveryState = .read
                }
            }

            let existingIDs = Set(threads[threadIndex].messages.map(\.id))
            let formatter = ISO8601DateFormatter()
            for remote in remoteMessages where remote.author == "support" {
                guard let id = UUID(uuidString: remote.id), !existingIDs.contains(id) else { continue }
                threads[threadIndex].messages.append(
                    SupportMessage(
                        id: id,
                        text: remote.text,
                        author: .support,
                        createdAt: formatter.date(from: remote.createdAt) ?? Date(),
                        deliveryState: readMessageIDs.contains(id) ? .read : .sent
                    )
                )
            }
            threads[threadIndex].messages.sort { $0.createdAt < $1.createdAt }
            if let lastDate = threads[threadIndex].messages.last?.createdAt {
                threads[threadIndex].updatedAt = lastDate
            }
            threads[threadIndex].lastMessagePreview = threads[threadIndex].messages.last?.text
            threads[threadIndex].serverUnreadSupportCount = threads[threadIndex].messages.reduce(into: 0) { count, message in
                if message.author == .support && message.deliveryState != .read { count += 1 }
            }
            save(threads)
        }
        notifyChange()
    }

    fileprivate static func applySummaries(_ summaries: [SupportThreadSummary]) {
        let iso = ISO8601DateFormatter()
        lock.withLock {
            var threads = load()
            let existingByID = Dictionary(uniqueKeysWithValues: threads.map { ($0.id, $0) })
            var updated = summaries.compactMap { summary -> SupportThread? in
                guard let id = UUID(uuidString: summary.id) else { return nil }
                let old = existingByID[id]
                let status = SupportThreadStatus(
                    serverValue: summary.status,
                    isClosed: summary.status == SupportThreadStatus.closed.rawValue
                )
                let createdAt = iso.date(from: summary.createdAt) ?? old?.createdAt ?? Date()
                let updatedAt = iso.date(from: summary.updatedAt) ?? old?.updatedAt ?? createdAt
                return SupportThread(
                    id: id,
                    category: SupportCategory(rawValue: summary.category) ?? old?.category ?? .other,
                    subject: summary.subject.isEmpty ? (old?.subject ?? "") : summary.subject,
                    messages: old?.messages ?? [],
                    createdAt: createdAt,
                    updatedAt: updatedAt,
                    isClosed: status == .closed,
                    status: status,
                    serverUnreadSupportCount: summary.unreadForUserCount,
                    lastMessagePreview: summary.lastMessagePreview
                )
            }
            let returnedIDs = Set(updated.map(\.id))
            updated.append(contentsOf: existingByID.values.filter { thread in
                !returnedIDs.contains(thread.id)
                    && thread.messages.contains {
                        $0.deliveryState == .pending
                            || $0.deliveryState == .sending
                            || $0.deliveryState == .failed
                    }
            })
            threads = updated
            save(updated)
        }
        notifyChange()
    }

    static func close(threadID: UUID) {
        lock.withLock {
            var threads = load()
            guard let index = threads.firstIndex(where: { $0.id == threadID }) else { return }
            threads[index].isClosed = true
            threads[index].status = .closed
            threads[index].updatedAt = Date()
            save(threads)
        }
        notifyChange()
    }

    static func thread(id: UUID) -> SupportThread? {
        lock.withLock { load().first(where: { $0.id == id }) }
    }

    static func hasUnreadSupportMessages(threadID: UUID) -> Bool {
        lock.withLock {
            guard let thread = load().first(where: { $0.id == threadID }) else { return false }
            return thread.messages.contains {
                $0.author == .support && $0.deliveryState != .read
            }
        }
    }

    static func markSupportMessagesRead(threadID: UUID) {
        var didChange = false
        lock.withLock {
            var threads = load()
            guard let threadIndex = threads.firstIndex(where: { $0.id == threadID }) else {
                return
            }
            for messageIndex in threads[threadIndex].messages.indices {
                guard threads[threadIndex].messages[messageIndex].author == .support,
                      threads[threadIndex].messages[messageIndex].deliveryState != .read else {
                    continue
                }
                threads[threadIndex].messages[messageIndex].deliveryState = .read
                didChange = true
            }
            guard didChange else { return }
            threads[threadIndex].serverUnreadSupportCount = 0
            save(threads)
        }
        if didChange { notifyChange() }
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: SupportStorage.appGroupId) ?? .standard
    }

    private static func load() -> [SupportThread] {
        guard let data = defaults.data(forKey: SupportStorage.key) else { return [] }
        return (try? JSONDecoder().decode([SupportThread].self, from: data)) ?? []
    }

    private static func save(_ threads: [SupportThread]) {
        guard let data = try? JSONEncoder().encode(threads) else { return }
        defaults.set(data, forKey: SupportStorage.key)
    }

    private static func notifyChange() {
        let post = {
            NotificationCenter.default.post(name: .laynorSupportDidChange, object: nil)
        }
        if Thread.isMainThread {
            post()
        } else {
            DispatchQueue.main.async(execute: post)
        }
    }
}

struct SupportRemoteService {
    func send(thread: SupportThread, message: SupportMessage) async throws {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else {
            throw FeedbackError.invalidURL
        }

        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
        let payload = SupportRequest(
            type: thread.category.feedbackType.rawValue,
            message: message.text,
            locale: LaynorLocalization.appLanguageCode,
            appVersion: version,
            threadId: thread.id.uuidString.lowercased(),
            subject: thread.subject,
            category: thread.category.rawValue,
            installationId: LaynorInstallation.identifier,
            messageId: message.id.uuidString.lowercased(),
            messageCreatedAt: ISO8601DateFormatter().string(from: message.createdAt),
            threadCreatedAt: ISO8601DateFormatter().string(from: thread.createdAt)
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(SupportErrorResponse.self, from: data)
            throw FeedbackError.api(backendError?.error ?? "feedback.error.generic".localizedString())
        }
    }

    func sync(threadID: UUID) async throws {
        try await SupportSyncCoordinator.shared.sync(threadID: threadID)
    }

    func close(threadID: UUID) async throws {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else {
            throw FeedbackError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(SupportUserCloseRequest(
            threadId: threadID.uuidString.lowercased(),
            installationId: LaynorInstallation.identifier
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let backendError = try? JSONDecoder().decode(SupportErrorResponse.self, from: data)
            throw FeedbackError.api(backendError?.error ?? "feedback.error.generic".localizedString())
        }
    }

    func listThreads() async throws {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else { throw FeedbackError.invalidURL }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(SupportUserListRequest(
            installationId: LaynorInstallation.identifier
        ))
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw FeedbackError.invalidResponse
        }
        let value = try JSONDecoder().decode(SupportUserListResponse.self, from: data)
        SupportStore.applySummaries(value.threads)
    }

    fileprivate func performSync(threadID: UUID) async throws {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else {
            throw FeedbackError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(
            SupportSyncRequest(
                action: "support_thread",
                threadId: threadID.uuidString.lowercased(),
                installationId: LaynorInstallation.identifier
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { return }
            throw FeedbackError.invalidResponse
        }
        let value = try JSONDecoder().decode(SupportSyncResponse.self, from: data)
        let readIDs = Set(value.readMessageIds.compactMap(UUID.init(uuidString:)))
        SupportStore.applySync(
            threadID: threadID,
            messages: value.messages,
            readMessageIDs: readIDs,
            status: value.status
        )
    }

    func markRead(threadID: UUID) async throws {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else {
            throw FeedbackError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(BudyConfiguration.clientKey, forHTTPHeaderField: "X-Budy-Client")
        request.timeoutInterval = 15
        request.httpBody = try JSONEncoder().encode(
            SupportMarkReadRequest(
                threadId: threadID.uuidString.lowercased(),
                installationId: LaynorInstallation.identifier
            )
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw FeedbackError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if http.statusCode == 404 { return }
            let backendError = try? JSONDecoder().decode(SupportErrorResponse.self, from: data)
            throw FeedbackError.api(backendError?.error ?? "feedback.error.generic".localizedString())
        }
    }
}

private struct SupportSyncRequest: Encodable {
    let action: String
    let threadId: String
    let installationId: String
}

private struct SupportUserListRequest: Encodable {
    let action = "support_user_list"
    let installationId: String
}

private struct SupportUserCloseRequest: Encodable {
    let action = "support_user_close"
    let threadId: String
    let installationId: String
}

private struct SupportRequest: Encodable {
    let type: String
    let message: String
    let locale: String
    let appVersion: String
    let threadId: String
    let subject: String
    let category: String
    let installationId: String
    let messageId: String
    let messageCreatedAt: String
    let threadCreatedAt: String
}

private struct SupportErrorResponse: Decodable {
    let error: String
}

struct SupportView: View {
    @Binding var unreadCount: Int
    @AppStorage("laynor.support.access.granted")  private var isSupportMode = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var threads: [SupportThread] = []
    @State private var isSyncing = false
    @State private var isShowingNewThread = false

    var body: some View {
        Group {
            if isSupportMode {
                SupportOperatorInboxView(unreadCount: $unreadCount)
            } else {
                userSupportView
            }
        }
    }

    private var userSupportView: some View {
        NavigationStack {
            Group {
                if threads.isEmpty {
                    emptyState
                } else {
                    List {
                        ForEach(threads) { thread in
                            NavigationLink {
                                SupportThreadView(threadID: thread.id)
                            } label: {
                                SupportThreadRow(thread: thread)
                            }
                            .listRowBackground(BudyTheme.surface)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("support.title".localizedString())
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isShowingNewThread = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .accessibilityLabel("support.new".localizedString())
                }
            }
        }
        .tint(BudyTheme.accentDark)
        .sheet(isPresented: $isShowingNewThread) {
            NewSupportThreadView()
                .presentationDetents([.height(590)])
                .presentationDragIndicator(.visible)
                .presentationCornerRadius(26)
        }
        .onAppear(perform: refresh)
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportDidChange)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportPushReceived)) { notification in
            if let value = notification.userInfo?["threadId"] as? String,
               let id = UUID(uuidString: value) {
                Task { try? await SupportRemoteService().sync(threadID: id); refresh() }
            } else {
                Task { await syncThreads() }
            }
        }
        .task {
            await syncThreads()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                guard !Task.isCancelled else { return }
                await syncThreads()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await syncThreads() }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(BudyTheme.accentDark)
                .frame(width: 72, height: 72)
                .background(BudyTheme.accentSoft, in: Circle())

            Text("support.empty.title".localizedString())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.ink)

            Text("support.empty.subtitle".localizedString())
                .font(.system(size: 14))
                .foregroundStyle(BudyTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                isShowingNewThread = true
            } label: {
                Label("support.new".localizedString(), systemImage: "plus")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(BudyTheme.onPrimaryAction)
                    .padding(.horizontal, 18)
                    .frame(height: 46)
                    .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.top, 3)
        }
        .padding(.horizontal, 34)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func refresh() {
        threads = SupportStore.allThreads()
    }

    private func syncThreads() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        try? await SupportRemoteService().listThreads()
        guard !Task.isCancelled else { return }
        refresh()
    }
}

private struct SupportThreadRow: View {
    let thread: SupportThread

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: thread.category.icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(BudyTheme.accentDark)
                .frame(width: 38, height: 38)
                .background(BudyTheme.accentSoft, in: RoundedRectangle(cornerRadius: 11, style: .continuous))

            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(thread.subject)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .foregroundStyle(BudyTheme.ink)
                        .lineLimit(1)

                    Text(thread.lastMessage?.text ?? thread.lastMessagePreview ?? "")
                        .font(.system(size: 13))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .lineLimit(2)

                    Text(thread.category.title)
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(thread.status.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(thread.status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(thread.updatedAt, style: .date)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BudyTheme.secondaryInk)

                    if thread.unreadSupportMessageCount > 0 {
                        Text("\(thread.unreadSupportMessageCount)")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(BudyTheme.accentDark)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(
                                Circle().fill(BudyTheme.accent.opacity(0.16))
                            )
                            .accessibilityLabel(
                                "\(thread.unreadSupportMessageCount) unread messages"
                            )
                    }
                }
                .frame(minWidth: 76, alignment: .trailing)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 5)
    }
}

private struct SupportThreadView: View {
    let threadID: UUID
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var thread: SupportThread?
    @State private var draft = ""
    @State private var isSending = false
    @State private var isSyncing = false
    @State private var isClosing = false
    @State private var hasShownInitialMessages = false
    @State private var errorMessage = ""
    @State private var showsError = false

    var body: some View {
        VStack(spacing: 0) {
            if let thread {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 10) {
                            ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                                SupportMessageBubble(
                                    message: message,
                                    onRetry: message.deliveryState == .failed
                                        ? { send(thread: thread, message: message) }
                                        : nil
                                )
                                    .id(message.id)
                                    .transition(
                                        message.author == .user
                                            ? .asymmetric(
                                                insertion: .offset(x: 30, y: 24)
                                                    .combined(with: .scale(scale: 0.82, anchor: .bottomTrailing))
                                                    .combined(with: .opacity),
                                                removal: .opacity
                                            )
                                            : .asymmetric(
                                                insertion: .offset(x: -30, y: 24)
                                                    .combined(with: .scale(scale: 0.82, anchor: .bottomLeading))
                                                    .combined(with: .opacity),
                                                removal: .opacity
                                            )
                                    )
                                    .opacity(hasShownInitialMessages ? 1 : 0)
                                    .offset(
                                        x: hasShownInitialMessages
                                            ? 0
                                            : (message.author == .user ? 30 : -30),
                                        y: hasShownInitialMessages ? 0 : 24
                                    )
                                    .scaleEffect(
                                        hasShownInitialMessages ? 1 : 0.82,
                                        anchor: message.author == .user
                                            ? .bottomTrailing
                                            : .bottomLeading
                                    )
                                    .animation(
                                        .spring(response: 0.36, dampingFraction: 0.82)
                                            .delay(min(Double(index) * 0.04, 0.45)),
                                        value: hasShownInitialMessages
                                    )
                            }
                        }
                        .padding(16)
                    }
                    .onChange(of: thread.messages.count) { _, _ in
                        if let id = thread.messages.last?.id {
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                                proxy.scrollTo(id, anchor: .bottom)
                            }
                        }
                    }
                }

                if !thread.isClosed {
                    HStack(alignment: .bottom, spacing: 8) {
                        TextField("support.reply.placeholder".localizedString(), text: $draft, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 13)
                            .padding(.vertical, 10)
                            .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .onChange(of: draft) { _, value in
                                if value.count > 2_000 {
                                    draft = String(value.prefix(2_000))
                                }
                            }

                        Button(action: send) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                                .foregroundStyle(BudyTheme.onPrimaryAction)
                                .frame(width: 42, height: 42)
                                .background(BudyTheme.primaryAction, in: Circle())
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSend)
                        .opacity(canSend ? 1 : 0.45)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .background(BudyTheme.background)
                }
            } else {
                ProgressView()
            }
        }
        .background(BudyTheme.background.ignoresSafeArea())
        .navigationTitle(thread?.subject ?? "support.title".localizedString())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let thread {
                ToolbarItem(placement: .principal) {
                    VStack(spacing: 1) {
                        Text(thread.subject)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                            .lineLimit(1)
                        Text(thread.status.title)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(thread.status.color)
                            .lineLimit(1)
                    }
                }
            }
            if thread?.isClosed == false {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("support.close".localizedString()) {
                        closeThread()
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .disabled(isClosing || isSending)
                }
            }
        }
        .onAppear {
            SupportChatActivity.open(threadID: threadID)
            refresh()
        }
        .onDisappear {
            SupportChatActivity.close(threadID: threadID)
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportDidChange)) { _ in
            refresh()
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportPushReceived)) { notification in
            guard let pushedID = notification.userInfo?["threadId"] as? String,
                  UUID(uuidString: pushedID) == threadID else { return }
            Task { await syncAndMarkRead() }
        }
        .task(id: threadID) {
            while !Task.isCancelled {
                await syncAndMarkRead()
                try? await Task.sleep(for: .seconds(8))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                SupportChatActivity.open(threadID: threadID)
                Task { await syncAndMarkRead() }
            } else {
                SupportChatActivity.close(threadID: threadID)
            }
        }
        .alert("support.error.title".localizedString(), isPresented: $showsError) {
            Button("common.ok".localizedString(), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var canSend: Bool {
        !isSending && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend, let thread else { return }
        guard let message = SupportStore.appendMessage(threadID: thread.id, text: draft) else { return }
        draft = ""

        // Update the local conversation immediately so the outgoing bubble
        // gets its insertion transition before the network request starts.
        if let updatedThread = SupportStore.thread(id: thread.id) {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                self.thread = updatedThread
            }
        }
        send(thread: thread, message: message)
    }

    private func send(thread: SupportThread, message: SupportMessage) {
        isSending = true
        SupportStore.setDelivery(threadID: thread.id, messageID: message.id, state: .sending)

        Task {
            do {
                try await SupportRemoteService().send(thread: thread, message: message)
                SupportStore.setDelivery(threadID: thread.id, messageID: message.id, state: .sent)
            } catch {
                SupportStore.setDelivery(threadID: thread.id, messageID: message.id, state: .failed)
                errorMessage = error.localizedDescription
                showsError = true
            }
            isSending = false
        }
    }

    private func closeThread() {
        guard !isClosing else { return }
        isClosing = true
        Task {
            do {
                try await SupportRemoteService().close(threadID: threadID)
                SupportStore.close(threadID: threadID)
            } catch {
                errorMessage = error.localizedDescription
                showsError = true
            }
            isClosing = false
        }
    }

    private func refresh() {
        let hadThread = thread != nil
        let updatedThread = SupportStore.thread(id: threadID)
        let shouldAnimateInsertion = thread != nil
            && (updatedThread?.messages.count ?? 0) > (thread?.messages.count ?? 0)

        if shouldAnimateInsertion {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                thread = updatedThread
            }
        } else {
            thread = updatedThread
        }

        if !hadThread, updatedThread != nil {
            revealInitialMessages()
        }
    }

    private func revealInitialMessages() {
        guard !hasShownInitialMessages else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                hasShownInitialMessages = true
            }
        }
    }

    private func syncAndMarkRead() async {
        guard !isSyncing else { return }
        isSyncing = true
        defer { isSyncing = false }

        let service = SupportRemoteService()

        // If the response is already in local storage, acknowledge it without
        // waiting for the next read request to finish. A second check below
        // covers replies discovered by this sync.
        await markReadIfNeeded(using: service)

        do {
            try await service.sync(threadID: threadID)
        } catch {
            // Keep the local conversation usable when the network is slow or unavailable.
            return
        }

        // The store posts a notification, but refresh explicitly as well:
        // notifications can be coalesced during a navigation transition.
        await MainActor.run {
            refresh()
        }
        await markReadIfNeeded(using: service)
    }

    private func markReadIfNeeded(using service: SupportRemoteService) async {
        guard SupportStore.hasUnreadSupportMessages(threadID: threadID) else { return }
        do {
            try await service.markRead(threadID: threadID)
            SupportStore.markSupportMessagesRead(threadID: threadID)
        } catch {
            // The next polling pass will retry the acknowledgement.
        }
    }
}

private struct SupportMessageBubble: View {
    let message: SupportMessage
    let onRetry: (() -> Void)?

    var body: some View {
        HStack {
            if message.author == .user { Spacer(minLength: 36) }

            HStack(alignment: .bottom, spacing: 7) {
                Text(message.text)
                    .foregroundStyle(message.author == .user ? Color.white : BudyTheme.ink)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                messageMetadata
                    .fixedSize()
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 10)
            .background(
                message.author == .user ? BudyTheme.accent : BudyTheme.surface,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )

            if message.author == .support { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity)
    }

    private var messageMetadata: some View {
        HStack(spacing: 5) {
            Text(message.createdAt, style: .time)
            if message.author == .user {
                deliveryIndicator
                    .id(message.deliveryState)
                    .transition(.scale(scale: 0.72).combined(with: .opacity))
                    .animation(
                        .spring(response: 0.28, dampingFraction: 0.76),
                        value: message.deliveryState
                    )
            }
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(
            message.author == .user
                ? Color.white.opacity(0.74)
                : BudyTheme.secondaryInk
        )
    }

    @ViewBuilder
    private var deliveryIndicator: some View {
        switch message.deliveryState {
        case .pending, .sending:
            Image(systemName: "clock")
                .accessibilityLabel("support.message.sending".localizedString())
        case .sent:
            Image(systemName: "checkmark")
                .accessibilityLabel("support.message.sent".localizedString())
        case .read:
            ZStack {
                Image(systemName: "checkmark")
                    .offset(x: -2)
                Image(systemName: "checkmark")
                    .offset(x: 2)
            }
            .frame(width: 13, height: 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("support.message.read".localizedString())
        case .failed:
            Button {
                onRetry?()
            } label: {
                Image(systemName: "exclamationmark")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(Color.white)
                    .frame(width: 18, height: 18)
                    .background(Color.red, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("support.retry".localizedString())
        }
    }
}

private struct NewSupportThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var category: SupportCategory = .issue
    @State private var subject = ""
    @State private var message = ""
    @FocusState private var focusedField: Field?
    @State private var isSending = false
    @State private var errorMessage = ""
    @State private var showsError = false

    private enum Field {
        case subject
        case message
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("support.new.title".localizedString())
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(BudyTheme.ink)

                            Text("support.new.subtitle".localizedString())
                                .font(.system(size: 13))
                                .foregroundStyle(BudyTheme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        categoryPicker

                        VStack(spacing: 10) {
                            supportField(
                                icon: "text.alignleft",
                                field: .subject
                            ) {
                                TextField("support.subject.placeholder".localizedString(), text: $subject)
                                    .focused($focusedField, equals: .subject)
                                    .submitLabel(.next)
                                    .onSubmit { focusedField = .message }
                            }

                            supportField(
                                icon: "bubble.left.and.text.bubble.right",
                                field: .message,
                                alignment: .top
                            ) {
                                TextField("support.message.placeholder".localizedString(), text: $message, axis: .vertical)
                                    .focused($focusedField, equals: .message)
                                    .lineLimit(4...8)
                                    .autocorrectionDisabled()
                            }

                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)
                    .padding(.bottom, 20)
                }

                submitButton
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .onChange(of: subject) { _, value in
                if value.count > 120 { subject = String(value.prefix(120)) }
            }
            .onChange(of: message) { _, value in
                if value.count > 2_000 { message = String(value.prefix(2_000)) }
            }
            .navigationTitle("support.new".localizedString())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel".localizedString()) { dismiss() }
                        .disabled(isSending)
                }
            }
        }
        .tint(BudyTheme.accentDark)
        .alert("support.error.title".localizedString(), isPresented: $showsError) {
            Button("common.ok".localizedString(), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var categoryPicker: some View {
        HStack(spacing: 8) {
            ForEach(SupportCategory.allCases) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) {
                        category = option
                    }
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: option.icon)
                            .font(.system(size: 15, weight: .semibold))
                        Text(option.title)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(category == option ? BudyTheme.onPrimaryAction : BudyTheme.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 62)
                    .background(
                        category == option ? BudyTheme.primaryAction : BudyTheme.surface,
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(category == option ? Color.clear : BudyTheme.border)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func supportField<Content: View>(
        icon: String,
        field: Field,
        alignment: VerticalAlignment = .center,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(alignment: alignment, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(focusedField == field ? BudyTheme.accentDark : BudyTheme.secondaryInk)
                .frame(width: 18)
                .padding(.top, alignment == .top ? 4 : 0)

            content()
                .font(.system(size: 15))
                .foregroundStyle(BudyTheme.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, alignment == .top ? 13 : 12)
        .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .stroke(
                    focusedField == field ? BudyTheme.accentDark.opacity(0.78) : BudyTheme.border,
                    lineWidth: focusedField == field ? 1.5 : 1
                )
        }
    }

    private var submitButton: some View {
        Button(action: create) {
            HStack(spacing: 9) {
                if isSending {
                    ProgressView().tint(BudyTheme.onPrimaryAction)
                } else {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 14, weight: .bold))
                }
                Text("common.done".localizedString())
                    .font(.system(size: 16, weight: .bold))
            }
            .foregroundStyle(BudyTheme.onPrimaryAction)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(BudyTheme.primaryAction, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canCreate || isSending)
        .opacity(canCreate && !isSending ? 1 : 0.46)
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(BudyTheme.background)
    }

    private var canCreate: Bool {
        subject.trimmingCharacters(in: .whitespacesAndNewlines).count >= 2
            && message.trimmingCharacters(in: .whitespacesAndNewlines).count >= 3
    }

    private func create() {
        guard canCreate,
              let thread = SupportStore.create(
                category: category,
                subject: subject,
                message: message
              ),
              let firstMessage = thread.messages.first else { return }

        isSending = true
        SupportStore.setDelivery(threadID: thread.id, messageID: firstMessage.id, state: .sending)
        Task {
            do {
                try await SupportRemoteService().send(thread: thread, message: firstMessage)
                SupportStore.setDelivery(threadID: thread.id, messageID: firstMessage.id, state: .sent)
                dismiss()
            } catch {
                SupportStore.setDelivery(threadID: thread.id, messageID: firstMessage.id, state: .failed)
                isSending = false
                errorMessage = error.localizedDescription
                showsError = true
            }
        }
    }
}

extension Notification.Name {
    static let laynorSupportDidChange = Notification.Name("laynor.support.didChange")
    static let laynorSupportPushReceived = Notification.Name("laynor.support.pushReceived")
    static let laynorOpenSupportOperator = Notification.Name("laynor.support.openOperator")
    static let laynorOpenSupport = Notification.Name("laynor.support.open")
}
