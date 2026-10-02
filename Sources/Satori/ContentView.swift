import SwiftUI

struct ContentView: View {
    @Environment(Store.self) private var store
    @State private var newProjectName = ""

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            Sidebar()
                .navigationSplitViewColumnWidth(min: 200, ideal: 230)
        } detail: {
            VStack(spacing: 0) {
                switch store.selection ?? .inbox {
                case .review: WeeklyReviewView()
                case .projects: ProjectsOverview()
                case let d: TaskListView(destination: d).id(d)
                }
                StatusLine()
            }
            .background(Theme.bg)
            .toolbarBackground(Theme.bg, for: .windowToolbar)
        }
        .sheet(isPresented: $store.showProcessInbox) {
            ProcessInboxView().scaledFont(.body)
        }
        .sheet(isPresented: Binding(
            get: { store.moveToProjectTaskID != nil },
            set: { if !$0 { store.moveToProjectTaskID = nil } }
        )) {
            if let id = store.moveToProjectTaskID {
                MoveToProjectView(taskID: id).scaledFont(.body)
            }
        }
        .onAppear {
            // Wait for the window to become key, otherwise the sidebar keeps focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { store.focusRequest = .list }
        }
        .sheet(isPresented: $store.showShortcuts) {
            ShortcutsView().scaledFont(.body)
        }
        .sheet(isPresented: $store.showSearch) {
            SearchView().scaledFont(.body)
        }
        .alert("New Project", isPresented: $store.showNewProject) {
            TextField("Project name", text: $newProjectName)
            Button("Create") {
                let name = newProjectName.trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { store.go(.project(store.addProject(name))) }
                newProjectName = ""
            }
            Button("Cancel", role: .cancel) { newProjectName = "" }
        } message: {
            Text("A project is any outcome that takes more than one action.")
        }
    }
}

struct Sidebar: View {
    @Environment(Store.self) private var store
    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var store = store
        List(selection: $store.selection) {
            Section {
                row(.inbox, badge: store.count(.inbox))
                row(.today, badge: store.count(.today))
            }
            Section("Organize") {
                row(.next, badge: store.count(.next))
                row(.scheduled)
                row(.waiting, badge: store.count(.waiting))
                row(.someday)
                row(.reference)
            }
            Section("Projects") {
                row(.projects)
                ForEach(store.activeProjects) { p in
                    Label {
                        Text(p.title.isEmpty ? "Untitled Project" : p.title).scaledFont(.body)
                    } icon: {
                        if store.isStalled(p) {
                            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Theme.orange)
                        } else {
                            ProgressRing(progress: store.progress(p)).frame(width: 12, height: 12)
                        }
                    }
                    .help(store.isStalled(p) ? "No next action — what's the very next step?" : "Project · ↩ to open")
                    .scaledFont(.body)
                    .tag(Destination.project(p.id))
                }
            }
            Section("Reflect") {
                row(.review)
                    .badge(store.reviewIsDue ? Text("due").foregroundStyle(Theme.yellow) : nil)
                row(.logbook)
                row(.trash)
            }
        }
        .scaledFont(.body)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .focused($focused)
        .onChange(of: focused) { if focused { store.activePane = .sidebar } }
        .onKeyPress(characters: ["?"]) { _ in
            store.showShortcuts = true
            return .handled
        }
        // ↑↓ picks a list; → or Return jumps into it.
        .contextMenu(forSelectionType: Destination.self) { _ in
            EmptyView()
        } primaryAction: { _ in
            store.focusRequest = .list
        }
        .onKeyPress(.rightArrow) {
            store.focusRequest = .list
            return .handled
        }
        .onKeyPress(.space) {
            store.focusRequest = .newTask
            return .handled
        }
        .onChange(of: store.focusRequest) {
            guard store.focusRequest == .sidebar else { return }
            store.focusRequest = nil
            focused = true
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button { store.showNewProject = true } label: {
                    Text("+ new project").foregroundStyle(Theme.dim)
                }
                .buttonStyle(.borderless)
                .help("New project — ⌥⇧⌘N")
                Spacer()
            }
            .scaledFont(.callout)
            .padding(10)
            .background(Theme.sidebar)
        }
    }

    private func row(_ d: Destination, badge: Int = 0) -> some View {
        Label {
            Text(d.title).scaledFont(.body)
        } icon: {
            Image(systemName: d.icon).foregroundStyle(d.color.opacity(0.85))
        }
        .badge(badge)
        .scaledFont(.body)
        .help(d.goKey.map { "\(d.title) — \($0)" } ?? d.title)
        .tag(d)
    }
}

struct ProgressRing: View {
    var progress: Double

    var body: some View {
        ZStack {
            Circle().stroke(Theme.magenta.opacity(0.35), lineWidth: 1.5)
            Circle().trim(from: 0, to: progress)
                .stroke(Theme.magenta, style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

/// Prompt-style title + GTD hint as a comment, shown at the top of each list.
struct ListHeader: View {
    let destination: Destination
    @Environment(Store.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("❯").foregroundStyle(destination.color)
                Text(destination.title)
                let n = store.count(destination)
                if n > 0 { Text("\(n)").foregroundStyle(Theme.faint).scaledFont(.title3) }
            }
            .scaledFont(.title2, weight: .bold)
            Text("# " + destination.hint)
                .foregroundStyle(Theme.faint)
                .scaledFont(.callout)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
