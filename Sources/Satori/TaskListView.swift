import SwiftUI

struct TaskSection: Identifiable {
    let title: String?
    let tasks: [TaskItem]
    var id: String { title ?? "_" }
}

struct TaskListView: View {
    let destination: Destination
    @Environment(Store.self) private var store
    @State private var selection: UUID?
    @State private var newTitle = ""
    @State private var shownIDs: [UUID] = []
    @FocusState private var focus: Pane?

    private var isProjectView: Bool {
        if case .project = destination { return true }
        return false
    }

    var body: some View {
        let tasks = store.tasks(for: destination)
        VStack(alignment: .leading, spacing: 0) {
            Group {
                if case .project(let id) = destination {
                    ProjectHeader(id: id)
                } else {
                    ListHeader(destination: destination)
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 10)

            if let placeholder = destination.placeholder {
                newTaskField(placeholder)
            }

            List(selection: $selection) {
                if destination == .someday, !store.somedayProjects.isEmpty {
                    Section("Projects") {
                        ForEach(store.somedayProjects) { p in
                            Label { Text(p.title).scaledFont(.body) } icon: { Image(systemName: "circle.dashed") }.tag(p.id)
                        }
                    }
                }
                ForEach(sections(tasks)) { section in
                    if let title = section.title {
                        Section {
                            rows(section.tasks)
                        } header: {
                            Text("── " + title).foregroundStyle(Theme.dim).scaledFont(.caption)
                        }
                    } else {
                        rows(section.tasks)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .focused($focus, equals: .list)
            .onKeyPress(characters: ["?"]) { _ in
                store.showShortcuts = true
                return .handled
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first {
                    if store.project(id) != nil {
                        Button("Open Project") { store.go(.project(id)) }
                        Button("Make Active") { store.updateProject(id) { $0.isSomeday = false } }
                    } else {
                        TaskMenu(id: id)
                    }
                }
            } primaryAction: { ids in
                // Return or double-click: open the project, or edit the to-do.
                guard let id = ids.first else { return }
                if store.project(id) != nil { store.go(.project(id)) } else { edit() }
            }
            .onKeyPress(.space) {
                guard destination.placeholder != nil else { return .ignored }
                focus = .newTask
                return .handled
            }
            .onKeyPress(.leftArrow) {
                store.focusRequest = .sidebar
                return .handled
            }
            .onKeyPress(.rightArrow) {
                guard selection != nil else { return .ignored }
                edit()
                return .handled
            }
            .onExitCommand { store.showInspector = false }
            .onDeleteCommand {
                guard let selection, store.task(selection) != nil else { return }
                destination == .trash ? store.deletePermanently(selection) : store.trash(selection)
            }
            .overlay {
                if tasks.isEmpty && !(destination == .someday && !store.somedayProjects.isEmpty) {
                    emptyState
                }
            }
        }
        .inspector(isPresented: Binding(
            get: { store.showInspector },
            set: { store.showInspector = $0 }
        )) {
            Group {
                if let selection, store.task(selection) != nil {
                    TaskDetailView(id: selection, focus: $focus)
                } else {
                    ContentUnavailableView("No Selection", systemImage: "sidebar.right",
                                           description: Text("Select a to-do and press Return to edit it."))
                }
            }
            .onExitCommand { focus = .list }
            .inspectorColumnWidth(min: 260, ideal: 300, max: 420)
        }
        .focusedSceneValue(\.selectedTaskID, selection.flatMap { store.task($0)?.id })
        .onChange(of: store.data.tasks) {
            // When the selected task leaves this list (moved, completed, …), select its
            // neighbour so you can keep triaging from the keyboard.
            let ids = displayedIDs()
            if let s = selection, !ids.contains(s) {
                if let i = shownIDs.firstIndex(of: s) {
                    let candidates = shownIDs[(i + 1)...] + shownIDs[..<i].reversed()
                    selection = candidates.first(where: ids.contains)
                } else {
                    selection = nil
                }
            }
            shownIDs = ids
        }
        .onChange(of: store.focusRequest) { consumeFocusRequest() }
        .onChange(of: focus) { if let focus { store.activePane = focus } }
        .onAppear {
            shownIDs = displayedIDs()
            consumeFocusRequest()
        }
        .toolbar { toolbar }
        .navigationTitle("")
    }

    // MARK: Pieces

    private func newTaskField(_ placeholder: String) -> some View {
        let active = focus == .newTask
        return HStack(spacing: 10) {
            Text("❯")
                .scaledFont(.body, weight: .bold)
                .foregroundStyle(active ? Theme.accent : Theme.faint)
            TextField(placeholder, text: $newTitle)
                .textFieldStyle(.plain)
                .focused($focus, equals: .newTask)
                .onSubmit(addTask)
                .onExitCommand { focus = .list }
                .onKeyPress(.downArrow) {
                    focus = .list
                    return .handled
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
        .overlay(RoundedRectangle(cornerRadius: 6)
            .strokeBorder(active ? Theme.accent.opacity(0.7) : Theme.border, lineWidth: 1))
        .help("New to-do — Space · type @context to tag it · esc to go back")
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func rows(_ tasks: [TaskItem]) -> some View {
        ForEach(tasks) { task in
            TaskRow(task: task, showProject: !isProjectView)
                .scaledFont(.body)
                .listRowSeparator(.hidden)
                .tag(task.id)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        switch destination {
        case .inbox:
            ContentUnavailableView("Inbox Zero", systemImage: "checkmark.seal",
                                   description: Text("Your mind is like water."))
        case .today:
            ContentUnavailableView("Nothing for Today", systemImage: "sun.max",
                                   description: Text("Press ⌘T on a next action to plan it for today."))
        case .project:
            ContentUnavailableView("No Actions Yet", systemImage: "list.bullet",
                                   description: Text("What's the very next physical action?"))
        default:
            ContentUnavailableView("Empty", systemImage: destination.icon)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if destination == .inbox {
            ToolbarItem {
                Button { store.showProcessInbox = true } label: {
                    Label("Process Inbox", systemImage: "arrow.triangle.branch")
                }
                .help("Process Inbox — ⇧⌘I")
                .disabled(store.count(.inbox) == 0)
            }
        }
        if destination == .trash {
            ToolbarItem {
                Button("Empty Trash") { store.emptyTrash() }
                    .disabled(store.count(.trash) == 0)
            }
        }
    }

    // MARK: Logic

    private func addTask() {
        let title = newTitle.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else { return }
        withAnimation { _ = store.addTask(title, to: destination) }
        newTitle = ""
        focus = .newTask
    }

    /// Show the inspector and move the cursor into the title field.
    private func edit() {
        guard selection != nil else { return }
        store.showInspector = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focus = .inspector }
    }

    private func displayedIDs() -> [UUID] {
        sections(store.tasks(for: destination)).flatMap(\.tasks).map(\.id)
    }

    private func consumeFocusRequest() {
        guard let request = store.focusRequest, request == .list || request == .newTask else { return }
        store.focusRequest = nil
        let target: Pane = request == .newTask && destination.placeholder != nil ? .newTask : .list
        DispatchQueue.main.async {
            focus = target
            // Give the arrow keys something to move from.
            if target == .list && selection == nil { selection = displayedIDs().first }
        }
    }

    private func sections(_ tasks: [TaskItem]) -> [TaskSection] {
        switch destination {
        case .next:
            let groups = Dictionary(grouping: tasks) { $0.context ?? "" }
            let known = store.data.contexts.filter { groups[$0] != nil }
            let other = groups.keys.filter { !$0.isEmpty && !store.data.contexts.contains($0) }.sorted()
            var result = (known + other).map { TaskSection(title: $0, tasks: groups[$0]!) }
            if let none = groups[""] { result.append(TaskSection(title: "No Context", tasks: none)) }
            return result
        case .scheduled:
            return groupedByDay(tasks) { $0.deferUntil }
        case .logbook:
            return groupedByDay(tasks) { $0.completedAt }
        case .project:
            let now = Date()
            let order: [(String, (TaskItem) -> Bool)] = [
                ("Inbox", { $0.bucket == .inbox }),
                ("Next Actions", { $0.bucket == .next && !$0.isScheduled(now) }),
                ("Waiting For", { $0.bucket == .waiting && !$0.isScheduled(now) }),
                ("Scheduled", { $0.bucket != .someday && $0.bucket != .reference && $0.isScheduled(now) }),
                ("Someday/Maybe", { $0.bucket == .someday }),
                ("Reference", { $0.bucket == .reference }),
            ]
            return order.compactMap { title, match in
                let items = tasks.filter(match)
                return items.isEmpty ? nil : TaskSection(title: title, tasks: items)
            }
        default:
            return [TaskSection(title: nil, tasks: tasks)]
        }
    }

    private func groupedByDay(_ tasks: [TaskItem], _ date: (TaskItem) -> Date?) -> [TaskSection] {
        var result: [TaskSection] = []
        for t in tasks {
            let title = date(t)?.friendly ?? "—"
            if let last = result.last, last.title == title {
                result[result.count - 1] = TaskSection(title: title, tasks: last.tasks + [t])
            } else {
                result.append(TaskSection(title: title, tasks: [t]))
            }
        }
        return result
    }
}

// MARK: - Row

struct TaskRow: View {
    let task: TaskItem
    var showProject = true
    @Environment(Store.self) private var store
    @State private var checking = false

    var body: some View {
        let done = task.isDone || checking
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button(action: toggle) {
                Text(done ? "[x]" : "[ ]")
                    .scaledFont(.body)
                    .foregroundStyle(done ? Theme.green : Theme.dim)
            }
            .buttonStyle(.plain)
            .disabled(task.trashedAt != nil)
            .help(task.isDone ? "Mark incomplete — ⌘K" : "Complete — ⌘K")

            VStack(alignment: .leading, spacing: 3) {
                Text(task.title.isEmpty ? "New To-Do" : task.title)
                    .scaledFont(.body)
                    .strikethrough(task.isDone, color: Theme.faint)
                    .foregroundStyle(done ? Theme.faint : Theme.text)
                meta
            }
            Spacer(minLength: 4)
            if task.starred && !task.isDone {
                Text("★").foregroundStyle(Theme.yellow)
                    .help("In Today — ⌘T to remove")
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var meta: some View {
        let project = showProject ? task.projectID.flatMap { store.project($0) } : nil
        let parts: [(String, Color)] = [
            project.map { ("▸ " + $0.title, Theme.magenta) },
            task.context.map { ($0, Theme.cyan) },
            (task.bucket == .waiting && !task.waitingOn.isEmpty) ? ("→ " + task.waitingOn, Theme.orange) : nil,
            task.deferUntil.flatMap { task.isScheduled() ? ("starts " + $0.friendly.lowercased(), Theme.red.opacity(0.8)) : nil },
            task.due.map { ("due " + $0.friendly.lowercased(), task.isOverdue ? Theme.red : Theme.dim) },
            task.notes.isEmpty ? nil : ("≡ note", Theme.faint),
        ].compactMap { $0 }
        if !parts.isEmpty {
            parts.dropFirst().reduce(Text(parts[0].0).foregroundColor(parts[0].1)) { line, part in
                line + Text("  ·  ").foregroundColor(Theme.faint) + Text(part.0).foregroundColor(part.1)
            }
            .scaledFont(.caption)
            .lineLimit(1)
        }
    }

    private func toggle() {
        if task.isDone {
            withAnimation { store.toggleComplete(task.id) }
            return
        }
        // Show the check briefly before the task slides out of the list.
        checking = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            withAnimation { store.toggleComplete(task.id) }
            checking = false
        }
    }
}

// MARK: - Context menu

struct TaskMenu: View {
    let id: UUID
    @Environment(Store.self) private var store

    var body: some View {
        if let task = store.task(id) {
            if task.trashedAt != nil {
                Button("Put Back") { store.restore(id) }
                Button("Delete Immediately", role: .destructive) { store.deletePermanently(id) }
            } else {
                Button(task.isDone ? "Mark Incomplete" : "Complete") { store.toggleComplete(id) }
                Button(task.starred ? "Remove from Today" : "Add to Today") { store.toggleStar(id) }
                Divider()
                Menu("Move To") {
                    ForEach(listShortcuts, id: \.move) { item in
                        Button(item.destination.title) { store.send(id, to: item.destination) }
                            .keyboardShortcut(KeyEquivalent(item.move))
                    }
                    Divider()
                    Button("Project…") { store.moveToProjectTaskID = id }
                        .keyboardShortcut("p")
                }
                Menu("Context") {
                    Button("None") { store.update(id) { $0.context = nil } }
                    ForEach(store.data.contexts, id: \.self) { c in
                        Button(c) { store.update(id) { $0.context = c } }
                    }
                }
                Menu("Project") {
                    Button("None") { store.assign(id, toProject: nil) }
                    ForEach(store.activeProjects + store.somedayProjects) { p in
                        Button(p.title) { store.assign(id, toProject: p.id) }
                    }
                }
                Divider()
                Button("Move to Trash", role: .destructive) { store.trash(id) }
            }
        }
    }
}
