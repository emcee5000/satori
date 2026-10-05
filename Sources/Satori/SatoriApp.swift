import AppKit
import SwiftUI

@main
struct SatoriApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = Store()

    var body: some Scene {
        Window("Satori", id: "main") {
            ContentView()
                .environment(store)
                .scaledFont(.body)
                .terminalTheme()
                .frame(minWidth: 780, minHeight: 480)
        }
        .defaultSize(width: 1040, height: 680)
        .windowToolbarStyle(.unifiedCompact(showsTitle: false))
        .commands { SatoriCommands(store: store) }

        Settings {
            SettingsView().environment(store).scaledFont(.body).terminalTheme()
        }

        MenuBarExtra("Satori", systemImage: "tray.and.arrow.down") {
            QuickCaptureView().environment(store)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var keyMonitor: Any?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (e.g. `swift run`).
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()

        // Like Safari, accept ⌘= (unshifted) as "Make Text Bigger" too.
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if mods == .command, event.charactersIgnoringModifiers == "=" {
                TextScale.bigger()
                return nil
            }
            return event
        }
    }
}

// MARK: - Menu commands

struct SelectedTaskKey: FocusedValueKey { typealias Value = UUID }

extension FocusedValues {
    var selectedTaskID: UUID? {
        get { self[SelectedTaskKey.self] }
        set { self[SelectedTaskKey.self] = newValue }
    }
}

/// First-letter shortcuts: ⌘ + letter moves the selected to-do to a list,
/// ⌥⌘ + letter goes to it. (⌥⌘D is a system shortcut, so Scheduled uses ⌥⌘U for "upcoming".)
let listShortcuts: [(destination: Destination, move: Character, go: Character)] = [
    (.inbox, "i", "i"),
    (.today, "t", "t"),
    (.next, "n", "n"),
    (.scheduled, "d", "u"),
    (.waiting, "w", "w"),
    (.someday, "s", "s"),
    (.reference, "r", "r"),
]

struct SatoriCommands: Commands {
    let store: Store
    @FocusedValue(\.selectedTaskID) private var selected

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New To-Do") { store.requestNewTask() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Project…") { store.showNewProject = true }
                .keyboardShortcut("n", modifiers: [.command, .option, .shift])
            Divider()
            Button("Process Inbox…") { store.showProcessInbox = true }
                .keyboardShortcut("i", modifiers: [.command, .shift])
        }

        // Text fields keep their own undo while you're typing in them; otherwise ⌘Z
        // undoes the last change to your to-dos and projects.
        CommandGroup(replacing: .undoRedo) {
            Button("Undo") { if !textField(undo: true) { store.undoLastChange() } }
                .keyboardShortcut("z")
            Button("Redo") { if !textField(undo: false) { store.redoLastChange() } }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") { store.showSearch = true }
                .keyboardShortcut("f")
        }

        // ⌘W belongs to Waiting For, so closing a window moves to ⇧⌘W.
        CommandGroup(replacing: .saveItem) {
            Button("Close Window") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .printItem) {}

        CommandGroup(after: .toolbar) {
            Button(store.showInspector ? "Hide Inspector" : "Show Inspector") { store.showInspector.toggle() }
                .keyboardShortcut("i", modifiers: [.command, .control])
            Divider()
            Button("Make Text Bigger") { TextScale.bigger() }
                .keyboardShortcut("+")
            Button("Make Text Smaller") { TextScale.smaller() }
                .keyboardShortcut("-")
            Button("Actual Size") { TextScale.reset() }
                .keyboardShortcut("0")
            Divider()
        }

        CommandGroup(replacing: .help) {
            Button("Keyboard Shortcuts") { store.showShortcuts = true }
                .keyboardShortcut("/")
        }

        CommandMenu("To-Do") {
            Button("Complete") { if let selected { store.toggleComplete(selected) } }
                .keyboardShortcut("k")
                .disabled(selected == nil)
            Button("Complete Project") { if let id = currentProject { store.requestCompleteProject(id) } }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(currentProject.flatMap(store.project)?.isActive != true)
            Divider()
            ForEach(listShortcuts, id: \.move) { item in
                Button(moveTitle(item.destination)) {
                    guard let selected else { return }
                    // ⌘T toggles: pressing it on a Today item takes it back out.
                    if item.destination == .today, store.task(selected)?.starred == true {
                        store.toggleStar(selected)
                    } else {
                        store.send(selected, to: item.destination)
                    }
                }
                .keyboardShortcut(KeyEquivalent(item.move))
                .disabled(selected == nil)
            }
            Button("Move to Project…") { store.moveToProjectTaskID = selected }
                .keyboardShortcut("p")
                .disabled(selected == nil)
            Divider()
            Button("Move to Trash") { if let selected { store.trash(selected) } }
                .keyboardShortcut(.delete)
                .disabled(selected == nil)
        }

        CommandMenu("Go") {
            ForEach(listShortcuts, id: \.go) { item in
                Button(item.destination.title) { store.go(item.destination) }
                    .keyboardShortcut(KeyEquivalent(item.go), modifiers: [.command, .option])
            }
            Divider()
            Button("Projects") { store.go(.projects) }
                .keyboardShortcut("p", modifiers: [.command, .option])
            Button("Weekly Review") { store.go(.review) }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Logbook") { store.go(.logbook) }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Button("Trash") { store.go(.trash) }
                .keyboardShortcut(.delete, modifiers: [.command, .shift])
        }
    }

    /// The project being viewed, for project commands.
    private var currentProject: UUID? {
        if case .project(let id) = store.selection { return id }
        return nil
    }

    /// Sends undo/redo to the focused text field if it has something to undo.
    private func textField(undo: Bool) -> Bool {
        guard let text = NSApp.keyWindow?.firstResponder as? NSTextView,
              let manager = text.undoManager,
              undo ? manager.canUndo : manager.canRedo else { return false }
        undo ? manager.undo() : manager.redo()
        return true
    }

    private func moveTitle(_ d: Destination) -> String {
        switch d {
        case .today: "Today"
        case .scheduled: "Scheduled (Tomorrow)"
        default: "Move to \(d.title)"
        }
    }
}
