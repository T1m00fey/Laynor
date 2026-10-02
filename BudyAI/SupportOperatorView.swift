import Foundation
import SwiftUI

struct SupportOperatorMessage: Decodable, Identifiable, Hashable {
    let id: String
    let author: SupportMessageAuthor
    let text: String
    let createdAt: String
    var deliveryState: SupportDeliveryState

    private enum CodingKeys: String, CodingKey {
        case id, author, text, createdAt, deliveryState
    }

    init(
        id: String,
        author: SupportMessageAuthor,
        text: String,
        createdAt: String,
        deliveryState: SupportDeliveryState = .sent
    ) {
        self.id = id
        self.author = author
        self.text = text
        self.createdAt = createdAt
        self.deliveryState = deliveryState
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        author = try values.decode(SupportMessageAuthor.self, forKey: .author)
        text = try values.decode(String.self, forKey: .text)
        createdAt = try values.decode(String.self, forKey: .createdAt)
        deliveryState = try values.decodeIfPresent(SupportDeliveryState.self, forKey: .deliveryState)
            ?? (author == .support ? .sent : .read)
    }

    var date: Date {
        ISO8601DateFormatter().date(from: createdAt) ?? Date()
    }
}

struct SupportOperatorThread: Decodable, Identifiable, Hashable {
    let id: String
    let subject: String
    let category: String
    var status: SupportThreadStatus
    var messages: [SupportOperatorMessage]
    let createdAt: String
    var updatedAt: String
    var unreadFromUserCount: Int = 0
    var lastMessagePreview: String = ""

    private enum CodingKeys: String, CodingKey {
        case id, subject, category, status, messages, createdAt, updatedAt
        case unreadForSupportCount, lastMessagePreview
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(String.self, forKey: .id)
        subject = try values.decodeIfPresent(String.self, forKey: .subject) ?? ""
        category = try values.decodeIfPresent(String.self, forKey: .category) ?? "other"
        let statusValue = try values.decodeIfPresent(String.self, forKey: .status) ?? "awaiting_support"
        status = SupportThreadStatus(serverValue: statusValue, isClosed: statusValue == "closed")
        messages = try values.decodeIfPresent([SupportOperatorMessage].self, forKey: .messages) ?? []
        createdAt = try values.decodeIfPresent(String.self, forKey: .createdAt) ?? ""
        updatedAt = try values.decodeIfPresent(String.self, forKey: .updatedAt) ?? createdAt
        unreadFromUserCount = try values.decodeIfPresent(Int.self, forKey: .unreadForSupportCount) ?? 0
        lastMessagePreview = try values.decodeIfPresent(String.self, forKey: .lastMessagePreview) ?? ""
    }

    var categoryValue: SupportCategory {
        SupportCategory(rawValue: category) ?? .other
    }

    var updatedDate: Date {
        ISO8601DateFormatter().date(from: updatedAt) ?? Date()
    }

    var unreadSupportMessageCount: Int {
        if unreadFromUserCount > 0 { return unreadFromUserCount }
        return messages.reduce(into: 0) { count, message in
            if message.author == .user, message.deliveryState != .read {
                count += 1
            }
        }
    }
}

private struct SupportOperatorListResponse: Decodable {
    let threads: [SupportOperatorThread]
}

private struct SupportOperatorListRequest: Encodable {
    let action = "support_list"
    let code: String
}

private struct SupportOperatorThreadRequest: Encodable {
    let action = "support_operator_thread"
    let code: String
    let threadId: String
}

private struct SupportOperatorReplyRequest: Encodable {
    let action = "support_reply"
    let code: String
    let threadId: String
    let messageId: String
    let message: String
    let createdAt: String
}

private struct SupportOperatorCloseRequest: Encodable {
    let action = "support_close"
    let code: String
    let threadId: String
}

private struct SupportOperatorMarkReadRequest: Encodable {
    let action = "support_operator_mark_read"
    let code: String
    let threadId: String
}

