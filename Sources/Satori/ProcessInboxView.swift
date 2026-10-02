import SwiftUI

/// Walks through the inbox one item at a time using David Allen's clarify workflow:
/// actionable? → under 2 minutes? → project? → delegate? → defer (next action or date).
struct ProcessInboxView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss

    enum Step { case actionable, notActionable, twoMinutes, singleOrProject, projectForm, whoDoesIt, delegateForm, when }

    @AppStorage(TextScale.key) private var scale = 1.0
    @State private var step: Step = .actionable
    @State private var currentID: UUID?
    @State private var skipped: Set<UUID> = []
    @State private var processed = 0

    @State private var title = ""
    @State private var projectName = ""
    @State private var firstAction = ""
    @State private var waitingOn = ""
    @State private var context: String?
    @State private var projectID: UUID?
    @State private var date: Date = .startOfTomorrow

    private var remaining: [TaskItem] { store.tasks(for: .inbox).filter { !skipped.contains($0.id) } }
    private var current: TaskItem? { currentID.flatMap { store.task($0) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label("Process Inbox", systemImage: "arrow.triangle.branch").scaledFont(.headline)
                Spacer()
                Text("\(remaining.count) left · \(processed) processed")
                    .scaledFont(.caption).foregroundStyle(Theme.dim)
            }

            if let item = current {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("What is it?", text: $title, axis: .vertical)
                        .textFieldStyle(.plain)
                        .scaledFont(.title2, weight: .semibold)
                    if !item.notes.isEmpty {
                        Text(item.notes).foregroundStyle(Theme.dim).lineLimit(3)
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))

                stepView
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
                ContentUnavailableView(
                    "Inbox Zero",
                    systemImage: "checkmark.seal.fill",
                    description: Text(processed > 0 ? "Processed \(processed) item\(processed == 1 ? "" : "s"). Mind like water." : "Nothing to process.")
                )
            }

            Spacer(minLength: 0)

            HStack {
                if current != nil && step != .actionable {
                    KeyButton("Start Over", "[") { step = .actionable }
                }
                if current != nil {
                    KeyButton("Skip", "]") {
                        if let currentID { skipped.insert(currentID) }
                        loadNext()
                    }
                }
                Spacer()
                KeyButton("Done", .cancelAction) { dismiss() }
            }
        }
        .padding(24)
        .background(Theme.bg)
        .frame(width: 540 * scale, height: 470 * scale)
        .onAppear(perform: loadNext)
    }

    @ViewBuilder
    private var stepView: some View {
        switch step {
        case .actionable:
            Question("Is it actionable?", "Does this require you to do something?") {
                KeyButton("Yes", .defaultAction) { step = .twoMinutes }
                KeyButton("No", "1") { step = .notActionable }
            }

        case .notActionable:
            Question("Not actionable. Where does it go?", "Trash it, incubate it, or keep it as reference.") {
                KeyButton("Trash", "1") { finish { $0.trashedAt = Date() } }
                KeyButton("Someday/Maybe", "2") { finish { $0.bucket = .someday } }
                KeyButton("Reference", "3") { finish { $0.bucket = .reference } }
            }

        case .twoMinutes:
            Question("Will it take less than 2 minutes?", "If so, do it right now — it's faster than tracking it.") {
                KeyButton("No", .defaultAction) { step = .singleOrProject }
                KeyButton("Yes — I did it", "1") { finish { $0.completedAt = Date() } }
            }

        case .singleOrProject:
            Question("Is it a single action or a project?", "A project is any outcome needing more than one step.") {
                KeyButton("Single action", .defaultAction) { step = .whoDoesIt }
                KeyButton("It's a project", "1") {
                    projectName = title
                    step = .projectForm
                }
            }

        case .projectForm:
            VStack(alignment: .leading, spacing: 10) {
                Text("Define the project").scaledFont(.title3, weight: .bold)
                TextField("Project name (the outcome)", text: $projectName)
                TextField("Very next action — start with a verb", text: $firstAction)
                Picker("Context", selection: $context) { contextOptions }
                    .fixedSize()
                KeyButton("Create Project", .defaultAction) { makeProject() }
                    .disabled(projectName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .textFieldStyle(.roundedBorder)

        case .whoDoesIt:
            Question("Are you the right person to do it?", "If not, delegate it and track it in Waiting For.") {
                KeyButton("Yes, I'll do it", .defaultAction) { step = .when }
                KeyButton("Delegate it", "1") { step = .delegateForm }
            }

        case .delegateForm:
            VStack(alignment: .leading, spacing: 10) {
                Text("Delegate").scaledFont(.title3, weight: .bold)
                TextField("Who are you waiting on?", text: $waitingOn)
                    .textFieldStyle(.roundedBorder)
                Picker("Project", selection: $projectID) { projectOptions }.fixedSize()
                KeyButton("Move to Waiting For", .defaultAction) {
                    finish { t in
                        t.bucket = .waiting
                        t.waitingOn = waitingOn
                        t.projectID = projectID
                    }
                }
            }

        case .when:
            VStack(alignment: .leading, spacing: 12) {
                Text("Defer it: when will you do it?").scaledFont(.title3, weight: .bold)
                HStack(spacing: 16) {
                    Picker("Context", selection: $context) { contextOptions }.fixedSize()
                    Picker("Project", selection: $projectID) { projectOptions }.fixedSize()
                }
                HStack {
                    KeyButton("As soon as I can", .defaultAction) { finish(asNext(starred: false)) }
                    KeyButton("Today", "1") { finish(asNext(starred: true)) }
                }
                HStack {
                    DatePicker("On", selection: $date, in: Date.startOfTomorrow..., displayedComponents: .date)
                        .fixedSize()
                    KeyButton("Schedule", "2") {
                        finish { t in
                            asNext(starred: false)(&t)
                            t.deferUntil = date.startOfDay
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var contextOptions: some View {
        Text("No context").tag(String?.none)
        ForEach(store.data.contexts, id: \.self) { Text($0).tag(Optional($0)) }
    }

    @ViewBuilder
    private var projectOptions: some View {
        Text("No project").tag(UUID?.none)
        ForEach(store.activeProjects) { Text($0.title).tag(Optional($0.id)) }
    }

    private func asNext(starred: Bool) -> (inout TaskItem) -> Void {
        { t in
            t.bucket = .next
            t.context = context
            t.projectID = projectID
            t.starred = starred
        }
    }

    // MARK: Flow

    private func loadNext() {
        let next = remaining.first
        currentID = next?.id
        title = next?.title ?? ""
        step = .actionable
        projectName = ""
        firstAction = ""
        waitingOn = ""
        context = nil
        projectID = nil
        date = .startOfTomorrow
    }

    private func finish(_ apply: (inout TaskItem) -> Void) {
        guard let id = currentID else { return }
        let parsed = store.parseContext(title)
        store.update(id) { t in
            t.title = parsed.title
            apply(&t)
            if let c = parsed.context { t.context = c }
        }
        processed += 1
        loadNext()
    }

    private func makeProject() {
        guard let id = currentID else { return }
        let parsed = store.parseContext(title)
        title = parsed.title
        if context == nil { context = parsed.context }
        let name = projectName.trimmingCharacters(in: .whitespaces)
        let pid = store.addProject(name)
        let action = firstAction.trimmingCharacters(in: .whitespaces)
        if action.isEmpty {
            // No next action defined yet — the inbox item itself becomes one.
            store.update(id) { t in
                t.title = title
                t.bucket = .next
                t.projectID = pid
                t.context = context
            }
        } else {
            store.update(id) { t in
                t.title = action
                t.bucket = .next
                t.projectID = pid
                t.context = context
                if title != name && title != action {
                    t.notes = [t.notes, "Captured as: \(title)"].filter { !$0.isEmpty }.joined(separator: "\n")
                }
            }
        }
        processed += 1
        loadNext()
    }
}

/// A button that shows the key that triggers it.
struct KeyButton: View {
    let title: String
    let shortcut: KeyboardShortcut
    let action: () -> Void

    init(_ title: String, _ shortcut: KeyboardShortcut, action: @escaping () -> Void) {
        self.title = title
        self.shortcut = shortcut
        self.action = action
    }

    init(_ title: String, _ key: Character, action: @escaping () -> Void) {
        self.init(title, KeyboardShortcut(KeyEquivalent(key), modifiers: .command), action: action)
    }

    private var hint: String {
        switch shortcut.key {
        case .return: "↩"
        case .escape: "esc"
        default: "⌘" + String(shortcut.key.character).uppercased()
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(title)
                Text(hint).scaledFont(.caption).foregroundStyle(Theme.dim)
            }
        }
        .keyboardShortcut(shortcut)
    }
}

private struct Question<Buttons: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let buttons: Buttons

    init(_ title: String, _ detail: String, @ViewBuilder buttons: () -> Buttons) {
        self.title = title
        self.detail = detail
        self.buttons = buttons()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).scaledFont(.title3, weight: .bold)
            Text(detail).foregroundStyle(Theme.dim)
            HStack { buttons }
                .controlSize(.large)
                .padding(.top, 4)
        }
    }
}
