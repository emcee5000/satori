import Foundation
import SwiftUI

/// Where a task lives in the GTD system once it has been clarified.
enum Bucket: String, Codable, CaseIterable, Identifiable {
    case inbox, next, waiting, someday, reference

    var id: String { rawValue }

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .next: "Next Actions"
        case .waiting: "Waiting For"
        case .someday: "Someday/Maybe"
        case .reference: "Reference"
        }
    }

    var destination: Destination {
        switch self {
        case .inbox: .inbox
        case .next: .next
        case .waiting: .waiting
        case .someday: .someday
        case .reference: .reference
        }
    }

    init?(_ destination: Destination) {
        guard let match = Bucket.allCases.first(where: { $0.destination == destination }) else { return nil }
        self = match
    }
}

struct TaskItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    var notes = ""
    var bucket: Bucket = .inbox
    var projectID: UUID?
    var context: String?
    var waitingOn = ""
    /// Tickler date: the task stays hidden in Scheduled until this day.
    var deferUntil: Date?
    var due: Date?
    var starred = false
    var createdAt = Date()
    var completedAt: Date?
    var trashedAt: Date?

    var isDone: Bool { completedAt != nil }
    var isActive: Bool { completedAt == nil && trashedAt == nil }
    func isScheduled(_ now: Date = .now) -> Bool { (deferUntil ?? .distantPast) > now }
    var isOverdue: Bool { due.map { $0 < .startOfToday } ?? false }
    var isDueByToday: Bool { due.map { $0 < .startOfTomorrow } ?? false }
}

struct Project: Identifiable, Codable, Hashable {
    var id = UUID()
    var title: String
    /// GTD "successful outcome": what does done look like?
    var outcome = ""
    var isSomeday = false
    var createdAt = Date()
    var completedAt: Date?
    var trashedAt: Date?

    var isActive: Bool { completedAt == nil && trashedAt == nil }
}

struct AppData: Codable {
    var tasks: [TaskItem] = []
    var projects: [Project] = []
    var contexts: [String] = ["@home", "@work", "@computer", "@phone", "@errands", "@anywhere"]
    var lastReview: Date?
    var reviewChecks: [String] = []

    static var welcome: AppData {
        var d = AppData()
        d.tasks = [
            TaskItem(title: "Welcome to Satori — capture everything here first"),
            TaskItem(title: "Process this inbox with ⌘⇧I (or the button in the toolbar)"),
            TaskItem(title: "Use the menu bar icon to capture thoughts from anywhere"),
        ]
        return d
    }
}

// Tolerant decoding so older or newer data files still load.
extension TaskItem {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
        bucket = (try? c.decode(Bucket.self, forKey: .bucket)) ?? .inbox
        projectID = try c.decodeIfPresent(UUID.self, forKey: .projectID)
        context = try c.decodeIfPresent(String.self, forKey: .context)
        waitingOn = try c.decodeIfPresent(String.self, forKey: .waitingOn) ?? ""
        deferUntil = try c.decodeIfPresent(Date.self, forKey: .deferUntil)
        due = try c.decodeIfPresent(Date.self, forKey: .due)
        starred = try c.decodeIfPresent(Bool.self, forKey: .starred) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        trashedAt = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
    }
}

extension Project {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decodeIfPresent(String.self, forKey: .title) ?? ""
        outcome = try c.decodeIfPresent(String.self, forKey: .outcome) ?? ""
        isSomeday = try c.decodeIfPresent(Bool.self, forKey: .isSomeday) ?? false
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        completedAt = try c.decodeIfPresent(Date.self, forKey: .completedAt)
        trashedAt = try c.decodeIfPresent(Date.self, forKey: .trashedAt)
    }
}

extension AppData {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppData()
        tasks = try c.decodeIfPresent([TaskItem].self, forKey: .tasks) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        contexts = try c.decodeIfPresent([String].self, forKey: .contexts) ?? defaults.contexts
        lastReview = try c.decodeIfPresent(Date.self, forKey: .lastReview)
        reviewChecks = try c.decodeIfPresent([String].self, forKey: .reviewChecks) ?? []
    }
}