private struct SupportOperatorErrorResponse: Decodable {
    let error: String
}

private enum SupportOperatorError: LocalizedError {
    case invalidURL
    case unauthorized
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "support.access.error.url".localizedString()
        case .unauthorized:
            return "support.operator.session.expired".localizedString()
        case .server(let message):
            return message
        }
    }
}

private struct SupportOperatorService {
    func openThreads(code: String) async throws -> [SupportOperatorThread] {
        let data = try await perform(SupportOperatorListRequest(code: code))
        return try JSONDecoder().decode(SupportOperatorListResponse.self, from: data).threads
    }

    func openThread(code: String, threadID: String) async throws -> SupportOperatorThread {
        let data = try await perform(SupportOperatorThreadRequest(code: code, threadId: threadID))
        return try JSONDecoder().decode(SupportOperatorThread.self, from: data)
    }

    func reply(code: String, threadID: String, messageID: String, text: String, createdAt: Date) async throws {
        _ = try await perform(
            SupportOperatorReplyRequest(
                code: code,
                threadId: threadID,
                messageId: messageID,
                message: text,
                createdAt: ISO8601DateFormatter().string(from: createdAt)
            )
        )
    }

    func close(code: String, threadID: String) async throws {
        _ = try await perform(SupportOperatorCloseRequest(code: code, threadId: threadID))
    }

    func markRead(code: String, threadID: String) async throws {
        _ = try await perform(
            SupportOperatorMarkReadRequest(code: code, threadId: threadID)
        )
    }

    private func perform<Payload: Encodable>(_ payload: Payload) async throws -> Data {
        guard let url = URL(string: BudyConfiguration.feedbackURL) else {
            throw SupportOperatorError.invalidURL
        }
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
            throw SupportOperatorError.server("support.access.error.response".localizedString())
        }
        if http.statusCode == 401 || http.statusCode == 403 {
            throw SupportOperatorError.unauthorized
        }
        guard (200..<300).contains(http.statusCode) else {
            let value = try? JSONDecoder().decode(SupportOperatorErrorResponse.self, from: data)
            throw SupportOperatorError.server(value?.error ?? "support.access.error.response".localizedString())
        }
        return data
    }
}

struct SupportOperatorInboxView: View {
    @Binding var unreadCount: Int
    @AppStorage("laynor.support.access.granted") private var isSupportMode = false
    @Environment(\.scenePhase) private var scenePhase
    @State private var threads: [SupportOperatorThread] = []
    @State private var isLoading = true
    @State private var hasLoaded = false
    @State private var isRefreshing = false
    @State private var errorMessage = ""
    @State private var showsError = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && !hasLoaded {
                    ProgressView()
                } else if threads.isEmpty {
                    ContentUnavailableView(
                        "support.operator.empty.title".localizedString(),
                        systemImage: "checkmark.bubble",
                        description: Text("support.operator.empty.subtitle".localizedString())
                    )
                } else {
                    List(threads) { thread in
                        NavigationLink {
                            SupportOperatorThreadView(initialThread: thread) {
                                Task { await refresh(showLoading: false) }
                            }
                        } label: {
                            SupportOperatorThreadRow(thread: thread)
                        }
                        .listRowBackground(BudyTheme.surface)
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .refreshable { await refresh(showLoading: false) }
                }
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("support.operator.title".localizedString())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("support.access.logout".localizedString(), role: .destructive) {
                            Task {
                                try? await LaynorPushService.unregisterSupportDevice()
                                SupportAccessSession.revoke()
                                isSupportMode = false
                            }
                        }
                    } label: {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                    }
                    .accessibilityLabel("support.access.active".localizedString())
                }
            }
        }
        .tint(BudyTheme.accentDark)
        .task {
            while !Task.isCancelled && isSupportMode {
                await refresh(showLoading: !hasLoaded)
                try? await Task.sleep(for: .seconds(12))
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await refresh(showLoading: false) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportPushReceived)) { _ in
            Task { await refresh(showLoading: false) }
        }
        .alert("support.error.title".localizedString(), isPresented: $showsError) {
            Button("common.ok".localizedString(), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private func refresh(showLoading: Bool) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let code = SupportAccessSession.code else {
            unreadCount = 0
            isSupportMode = false
            return
        }
        if showLoading { isLoading = true }
        do {
            let loadedThreads = try await SupportOperatorService().openThreads(code: code)
                .filter { $0.status != .closed }
                .sorted { $0.updatedDate > $1.updatedDate }
            threads = loadedThreads
            unreadCount = loadedThreads.reduce(0) {
                $0 + $1.unreadSupportMessageCount
            }
        } catch SupportOperatorError.unauthorized {
            Task { try? await LaynorPushService.unregisterSupportDevice() }
            unreadCount = 0
            SupportAccessSession.revoke()
            isSupportMode = false
        } catch {
            // The inbox is polled continuously. A transient first request
            // should not interrupt the transition into the support screen.
            if hasLoaded {
                errorMessage = error.localizedDescription
                showsError = true
            }
        }
        isLoading = false
        hasLoaded = true
    }
}

