import SwiftUI

struct RemindersView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var reminders: [LaynorReminder] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if reminders.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(reminders) { reminder in
                                reminderCard(reminder)
                            }
                        }
                        .padding(18)
                        .padding(.bottom, 24)
                    }
                }
            }
            .background(BudyTheme.background.ignoresSafeArea())
            .navigationTitle("reminders.title".localizedString())
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    .accessibilityLabel("reminders.refresh".localizedString())
                }
            }
        }
        .task {
            await refresh()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                Task { await refresh() }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BudyTheme.accentSoft)
                Image(systemName: "bell.badge")
                    .font(.system(size: 29, weight: .semibold))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .frame(width: 72, height: 72)

            Text("reminders.empty.title".localizedString())
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(BudyTheme.ink)

            Text("reminders.empty.subtitle".localizedString())
                .font(.system(size: 14))
                .foregroundStyle(BudyTheme.secondaryInk)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 42)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func reminderCard(_ reminder: LaynorReminder) -> some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(BudyTheme.accentSoft)
                Image(systemName: "bell.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BudyTheme.accentDark)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 5) {
                Text(reminder.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(BudyTheme.ink)
                    .lineLimit(2)

                Label(
                    formatted(reminder.eventDate ?? reminder.fireDate),
                    systemImage: "calendar"
                )
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(BudyTheme.secondaryInk)

                if let eventDate = reminder.eventDate,
                   abs(eventDate.timeIntervalSince(reminder.fireDate)) > 30 {
                    Text(
                        String(
                            format: "reminders.notification_at".localizedString(),
                            formatted(reminder.fireDate)
                        )
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(BudyTheme.secondaryInk.opacity(0.78))
                }
            }

            Spacer(minLength: 8)

            Button(role: .destructive) {
                withAnimation(.easeOut(duration: 0.2)) {
                    LaynorReminderCenter.cancel(reminder)
                    reminders.removeAll { $0.id == reminder.id }
                }
                Task {
                    try? await LaynorPushService.cancelReminder(id: reminder.id)
                }
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BudyTheme.secondaryInk)
                    .frame(width: 38, height: 38)
                    .background(BudyTheme.field, in: Circle())
            }
            .accessibilityLabel("reminders.delete".localizedString())
        }
        .padding(15)
        .background(
            BudyTheme.surface,
            in: RoundedRectangle(cornerRadius: 21, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 21, style: .continuous)
                .stroke(BudyTheme.border)
        }
    }

    private func formatted(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    @MainActor
    private func refresh() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        // Show reminders written by the keyboard immediately. The server
        // request may still be in flight or may have been interrupted when
        // iOS reclaimed the keyboard extension.
        let localReminders = LaynorReminderCenter.scheduledReminders()
        reminders = localReminders

        await LaynorPushService.uploadPendingReminders()

        do {
            let serverReminders = try await LaynorPushService.reminders()
            reminders = merge(
                local: localReminders,
                server: serverReminders
            )
        } catch {
            reminders = localReminders
        }
    }

    private func merge(
        local: [LaynorReminder],
        server: [LaynorReminder]
    ) -> [LaynorReminder] {
        var remindersById = Dictionary(
            uniqueKeysWithValues: local.map { ($0.id, $0) }
        )
        for reminder in server {
            remindersById[reminder.id] = reminder
        }
        return remindersById.values.sorted {
            ($0.eventDate ?? $0.fireDate) < ($1.eventDate ?? $1.fireDate)
        }
    }
}
