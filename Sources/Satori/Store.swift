import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class Store {
    var data: AppData {
        didSet {
            if recordsUndo { undo.record(from: oldValue, to: data) }
            scheduleSave()
            if data.tasks != oldValue.tasks { reminders.schedule(for: data) }
        }
    }

    // UI state shared between windows, menus and the menu bar.
    var selection: Destination? = .inbox
    var showProcessInbox = false
    var showNewProject = false
    var moveToProjectTaskID: UUID?
    var showInspector = false
    var showShortcuts = false
    var showSearch = false
    /// A project waiting for "complete it and its open to-dos?" confirmation.
    var confirmCompleteProjectID: UUID?
    /// A project whose last open to-do was just completed: done, or what's next?
    var finishedProjectID: UUID?
    /// A to-do or project to select once its list appears (e.g. after a search).
    var selectRequest: UUID?
    /// The pane that currently has keyboard focus; drives the status line.
    var activePane: Pane?
    /// Asks a pane to take keyboard focus; the pane clears it once handled.
    var focusRequest: Pane?

    let sync: SyncService
    /// Undo and redo for changes made on this Mac (changes from sync aren't undoable).
    let undo = UndoHistory()
    let reminders = Reminders()
    @ObservationIgnored private(set) var globalCapture: GlobalCapture?
    @ObservationIgnored private var recordsUndo = true
    @ObservationIgnored let fileURL: URL
    @ObservationIgnored private var saveWork: DispatchWorkItem?

    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        // Accept dates with or without fractional seconds (the web app may write either).
        d.dateDecodingStrategy = .custom { decoder in
            let text = try decoder.singleValueContainer().decode(String.self)
            let plain = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            guard let date = plain.date(from: text) ?? fractional.date(from: text) else {
                throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Bad date: \(text)"))
            }
            return date
        }
        return d
    }()

    init() {
        // SATORI_DATA_DIR points the app at a separate data folder (for development, demos
        // or tests). Sync stays off there, so throwaway data never reaches your real repo.
        let customDir = ProcessInfo.processInfo.environment["SATORI_DATA_DIR"]
        sync = SyncService(allowed: customDir == nil)
        let dir = customDir.map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Satori", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("data.json")

        // Carry data over from when the app was called Clarity.
        let legacy = dir.deletingLastPathComponent().appendingPathComponent("Clarity/data.json")
        if !FileManager.default.fileExists(atPath: fileURL.path),
           FileManager.default.fileExists(atPath: legacy.path) {
            try? FileManager.default.copyItem(at: legacy, to: fileURL)
        }

        if let raw = try? Data(contentsOf: fileURL) {
            if let decoded = try? Self.decoder.decode(AppData.self, from: raw) {
                data = decoded
            } else {
                // Never silently overwrite a file we couldn't read; set it aside.
                let backup = dir.appendingPathComponent("data-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? FileManager.default.copyItem(at: fileURL, to: backup)
                data = AppData()
            }
        } else {
            data = AppData.welcome
        }

        sync.store = self
        sync.restart()
        reminders.schedule(for: data)
        globalCapture = GlobalCapture(store: self)

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.saveNow() }
        }
    }

    // MARK: Persistence

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.saveNow() }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func saveNow() {
        saveWork?.cancel()
        saveWork = nil
        do {
            try Self.encoder.encode(data).write(to: fileURL, options: .atomic)
        } catch {
            NSLog("Satori: failed to save: \(error)")
        }
        sync.schedule()
    }

    /// Replaces local data with a merged copy from sync.
    func applySynced(_ merged: AppData) {
        recordsUndo = false
        data = merged
        recordsUndo = true
    }

    func undoLastChange() { applyHistory(undo.popUndo(), redo: false) }
    func redoLastChange() { applyHistory(undo.popRedo(), redo: true) }

    private func applyHistory(_ step: UndoHistory.Step?, redo: Bool) {
        guard let step else { return }
        var copy = data
        let inverse = step.apply(to: &copy)
        recordsUndo = false
        data = copy
        recordsUndo = true
        redo ? undo.pushUndo(inverse) : undo.pushRedo(inverse)
    }

    // MARK: Queries

    func tasks(for destination: Destination) -> [TaskItem] {
        let now = Date()
        let active = data.tasks.filter(\.isActive)
        switch destination {
        case .inbox:
            return active.filter { $0.bucket == .inbox }
        case .today:
            return active.filter {
                !$0.isScheduled(now) && $0.bucket != .reference && $0.bucket != .someday
                    && ($0.starred || $0.isDueByToday)
            }
        case .next:
            return active.filter { $0.bucket == .next && !$0.isScheduled(now) && projectIsLive($0.projectID) }
        case .scheduled:
            return active.filter { $0.isScheduled(now) }
                .sorted { ($0.deferUntil ?? now) < ($1.deferUntil ?? now) }
        case .waiting:
            return active.filter { $0.bucket == .waiting && !$0.isScheduled(now) }
        case .someday:
            return active.filter { $0.bucket == .someday }
        case .reference:
            return active.filter { $0.bucket == .reference }
        case .project(let id):
            return active.filter { $0.projectID == id }
        case .logbook:
            return data.tasks.filter { $0.isDone && $0.trashedAt == nil }
                .sorted { ($0.completedAt ?? now) > ($1.completedAt ?? now) }
        case .trash:
            return data.tasks.filter { $0.trashedAt != nil }
                .sorted { ($0.trashedAt ?? now) > ($1.trashedAt ?? now) }
        case .projects, .review:
            return []
        }
    }

    func count(_ destination: Destination) -> Int { tasks(for: destination).count }

    /// The list where a to-do lives, for jumping to it from search.
    func home(of task: TaskItem) -> Destination {
        if task.trashedAt != nil { return .trash }
        if task.isDone { return .logbook }
        if let id = task.projectID, project(id) != nil { return .project(id) }
        if task.isScheduled() { return .scheduled }
        return task.bucket.destination
    }

    /// To-dos and projects whose title or notes contain every word of the query.
    func search(_ query: String) -> (projects: [Project], tasks: [TaskItem]) {
        let words = query.split(separator: " ").map(String.init)
        guard !words.isEmpty else { return ([], []) }
        func matches(_ text: String) -> Bool { words.allSatisfy { text.localizedStandardContains($0) } }
        let projects = data.projects.filter { $0.trashedAt == nil && matches($0.title + " " + $0.outcome) }
        // Open to-dos first, then finished ones, newest first within each.
        let tasks = data.tasks.filter { $0.trashedAt == nil && matches($0.title + " " + $0.notes) }
            .sorted { ($0.isDone ? 1 : 0, $1.updatedAt) < ($1.isDone ? 1 : 0, $0.updatedAt) }
        return (projects, tasks)
    }

    func task(_ id: UUID) -> TaskItem? { data.tasks.first { $0.id == id } }

    func binding(for id: UUID) -> Binding<TaskItem>? {
        guard let current = task(id) else { return nil }
        return Binding(
            get: { self.task(id) ?? current },
            set: { new in self.update(id) { $0 = new } }
        )
    }

    var reviewIsDue: Bool {
        guard let last = data.lastReview else { return true }
        return Date().timeIntervalSince(last) > 7 * 24 * 3600
    }

    // MARK: Task mutations

    func update(_ id: UUID, _ change: (inout TaskItem) -> Void) {
        guard let i = data.tasks.firstIndex(where: { $0.id == id }) else { return }
        var task = data.tasks[i]
        change(&task)
        guard task != data.tasks[i] else { return }
        task.updatedAt = Date()
        data.tasks[i] = task
    }

    /// Pulls a known "@context" word out of a title, e.g. "Call Bob @phone".
    func parseContext(_ title: String) -> (title: String, context: String?) {
        var context: String?
        let words = title.split(separator: " ", omittingEmptySubsequences: false).filter { word in
            guard word.hasPrefix("@"), context == nil,
                  let match = data.contexts.first(where: { $0.caseInsensitiveCompare(word) == .orderedSame })
            else { return true }
            context = match
            return false
        }
        return (words.joined(separator: " ").trimmingCharacters(in: .whitespaces), context)
    }

    @discardableResult
    func addTask(_ title: String, to destination: Destination) -> UUID {
        let parsed = parseContext(title)
        var t = TaskItem(title: parsed.title)
        t.context = parsed.context
        switch destination {
        case .today: t.bucket = .next; t.starred = true
        case .next: t.bucket = .next
        case .scheduled: t.bucket = .next; t.deferUntil = .startOfTomorrow
        case .waiting: t.bucket = .waiting
        case .someday: t.bucket = .someday
        case .reference: t.bucket = .reference
        case .project(let id): t.bucket = .next; t.projectID = id
        default: break
        }
        data.tasks.append(t)
        return t.id
    }

    func toggleComplete(_ id: UUID) {
        guard let task = task(id) else { return }
        defer { if task.completedAt == nil { checkProjectFinished(after: task) } }
        if task.completedAt == nil, let next = task.nextOccurrence() {
            // Complete it and add the next one as a single change, so one undo reverts both.
            var copy = data
            if let i = copy.tasks.firstIndex(where: { $0.id == id }) {
                copy.tasks[i].completedAt = Date()
                copy.tasks[i].updatedAt = Date()
            }
            copy.tasks.append(next)
            data = copy
        } else {
            update(id) { $0.completedAt = $0.completedAt == nil ? Date() : nil }
        }
    }

    func toggleStar(_ id: UUID) {
        update(id) { $0.starred.toggle() }
    }

    func move(_ id: UUID, to bucket: Bucket) {
        send(id, to: bucket.destination)
    }

    /// Moves a task so that it shows up in the given sidebar list.
    func send(_ id: UUID, to destination: Destination) {
        update(id) { t in
            let unclarified: Set<Bucket> = [.inbox, .someday, .reference]
            switch destination {
            case .today:
                if unclarified.contains(t.bucket) { t.bucket = .next }
                t.deferUntil = nil
                t.starred = true
            case .scheduled:
                if unclarified.contains(t.bucket) { t.bucket = .next }
                if !t.isScheduled() { t.deferUntil = .startOfTomorrow }
                t.starred = false
            case .inbox, .someday, .reference:
                t.bucket = Bucket(destination)!
                t.deferUntil = nil
                t.starred = false
            case .next, .waiting:
                t.bucket = Bucket(destination)!
                t.deferUntil = nil
            default:
                break
            }
        }
    }

    func assign(_ id: UUID, toProject projectID: UUID?) {
        update(id) { t in
            t.projectID = projectID
            if projectID != nil && t.bucket == .inbox { t.bucket = .next }
        }
    }

    func trash(_ id: UUID) {
        update(id) { $0.trashedAt = Date() }
    }

    func restore(_ id: UUID) {
        update(id) { t in
            t.trashedAt = nil
            if let pid = t.projectID, project(pid)?.trashedAt != nil { t.projectID = nil }
        }
    }

    func deletePermanently(_ id: UUID) {
        data.deleted[id.uuidString] = Date()
        data.tasks.removeAll { $0.id == id }
    }

    func emptyTrash() {
        let now = Date()
        for t in data.tasks where t.trashedAt != nil { data.deleted[t.id.uuidString] = now }
        for p in data.projects where p.trashedAt != nil { data.deleted[p.id.uuidString] = now }
        data.tasks.removeAll { $0.trashedAt != nil }
        data.projects.removeAll { $0.trashedAt != nil }
    }

    // MARK: Projects

    var activeProjects: [Project] { data.projects.filter { $0.isActive && !$0.isSomeday } }
    var somedayProjects: [Project] { data.projects.filter { $0.isActive && $0.isSomeday } }
    var completedProjects: [Project] {
        data.projects.filter { $0.completedAt != nil && $0.trashedAt == nil }
            .sorted { ($0.completedAt ?? .now) > ($1.completedAt ?? .now) }
    }

    func project(_ id: UUID) -> Project? { data.projects.first { $0.id == id } }

    func projectBinding(_ id: UUID) -> Binding<Project>? {
        guard let current = project(id) else { return nil }
        return Binding(
            get: { self.project(id) ?? current },
            set: { new in self.updateProject(id) { $0 = new } }
        )
    }

    func updateProject(_ id: UUID, _ change: (inout Project) -> Void) {
        guard let i = data.projects.firstIndex(where: { $0.id == id }) else { return }
        var project = data.projects[i]
        change(&project)
        guard project != data.projects[i] else { return }
        project.updatedAt = Date()
        data.projects[i] = project
    }

    /// Tasks in a someday or finished project shouldn't clutter Next Actions.
    private func projectIsLive(_ id: UUID?) -> Bool {
        guard let id, let p = project(id) else { return true }
        return p.isActive && !p.isSomeday
    }

    @discardableResult
    func addProject(_ title: String) -> UUID {
        let p = Project(title: title)
        data.projects.append(p)
        return p.id
    }

    func nextActionCount(_ p: Project) -> Int {
        let now = Date()
        return tasks(for: .project(p.id)).filter { $0.bucket == .next && !$0.isScheduled(now) }.count
    }

    /// GTD: an active project without a next action is stuck.
    func isStalled(_ p: Project) -> Bool { p.isActive && !p.isSomeday && nextActionCount(p) == 0 }

    func progress(_ p: Project) -> Double {
        let all = data.tasks.filter { $0.projectID == p.id && $0.trashedAt == nil }
        guard !all.isEmpty else { return p.completedAt == nil ? 0 : 1 }
        return Double(all.filter(\.isDone).count) / Double(all.count)
    }

    /// To-dos in a project that aren't done or trashed.
    func openTasks(in id: UUID) -> [TaskItem] {
        data.tasks.filter { $0.projectID == id && $0.isActive }
    }

    /// Completes a project, asking first if it still has open to-dos.
    func requestCompleteProject(_ id: UUID) {
        guard let p = project(id), p.isActive else { return }
        if openTasks(in: id).isEmpty { completeProject(id) } else { confirmCompleteProjectID = id }
    }

    /// Marks a project and its open to-dos done, as one undoable change.
    func completeProject(_ id: UUID) {
        let now = Date()
        var copy = data
        for i in copy.tasks.indices where copy.tasks[i].projectID == id && copy.tasks[i].isActive {
            copy.tasks[i].completedAt = now
            copy.tasks[i].updatedAt = now
        }
        if let i = copy.projects.firstIndex(where: { $0.id == id }) {
            copy.projects[i].completedAt = now
            copy.projects[i].updatedAt = now
        }
        data = copy
        if selection == .project(id) { go(.projects) }
    }

    func reopenProject(_ id: UUID) {
        updateProject(id) { $0.completedAt = nil }
    }

    /// Opens a project with the cursor in its new to-do field.
    func addNextAction(to id: UUID) {
        selection = .project(id)
        DispatchQueue.main.async { self.focusRequest = .newTask }
    }

    /// GTD: when a project runs out of actions, it's either done or needs its next one.
    private func checkProjectFinished(after task: TaskItem) {
        guard let pid = task.projectID, let p = project(pid), p.isActive, self.task(task.id)?.isDone == true,
              openTasks(in: pid).isEmpty else { return }
        finishedProjectID = pid
    }

    func trashProject(_ id: UUID) {
        let now = Date()
        for i in data.tasks.indices where data.tasks[i].projectID == id && data.tasks[i].isActive {
            data.tasks[i].trashedAt = now
            data.tasks[i].updatedAt = now
        }
        updateProject(id) { $0.trashedAt = now }
        if selection == .project(id) { selection = .projects }
    }

    // MARK: Commands

    func requestNewTask() {
        if selection?.placeholder == nil { selection = .inbox }
        focusRequest = .newTask
    }

    /// Navigate to a list and put keyboard focus in it.
    func go(_ destination: Destination) {
        selection = destination
        // Ask on the next run-loop pass, once the new list exists; otherwise the
        // list being replaced claims the focus and the new one appears unfocused.
        DispatchQueue.main.async { self.focusRequest = .list }
    }
}