private struct SupportOperatorThreadRow: View {
    let thread: SupportOperatorThread

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: thread.categoryValue.icon)
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

                    Text(thread.lastMessagePreview.isEmpty
                        ? (thread.messages.last?.text ?? "")
                        : thread.lastMessagePreview)
                        .font(.system(size: 13))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .lineLimit(2)

                    Text(thread.categoryValue.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(BudyTheme.secondaryInk)
                        .lineLimit(1)
                }

                Spacer(minLength: 4)

                VStack(alignment: .trailing, spacing: 6) {
                    Text(thread.status.title)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(thread.status.color)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    Text(thread.updatedDate, style: .date)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(BudyTheme.secondaryInk)

                    if thread.unreadSupportMessageCount > 0 {
                        Text(verbatim: String(thread.unreadSupportMessageCount))
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundStyle(BudyTheme.accentDark)
                            .frame(minWidth: 24, minHeight: 24)
                            .background(Circle().fill(BudyTheme.accent.opacity(0.16)))
                            .accessibilityLabel(
                                "Unread messages: " + String(thread.unreadSupportMessageCount)
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

private struct SupportOperatorThreadView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("laynor.support.access.granted") private var isSupportMode = false
    @State private var thread: SupportOperatorThread
    @State private var draft = ""
    @State private var isSending = false
    @State private var isClosing = false
    @State private var isRefreshing = false
    @State private var hasShownInitialMessages = false
    @State private var showsCloseConfirmation = false
    @State private var errorMessage = ""
    @State private var showsError = false
    let onChange: () -> Void

    init(initialThread: SupportOperatorThread, onChange: @escaping () -> Void) {
        _thread = State(initialValue: initialThread)
        self.onChange = onChange
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(Array(thread.messages.enumerated()), id: \.element.id) { index, message in
                            SupportOperatorMessageBubble(
                                message: message,
                                onRetry: message.deliveryState == .failed
                                    ? { send(message: message) }
                                    : nil
                                )
                                .id(message.id)
                                .transition(
                                    message.author == .user
                                        ? .asymmetric(
                                            insertion: .offset(x: -30, y: 24)
                                                .combined(with: .scale(scale: 0.82, anchor: .bottomLeading))
                                                .combined(with: .opacity),
                                            removal: .opacity
                                        )
                                        :
                                    message.author == .support
                                        ? .asymmetric(
                                            insertion: .offset(x: 30, y: 24)
                                                .combined(with: .scale(scale: 0.82, anchor: .bottomTrailing))
                                                .combined(with: .opacity),
                                            removal: .opacity
                                        )
                                        : .opacity
                                )
                                .opacity(hasShownInitialMessages ? 1 : 0)
                                .offset(
                                    x: hasShownInitialMessages
                                        ? 0
                                        : (message.author == .user ? -30 : 30),
                                    y: hasShownInitialMessages ? 0 : 24
                                )
                                .scaleEffect(
                                    hasShownInitialMessages ? 1 : 0.82,
                                    anchor: message.author == .user
                                        ? .bottomLeading
                                        : .bottomTrailing
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
                    guard let id = thread.messages.last?.id else { return }
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
                        proxy.scrollTo(id, anchor: .bottom)
                    }
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("support.reply.placeholder".localizedString(), text: $draft, axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.plain)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 10)
                    .background(BudyTheme.surface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .onChange(of: draft) { _, value in
                        if value.count > 2_000 { draft = String(value.prefix(2_000)) }
                    }

                Button(action: send) {
                    Group {
                        if isSending {
                            ProgressView().tint(BudyTheme.onPrimaryAction)
                        } else {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 14, weight: .bold))
                        }
                    }
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
        .background(BudyTheme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                VStack(spacing: 1) {
                    Text(thread.subject)
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text(thread.status.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(thread.status.color)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("support.close".localizedString()) {
                    showsCloseConfirmation = true
                }
                .font(.system(size: 13, weight: .semibold))
                .disabled(isClosing || isSending)
            }
        }
        .task {
            while !Task.isCancelled {
                await refresh()
                try? await Task.sleep(for: .seconds(12))
            }
        }
        .onAppear {
            revealInitialMessages()
            if let threadID = UUID(uuidString: thread.id) {
                SupportChatActivity.open(threadID: threadID)
            }
        }
        .onDisappear {
            if let threadID = UUID(uuidString: thread.id) {
                SupportChatActivity.close(threadID: threadID)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                if let threadID = UUID(uuidString: thread.id) {
                    SupportChatActivity.open(threadID: threadID)
                }
                Task { await refresh() }
            } else if let threadID = UUID(uuidString: thread.id) {
                SupportChatActivity.close(threadID: threadID)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .laynorSupportPushReceived)) { notification in
            guard let pushedID = notification.userInfo?["threadId"] as? String,
                  pushedID.lowercased() == thread.id.lowercased() else { return }
            Task { await refresh() }
        }
        .confirmationDialog(
            "support.operator.close.confirmation".localizedString(),
            isPresented: $showsCloseConfirmation,
            titleVisibility: .visible
        ) {
            Button("support.close".localizedString(), role: .destructive) { close() }
            Button("common.cancel".localizedString(), role: .cancel) {}
        }
        .alert("support.error.title".localizedString(), isPresented: $showsError) {
            Button("common.ok".localizedString(), role: .cancel) {}
        } message: {
            Text(errorMessage)
        }
    }

    private var canSend: Bool {
        !isSending && !isClosing && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        guard canSend, SupportAccessSession.code != nil else { return }
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let messageID = UUID().uuidString.lowercased()
        let createdAt = Date()
        draft = ""
        let message = SupportOperatorMessage(
            id: messageID,
            author: .support,
            text: text,
            createdAt: ISO8601DateFormatter().string(from: createdAt),
            deliveryState: .pending
        )
        withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
            thread.messages.append(message)
        }
        send(message: message)
    }

    private func send(message: SupportOperatorMessage) {
        guard !isSending, let code = SupportAccessSession.code else { return }
        isSending = true
        setDelivery(messageID: message.id, state: .sending)

        Task {
            do {
                try await SupportOperatorService().reply(
                    code: code,
                    threadID: thread.id,
                    messageID: message.id,
                    text: message.text,
                    createdAt: message.date
                )
                setDelivery(messageID: message.id, state: .sent)
                thread.status = .awaitingUser
                thread.updatedAt = ISO8601DateFormatter().string(from: Date())
                onChange()
            } catch SupportOperatorError.unauthorized {
                endSession()
            } catch {
                setDelivery(messageID: message.id, state: .failed)
                show(error)
            }
            isSending = false
        }
    }

    private func setDelivery(messageID: String, state: SupportDeliveryState) {
        guard let index = thread.messages.firstIndex(where: { $0.id == messageID }) else { return }
        thread.messages[index].deliveryState = state
    }

    private func close() {
        guard let code = SupportAccessSession.code else { return }
        isClosing = true
        Task {
            do {
                try await SupportOperatorService().close(code: code, threadID: thread.id)
                onChange()
                dismiss()
            } catch SupportOperatorError.unauthorized {
                endSession()
            } catch {
                show(error)
            }
            isClosing = false
        }
    }

    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        guard let code = SupportAccessSession.code else {
            endSession()
            return
        }
        do {
            let updated = try await SupportOperatorService().openThread(code: code, threadID: thread.id)
            do {
                var merged = updated
                let localTransient = thread.messages.filter {
                    $0.author == .support
                        && ($0.deliveryState == .pending
                            || $0.deliveryState == .sending
                            || $0.deliveryState == .failed)
                }
                let remoteIDs = Set(merged.messages.map(\.id))
                merged.messages.append(contentsOf: localTransient.filter { !remoteIDs.contains($0.id) })
                merged.messages.sort { $0.date < $1.date }
                let existingIDs = Set(thread.messages.map(\.id))
                let hasNewMessages = merged.messages.contains { !existingIDs.contains($0.id) }
                if hasNewMessages {
                    withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                        thread = merged
                    }
                } else {
                    thread = merged
                }
                if thread.messages.contains(where: { $0.author == .user && $0.deliveryState != .read }),
                   let code = SupportAccessSession.code {
                    try? await SupportOperatorService().markRead(code: code, threadID: thread.id)
                    for index in thread.messages.indices where thread.messages[index].author == .user {
                        thread.messages[index].deliveryState = .read
                    }
                    onChange()
                }
            }
        } catch SupportOperatorError.unauthorized {
            endSession()
        } catch {
            // Periodic refresh failures should not interrupt an active reply.
        }
    }

    private func endSession() {
        Task {
            try? await LaynorPushService.unregisterSupportDevice()
            SupportAccessSession.revoke()
            isSupportMode = false
            dismiss()
        }
    }

    private func show(_ error: Error) {
        errorMessage = error.localizedDescription
        showsError = true
    }

    private func revealInitialMessages() {
        guard !hasShownInitialMessages else { return }
        DispatchQueue.main.async {
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                hasShownInitialMessages = true
            }
        }
    }
}

