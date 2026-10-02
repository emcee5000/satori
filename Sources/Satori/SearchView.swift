import SwiftUI

/// ⌘F: find any to-do or project by its title or notes, then jump to it.
struct SearchView: View {
    @Environment(Store.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private enum Hit: Identifiable {
        case project(Project), task(TaskItem)
        var id: UUID {
            switch self {
            case .project(let p): p.id
            case .task(let t): t.id
            }
        }
    }

    private var hits: [Hit] {
        let found = store.search(query)
        return (found.projects.map(Hit.project) + found.tasks.map(Hit.task)).prefix(50).map { $0 }
    }

    var body: some View {
        let hits = hits
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                Text("❯").scaledFont(.body, weight: .bold).foregroundStyle(Theme.accent)
                TextField("Find a to-do or project…", text: $query)
                    .textFieldStyle(.plain)
                    .focused($focused)
                    .onSubmit { open(hits) }
                    .onKeyPress(.downArrow) { move(1, in: hits) }
                    .onKeyPress(.upArrow) { move(-1, in: hits) }
            }
            .padding(14)
            .background(Theme.panel)

            Divider()

            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(hits.enumerated()), id: \.element.id) { i, hit in
                            row(hit)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 7)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(i == selected ? Theme.accent.opacity(0.18) : .clear)
                                .contentShape(Rectangle())
                                .onTapGesture { selected = i; open(hits) }
                                .id(i)
                        }
                    }
                }
                .onChange(of: selected) { scroller.scrollTo(selected) }
            }
            .overlay {
                if query.trimmingCharacters(in: .whitespaces).isEmpty {
                    Text("Type to search titles and notes").foregroundStyle(Theme.faint)
                } else if hits.isEmpty {
                    Text("No matches").foregroundStyle(Theme.faint)
                }
            }

            Divider()
            Text("↑↓ choose  ·  ↩ open  ·  esc close")
                .scaledFont(.caption)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
        }
        .frame(width: 560, height: 420)
        .background(Theme.bg)
        .onAppear { focused = true }
        .onChange(of: query) { selected = 0 }
        .onExitCommand { dismiss() }
    }

    @ViewBuilder
    private func row(_ hit: Hit) -> some View {
        switch hit {
        case .project(let p):
            HStack(spacing: 10) {
                Text("▸").foregroundStyle(Theme.magenta)
                VStack(alignment: .leading, spacing: 2) {
                    Text(p.title.isEmpty ? "Untitled Project" : p.title)
                    Text(p.completedAt == nil ? "Project" : "Completed project")
                        .scaledFont(.caption).foregroundStyle(Theme.faint)
                }
            }
        case .task(let t):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(t.isDone ? "[x]" : "[ ]").foregroundStyle(t.isDone ? Theme.green : Theme.dim)
                VStack(alignment: .leading, spacing: 2) {
                    Text(t.title.isEmpty ? "New To-Do" : t.title)
                        .strikethrough(t.isDone, color: Theme.faint)
                        .foregroundStyle(t.isDone ? Theme.faint : Theme.text)
                    Text(store.home(of: t).title).scaledFont(.caption).foregroundStyle(Theme.faint)
                }
            }
        }
    }

    private func move(_ delta: Int, in hits: [Hit]) -> KeyPress.Result {
        guard !hits.isEmpty else { return .handled }
        selected = min(max(selected + delta, 0), hits.count - 1)
        return .handled
    }

    private func open(_ hits: [Hit]) {
        guard hits.indices.contains(selected) else { return }
        switch hits[selected] {
        case .project(let p):
            store.go(.project(p.id))
        case .task(let t):
            store.selectRequest = t.id
            store.go(store.home(of: t))
        }
        dismiss()
    }
}
