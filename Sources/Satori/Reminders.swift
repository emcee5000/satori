import Foundation
import UserNotifications

/// Notifications on the morning a to-do is due. Rescheduled whenever the data
/// changes, including changes synced from the phone.
@MainActor
final class Reminders {
    static let enabledKey = "remindersEnabled"
    static let hourKey = "reminderHour"
    private static let prefix = "due-"
    /// macOS keeps at most 64 pending notifications per app.
    private static let limit = 60

    private var pending: DispatchWorkItem?
    private var asked = false

    init() {
        UserDefaults.standard.register(defaults: [Self.enabledKey: true, Self.hourKey: 9])
    }

    /// Notifications need a real app bundle; `swift run` builds don't have one.
    private var available: Bool { Bundle.main.bundleIdentifier != nil && Bundle.main.bundleURL.pathExtension == "app" }

    func schedule(for data: AppData) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.reschedule(data) }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: work)
    }

    /// The reminders that should be pending: one per open to-do due today or later.
    static func plan(for data: AppData, hour: Int, now: Date = .now, calendar: Calendar = .current) -> [(id: String, title: String, at: Date)] {
        data.tasks.compactMap { t -> (String, String, Date)? in
            guard t.isActive, let due = t.due,
                  let at = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: due), at > now
            else { return nil }
            return (prefix + t.id.uuidString, t.title.isEmpty ? "New To-Do" : t.title, at)
        }
        .sorted { $0.2 < $1.2 }
        .prefix(limit)
        .map { $0 }
    }

    private func reschedule(_ data: AppData) {
        guard available else { return }
        let center = UNUserNotificationCenter.current()
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        let plan = enabled ? Self.plan(for: data, hour: UserDefaults.standard.integer(forKey: Self.hourKey)) : []
        Task {
            let existing = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.prefix) }
            center.removePendingNotificationRequests(withIdentifiers: existing)
            guard !plan.isEmpty else { return }
            if !asked {
                asked = true
                _ = try? await center.requestAuthorization(options: [.alert, .sound])
            }
            for item in plan {
                let content = UNMutableNotificationContent()
                content.title = "Due today"
                content.body = item.title
                content.sound = .default
                let parts = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: item.at)
                let trigger = UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)
                try? await center.add(UNNotificationRequest(identifier: item.id, content: content, trigger: trigger))
            }
        }
    }
}