private struct SupportOperatorMessageBubble: View {
    let message: SupportOperatorMessage
    let onRetry: (() -> Void)?

    var body: some View {
        HStack {
            if message.author == .support { Spacer(minLength: 36) }

            HStack(alignment: .bottom, spacing: 7) {
                Text(message.text)
                    .foregroundStyle(message.author == .support ? Color.white : BudyTheme.ink)
                    .font(.system(size: 15))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                HStack(spacing: 5) {
                    Text(message.date, style: .time)
                    if message.author == .support {
                        deliveryIndicator
                            .id(message.deliveryState)
                            .transition(.scale(scale: 0.72).combined(with: .opacity))
                            .animation(
                                .spring(response: 0.28, dampingFraction: 0.76),
                                value: message.deliveryState
                            )
                    }
                }
                .fixedSize()
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(
                    message.author == .support
                        ? Color.white.opacity(0.74)
                        : BudyTheme.secondaryInk
                )
            }
            .padding(.horizontal, 13)
            .padding(.vertical, 9)
            .background(
                message.author == .support ? BudyTheme.accent : BudyTheme.surface,
                in: RoundedRectangle(cornerRadius: 17, style: .continuous)
            )

            if message.author == .user { Spacer(minLength: 36) }
        }
        .frame(maxWidth: .infinity)
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
