import SwiftUI

/// Cheat sheet for running the whole app from the keyboard (⌘/).
struct ShortcutsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(TextScale.key) private var scale = 1.0

    private let groups: [(String, [(String, String)])] = [
        ("Get around", [
            ("↑ ↓", "Move through lists or to-dos"),
            ("← →", "Sidebar ↔ to-do list"),
            ("Tab", "Next area (new to-do field, list, inspector)"),
            ("⌥⌘ I T N U W S R", "Go to Inbox, Today, Next, Scheduled, Waiting, Someday, Reference"),
            ("⌥⌘P  ⇧⌘R  ⌥⌘L", "Go to Projects, Weekly Review, Logbook"),
        ]),
        ("Work with a to-do", [
            ("Space", "New to-do (type @context to set its context)"),
            ("↩ or →", "Edit selected to-do"),
            ("↩ (in title)", "Finish editing, back to the list"),
            ("esc", "Back to the list / close the inspector"),
            ("⌘K", "Complete"),
            ("⇧⌘K", "Complete the project you're viewing"),
            ("⌫", "Move to Trash"),
            ("⌘Z  ⇧⌘Z", "Undo / redo"),
        ]),
        ("Move the selected to-do", [
            ("⌘I", "Inbox"),
            ("⌘T", "Today (press again to remove)"),
            ("⌘N", "Next Actions"),
            ("⌘D", "Scheduled — starts tomorrow"),
            ("⌘W", "Waiting For"),
            ("⌘S", "Someday/Maybe"),
            ("⌘R", "Reference"),
            ("⌘P", "Project… (type, ↑↓, ↩)"),
        ]),
        ("Everything else", [
            ("⇧⌘N  ⌥⇧⌘N", "New to-do / new project"),
            ("⌘F", "Find a to-do or project"),
            ("⌃⌥Space", "Capture from any app"),
            ("⇧⌘I", "Process Inbox (↩ and ⌘1–3 answer each question)"),
            ("⌃⌘I", "Show/hide inspector"),
            ("⌘+  ⌘−  ⌘0", "Text size"),
            ("⇧⌘W", "Close window"),
            ("? or ⌘/", "This cheat sheet"),
        ]),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Keyboard Shortcuts").scaledFont(.title2, weight: .bold)
            ScrollView {
                Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 6) {
                    ForEach(groups, id: \.0) { title, rows in
                        GridRow {
                            Text(title.uppercased()).scaledFont(.caption, weight: .bold).foregroundStyle(Theme.dim)
                                .gridCellColumns(2)
                                .padding(.top, 8)
                        }
                        ForEach(rows, id: \.0) { keys, action in
                            GridRow {
                                Text(keys).foregroundStyle(Theme.accent)
                                Text(action)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .background(Theme.bg)
        .frame(width: 560 * scale, height: 560 * scale)
    }
}
