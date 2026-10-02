import SwiftUI

/// Inspector for editing a single task.
struct TaskDetailView: View {
    let id: UUID
    var focus: FocusState<Pane?>.Binding
    @Environment(Store.self) private var store

    var body: some View {
        if let t = store.binding(for: id) {
            Form {
                Section {
                    // Grouped forms right-align field text; hide the labels so these read left to right.
                    TextField("Title", text: t.title, prompt: Text("Title"), axis: .vertical)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .scaledFont(.title3)
                        .focused(focus, equals: .inspector)
                        .onSubmit { focus.wrappedValue = .list }
                    TextField("Notes", text: t.notes, prompt: Text("Notes"), axis: .vertical)
                        .labelsHidden()
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(4...12)
                }

                Section("Organize") {
                    Picker("List", selection: t.bucket) {
                        ForEach(Bucket.allCases) { Text($0.title).tag($0) }
                    }
                    .help("From the list: ⌘I inbox · ⌘N next · ⌘W waiting · ⌘S someday · ⌘R reference")
                    if t.wrappedValue.bucket == .waiting {
                        TextField("Waiting on", text: t.waitingOn, prompt: Text("Person"))
                    }
                    Picker("Project", selection: t.projectID) {
                        Text("None").tag(UUID?.none)
                        ForEach(store.activeProjects + store.somedayProjects) { p in
                            Text(p.title).tag(Optional(p.id))
                        }
                    }
                    Picker("Context", selection: t.context) {
                        Text("None").tag(String?.none)
                        ForEach(store.data.contexts, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                    Toggle("Today", isOn: t.starred)
                        .help("⌘T")
                }

                Section("Dates") {
                    OptionalDatePicker(title: "Start date", help: "Hidden in Scheduled until this day · ⌘D = tomorrow", date: t.deferUntil)
                    OptionalDatePicker(title: "Due date", help: "Only for real deadlines", date: t.due)
                }

                Section {
                    LabeledContent("Created", value: t.wrappedValue.createdAt.formatted(date: .abbreviated, time: .shortened))
                    if let done = t.wrappedValue.completedAt {
                        LabeledContent("Completed", value: done.formatted(date: .abbreviated, time: .shortened))
                    }
                    HStack {
                        Button(t.wrappedValue.isDone ? "Mark Incomplete" : "Complete") { store.toggleComplete(id) }
                            .help("⌘K")
                        Spacer()
                        if t.wrappedValue.trashedAt != nil {
                            Button("Put Back") { store.restore(id) }
                        } else {
                            Button("Trash", role: .destructive) { store.trash(id) }
                                .help("⌫ from the list")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .background(Theme.panel)
        }
    }
}

struct OptionalDatePicker: View {
    let title: String
    let help: String
    @Binding var date: Date?

    var body: some View {
        Toggle(isOn: Binding(
            get: { date != nil },
            set: { date = $0 ? .startOfTomorrow : nil }
        )) {
            Text(title)
            Text(help)
        }
        if let current = date {
            DatePicker(title, selection: Binding(
                get: { current },
                set: { date = $0.startOfDay }
            ), displayedComponents: .date)
            .labelsHidden()
        }
    }
}

// MARK: - Projects

struct ProjectHeader: View {
    let id: UUID
    @Environment(Store.self) private var store

    var body: some View {
        if let p = store.projectBinding(id) {
            let project = p.wrappedValue
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    ProgressRing(progress: store.progress(project)).frame(width: 22, height: 22)
                    TextField("Project Name", text: p.title)
                        .scaledFont(.title2, weight: .bold)
                        .textFieldStyle(.plain)
                    Menu {
                        Button("Complete Project") { store.completeProject(id); store.go(.projects) }
                        Button(project.isSomeday ? "Make Active" : "Move to Someday/Maybe") {
                            store.updateProject(id) { $0.isSomeday.toggle() }
                        }
                        Divider()
                        Button("Delete Project", role: .destructive) { store.trashProject(id) }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .help("Complete, incubate or delete this project")
                    .menuIndicator(.hidden)
                    .fixedSize()
                }
                TextField("# successful outcome — what does “done” look like?", text: p.outcome, axis: .vertical)
                    .textFieldStyle(.plain)
                    .scaledFont(.callout)
                    .foregroundStyle(Theme.dim)
                if project.isSomeday {
                    Text("# incubating in someday/maybe — actions are hidden from next actions")
                        .scaledFont(.callout).foregroundStyle(Theme.sand)
                } else if store.isStalled(project) {
                    Text("! no next action — what's the very next physical step?")
                        .scaledFont(.callout).foregroundStyle(Theme.orange)
                }
            }
        }
    }
}

struct ProjectsOverview: View {
    @Environment(Store.self) private var store
    @State private var selection: UUID?
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ListHeader(destination: .projects)
                .padding(.horizontal, 20).padding(.top, 14).padding(.bottom, 10)
            List(selection: $selection) {
                Section("Active") {
                    if store.activeProjects.isEmpty {
                        Text("No active projects. Create one with ⌥⇧⌘N.").foregroundStyle(Theme.dim)
                    }
                    ForEach(store.activeProjects) { ProjectRow(project: $0).scaledFont(.body).listRowSeparator(.hidden).tag($0.id) }
                }
                if !store.somedayProjects.isEmpty {
                    Section("Someday/Maybe") {
                        ForEach(store.somedayProjects) { ProjectRow(project: $0).scaledFont(.body).listRowSeparator(.hidden).tag($0.id) }
                    }
                }
                if !store.completedProjects.isEmpty {
                    Section("Completed") {
                        ForEach(store.completedProjects.prefix(20)) { p in
                            HStack {
                                Text("[x]").foregroundStyle(Theme.green)
                                Text(p.title).scaledFont(.body).foregroundStyle(Theme.dim)
                                Spacer()
                                Text(p.completedAt?.friendly ?? "").scaledFont(.caption).foregroundStyle(.tertiary)
                            }
                            .scaledFont(.body)
                            .tag(p.id)
                        }
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .onChange(of: focused) { if focused { store.activePane = .list } }
            .onKeyPress(characters: ["?"]) { _ in
                store.showShortcuts = true
                return .handled
            }
            .contextMenu(forSelectionType: UUID.self) { ids in
                if let id = ids.first, let p = store.project(id) {
                    Button("Open Project") { store.go(.project(id)) }
                    if p.completedAt != nil {
                        Button("Reopen") { store.updateProject(id) { $0.completedAt = nil } }
                    } else {
                        Button("Complete Project") { store.completeProject(id) }
                        Button(p.isSomeday ? "Make Active" : "Move to Someday/Maybe") {
                            store.updateProject(id) { $0.isSomeday.toggle() }
                        }
                    }
                }
            } primaryAction: { ids in
                if let id = ids.first { store.go(.project(id)) }
            }
            .onKeyPress(.leftArrow) { store.focusRequest = .sidebar; return .handled }
            .onKeyPress(.rightArrow) {
                if let selection { store.go(.project(selection)) }
                return .handled
            }
        }
        .onChange(of: store.focusRequest) { consumeFocusRequest() }
        .onAppear { consumeFocusRequest() }
        .toolbar {
            Button { store.showNewProject = true } label: { Label("New Project", systemImage: "plus") }
        }
    }

    private func consumeFocusRequest() {
        guard store.focusRequest == .list else { return }
        store.focusRequest = nil
        DispatchQueue.main.async {
            focused = true
            if selection == nil { selection = (store.activeProjects + store.somedayProjects).first?.id }
        }
    }
}

struct ProjectRow: View {
    let project: Project
    @Environment(Store.self) private var store

    var body: some View {
        HStack(spacing: 10) {
                ProgressRing(progress: store.progress(project)).frame(width: 16, height: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(project.title.isEmpty ? "Untitled Project" : project.title).scaledFont(.body)
                    if !project.outcome.isEmpty {
                        Text(project.outcome).scaledFont(.caption).foregroundStyle(Theme.dim).lineLimit(1)
                    }
                }
                Spacer()
                if store.isStalled(project) {
                    Text("! no next action")
                        .scaledFont(.caption)
                        .foregroundStyle(Theme.orange)
                } else if !project.isSomeday {
                    let n = store.nextActionCount(project)
                    Text("\(n) next action\(n == 1 ? "" : "s")").scaledFont(.caption).foregroundStyle(Theme.dim)
                }
                Image(systemName: "chevron.right").scaledFont(.caption).foregroundStyle(.tertiary)
            }
        .padding(.vertical, 3)
    }
}

/// Type-to-filter project picker (⌘P). ↑↓ choose, Return picks, Esc cancels.
struct MoveToProjectView: View {
    let taskID: UUID
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TextScale.key) private var scale = 1.0
    @State private var filter = ""
    @State private var highlighted = 0
    @FocusState private var fieldFocused: Bool

    private enum Choice: Identifiable {
        case project(Project), create(String), remove
        var id: String {
            switch self {
            case .project(let p): p.id.uuidString
            case .create: "create"
            case .remove: "remove"
            }
        }
    }

    private var choices: [Choice] {
        let all = store.activeProjects + store.somedayProjects
        let name = filter.trimmingCharacters(in: .whitespaces)
        var result = (name.isEmpty ? all : all.filter { $0.title.localizedCaseInsensitiveContains(name) })
            .map(Choice.project)
        if !name.isEmpty && !all.contains(where: { $0.title.caseInsensitiveCompare(name) == .orderedSame }) {
            result.append(.create(name))
        }
        if store.task(taskID)?.projectID != nil { result.append(.remove) }
        return result
    }

    var body: some View {
        let choices = choices
        VStack(alignment: .leading, spacing: 10) {
            Text("Move to Project").scaledFont(.headline)
            TextField("Type a project name", text: $filter)
                .textFieldStyle(.roundedBorder)
                .focused($fieldFocused)
                .onSubmit { if choices.indices.contains(highlighted) { choose(choices[highlighted]) } }
                .onKeyPress(.downArrow) {
                    highlighted = min(highlighted + 1, max(choices.count - 1, 0))
                    return .handled
                }
                .onKeyPress(.upArrow) {
                    highlighted = max(highlighted - 1, 0)
                    return .handled
                }
                .onChange(of: filter) { highlighted = 0 }
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(choices.enumerated()), id: \.element.id) { i, choice in
                        label(choice)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 3).padding(.horizontal, 6)
                            .background(RoundedRectangle(cornerRadius: 5)
                                .fill(i == highlighted ? Color.accentColor.opacity(0.25) : .clear))
                            .contentShape(Rectangle())
                            .onTapGesture { choose(choice) }
                            .id(choice.id)
                    }
                }
                .listStyle(.inset)
                .onChange(of: highlighted) {
                    if choices.indices.contains(highlighted) { proxy.scrollTo(choices[highlighted].id) }
                }
            }
            HStack {
                Text("↑↓ choose · Return picks · Esc cancels").scaledFont(.caption).foregroundStyle(Theme.dim)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(18)
        .background(Theme.bg)
        .frame(width: 380 * scale, height: 380 * scale)
        .onAppear { fieldFocused = true }
    }

    @ViewBuilder
    private func label(_ choice: Choice) -> some View {
        switch choice {
        case .project(let p):
            Label(p.title.isEmpty ? "Untitled Project" : p.title,
                  systemImage: p.isSomeday ? "archivebox" : "circle.dashed")
        case .create(let name):
            Label("New Project “\(name)”", systemImage: "plus")
        case .remove:
            Label("Remove from Project", systemImage: "xmark.circle")
        }
    }

    private func choose(_ choice: Choice) {
        switch choice {
        case .project(let p): store.assign(taskID, toProject: p.id)
        case .create(let name): store.assign(taskID, toProject: store.addProject(name))
        case .remove: store.assign(taskID, toProject: nil)
        }
        dismiss()
    }
}