/// Keyboard-focusable areas of the main window.
enum Pane: Hashable { case sidebar, list, newTask, inspector }

/// Sidebar destinations.
enum Destination: Hashable {
    case inbox, today, next, scheduled, waiting, someday, reference
    case projects, project(UUID)
    case review, logbook, trash

    var title: String {
        switch self {
        case .inbox: "Inbox"
        case .today: "Today"
        case .next: "Next Actions"
        case .scheduled: "Scheduled"
        case .waiting: "Waiting For"
        case .someday: "Someday/Maybe"
        case .reference: "Reference"
        case .projects: "Projects"
        case .project: "Project"
        case .review: "Weekly Review"
        case .logbook: "Logbook"
        case .trash: "Trash"
        }
    }

    var icon: String {
        switch self {
        case .inbox: "tray.fill"
        case .today: "star.fill"
        case .next: "arrow.right.circle.fill"
        case .scheduled: "calendar"
        case .waiting: "hourglass"
        case .someday: "archivebox.fill"
        case .reference: "book.closed.fill"
        case .projects: "square.stack.3d.up.fill"
        case .project: "circle.dashed"
        case .review: "arrow.triangle.2.circlepath"
        case .logbook: "checkmark.square.fill"
        case .trash: "trash.fill"
        }
    }

    var color: Color {
        switch self {
        case .inbox: Theme.blue
        case .today: Theme.yellow
        case .next: Theme.cyan
        case .scheduled: Theme.red
        case .waiting: Theme.orange
        case .someday: Theme.sand
        case .reference: Theme.dim
        case .projects, .project: Theme.magenta
        case .review: Theme.yellow
        case .logbook: Theme.green
        case .trash: Theme.faint
        }
    }

    /// The ⌥⌘ shortcut that jumps here, for tooltips.
    var goKey: String? {
        switch self {
        case .inbox: "⌥⌘I"
        case .today: "⌥⌘T"
        case .next: "⌥⌘N"
        case .scheduled: "⌥⌘U"
        case .waiting: "⌥⌘W"
        case .someday: "⌥⌘S"
        case .reference: "⌥⌘R"
        case .projects: "⌥⌘P"
        case .review: "⇧⌘R"
        case .logbook: "⌥⌘L"
        case .trash: "⇧⌘⌫"
        case .project: nil
        }
    }

    var hint: String {
        switch self {
        case .inbox: "Capture everything. Clarify it later."
        case .today: "Starred actions and anything due today."
        case .next: "The very next physical, visible action — grouped by context."
        case .scheduled: "Your tickler. Items reappear on their start date."
        case .waiting: "Things you've delegated or are expecting from others."
        case .someday: "Incubating ideas. Revisit them during your weekly review."
        case .reference: "Non-actionable information worth keeping."
        case .projects: "Every outcome that takes more than one action needs a next action."
        case .project: ""
        case .review: "Get clear, get current, get creative."
        case .logbook: "Everything you've finished."
        case .trash: "Deleted items. Put them back or empty the trash."
        }
    }

    var placeholder: String? {
        switch self {
        case .inbox: "Capture a thought… (press Space)"
        case .today: "Add an action for today"
        case .next: "Add a next action — start with a verb"
        case .scheduled: "Add something for tomorrow"
        case .waiting: "What are you waiting for?"
        case .someday: "Someday I might…"
        case .reference: "Add a reference note"
        case .project: "Add an action to this project"
        default: nil
        }
    }
}

extension Date {
    static var startOfToday: Date { Calendar.current.startOfDay(for: .now) }
    static var startOfTomorrow: Date { Calendar.current.date(byAdding: .day, value: 1, to: .startOfToday)! }
    var startOfDay: Date { Calendar.current.startOfDay(for: self) }

    var friendly: String {
        let cal = Calendar.current
        if cal.isDateInToday(self) { return "Today" }
        if cal.isDateInTomorrow(self) { return "Tomorrow" }
        if cal.isDateInYesterday(self) { return "Yesterday" }
        if cal.component(.year, from: self) == cal.component(.year, from: .now) {
            return formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
