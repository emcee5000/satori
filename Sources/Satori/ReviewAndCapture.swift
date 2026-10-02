import AppKit
import SwiftUI

// MARK: - Weekly Review

private struct ReviewStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    var destination: Destination?
}

private let reviewPhases: [(String, [ReviewStep])] = [
    ("Get Clear", [
        ReviewStep(id: "collect", title: "Collect loose papers and materials",
                   detail: "Gather notes, receipts and scraps into your inbox."),
        ReviewStep(id: "inbox", title: "Get Inbox to zero",
                   detail: "Clarify every item and put it where it belongs.", destination: .inbox),
        ReviewStep(id: "mind", title: "Empty your head",
                   detail: "Capture any new projects, actions, waiting-fors and someday/maybes."),
    ]),
    ("Get Current", [
        ReviewStep(id: "next", title: "Review Next Actions",
                   detail: "Mark off completed actions. Add reminders for further steps.", destination: .next),
        ReviewStep(id: "pastcal", title: "Review previous calendar",
                   detail: "Look back two weeks for remaining or new action items."),
        ReviewStep(id: "upcal", title: "Review upcoming calendar",
                   detail: "Look ahead and capture actions for upcoming events."),
        ReviewStep(id: "waiting", title: "Review Waiting For",
                   detail: "Record follow-ups. Check off what's been received.", destination: .waiting),
        ReviewStep(id: "projects", title: "Review Projects",
                   detail: "Make sure every project has at least one current next action.", destination: .projects),
        ReviewStep(id: "scheduled", title: "Review Scheduled",
                   detail: "Is anything coming up that needs preparation now?", destination: .scheduled),
        ReviewStep(id: "checklists", title: "Review any relevant checklists",
                   detail: "Areas of focus, goals, routines — anything you haven't attended to?"),
    ]),
    ("Get Creative", [
        ReviewStep(id: "someday", title: "Review Someday/Maybe",
                   detail: "Activate anything that's now relevant. Delete what isn't.", destination: .someday),
        ReviewStep(id: "creative", title: "Be creative and courageous",
                   detail: "Any new, wonderful, harebrained ideas? Capture them."),
    ]),
]

struct WeeklyReviewView: View {
    @Environment(Store.self) private var store
    @State private var capture = ""
    @State private var selection: String?
    @FocusState private var focus: Pane?

    private var totalSteps: Int { reviewPhases.reduce(0) { $0 + $1.1.count } }
    private var allSteps: [ReviewStep] { reviewPhases.flatMap(\.1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ListHeader(destination: .review)

            HStack {
                if let last = store.data.lastReview {
                    Text("Last review: \(last.formatted(.relative(presentation: .named)))")
                        .foregroundStyle(store.reviewIsDue ? Theme.yellow : Theme.dim)
                } else {
                    Text("# no weekly review yet").foregroundStyle(Theme.yellow)
                }
                Spacer()
                Text("\(store.data.reviewChecks.count) of \(totalSteps)").foregroundStyle(Theme.dim)
            }
            .scaledFont(.callout)

            HStack(spacing: 8) {
                Text("❯").scaledFont(.body, weight: .bold).foregroundStyle(focus == .newTask ? Theme.accent : Theme.faint)
                TextField("Capture anything that comes to mind…", text: $capture)
                    .textFieldStyle(.plain)
                    .focused($focus, equals: .newTask)
                    .onSubmit {
                        let t = capture.trimmingCharacters(in: .whitespaces)
                        if !t.isEmpty { store.addTask(t, to: .inbox) }
                        capture = ""
                    }
                    .onExitCommand { focus = .list }
                    .onKeyPress(.downArrow) { focus = .list; return .handled }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(focus == .newTask ? Theme.accent.opacity(0.7) : Theme.border, lineWidth: 1))
            .help("Capture to Inbox — ↩ adds · ↓ back to the steps")

            List(selection: $selection) {
                ForEach(reviewPhases, id: \.0) { phase, steps in
                    Section {
                        ForEach(steps) { stepRow($0).scaledFont(.body).listRowSeparator(.hidden).tag($0.id) }
                    } header: {
                        Text("── " + phase.lowercased()).foregroundStyle(Theme.dim).scaledFont(.caption)
                    }
                }
            }
            .listStyle(.inset)
            .scrollContentBackground(.hidden)
            .focused($focus, equals: .list)
            .onChange(of: focus) { if let focus { store.activePane = focus } }
            .onKeyPress(characters: ["?"]) { _ in
                store.showShortcuts = true
                return .handled
            }
            .contextMenu(forSelectionType: String.self) { _ in
                EmptyView()
            } primaryAction: { ids in
                if let id = ids.first, let step = allSteps.first(where: { $0.id == id }) { open(step) }
            }
            .onKeyPress(.space) {
                if let selection { toggle(selection) }
                return .handled
            }
            .onKeyPress(.leftArrow) { store.focusRequest = .sidebar; return .handled }

            HStack {
                Spacer()
                Button("Finish Weekly Review") {
                    store.data.lastReview = Date()
                    store.data.reviewChecks = []
                }
                .keyboardShortcut(.return, modifiers: .command)
                .help("⌘↩")
            }
        }
        .padding(20)
        .onChange(of: store.focusRequest) { consumeFocusRequest() }
        .onAppear { consumeFocusRequest() }
    }

    private func consumeFocusRequest() {
        guard let request = store.focusRequest, request == .list || request == .newTask else { return }
        store.focusRequest = nil
        DispatchQueue.main.async {
            focus = request
            if selection == nil { selection = allSteps.first?.id }
        }
    }

    private func toggle(_ id: String) {
        if store.data.reviewChecks.contains(id) { store.data.reviewChecks.removeAll { $0 == id } }
        else { store.data.reviewChecks.append(id) }
    }

    private func open(_ step: ReviewStep) {
        guard let d = step.destination else { toggle(step.id); return }
        if d == .inbox { store.showProcessInbox = true } else { store.go(d) }
    }

    private func stepRow(_ step: ReviewStep) -> some View {
        let checked = store.data.reviewChecks.contains(step.id)
        return HStack(alignment: .top, spacing: 10) {
            Button { toggle(step.id) } label: {
                Text(checked ? "[x]" : "[ ]").scaledFont(.body).foregroundStyle(checked ? Theme.green : Theme.dim)
            }
            .buttonStyle(.plain)
            .help("Space")

            VStack(alignment: .leading, spacing: 2) {
                Text(step.title).scaledFont(.body).strikethrough(checked, color: Theme.faint).foregroundStyle(checked ? Theme.faint : Theme.text)
                Text("# " + step.detail).scaledFont(.caption).foregroundStyle(Theme.faint)
            }
            Spacer()
            if let d = step.destination {
                let stalled = d == .projects ? store.activeProjects.filter(store.isStalled).count : 0
                if stalled > 0 {
                    Text("\(stalled) stalled").scaledFont(.caption).foregroundStyle(Theme.orange)
                } else if d != .projects {
                    Text("\(store.count(d))").scaledFont(.caption).foregroundStyle(Theme.dim)
                }
                Button(d == .inbox ? "Process" : "Open") { open(step) }
                    .controlSize(.small)
                    .help("↩")
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Menu bar quick capture

struct QuickCaptureView: View {
    @Environment(Store.self) private var store
    @Environment(\.openWindow) private var openWindow
    @State private var text = ""
    @State private var captured = 0
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Capture to Inbox").scaledFont(.headline)
            TextField("What's on your mind?", text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit {
                    let t = text.trimmingCharacters(in: .whitespaces)
                    guard !t.isEmpty else { return }
                    store.addTask(t, to: .inbox)
                    text = ""
                    captured += 1
                }
            HStack {
                Text(captured > 0 ? "✓ Captured \(captured)" : "\(store.count(.inbox)) in Inbox")
                    .scaledFont(.caption).foregroundStyle(Theme.dim)
                Spacer()
                Button("Open Satori") {
                    openWindow(id: "main")
                    NSApp.activate()
                }
                .controlSize(.small)
            }
        }
        .padding(14)
        .frame(width: 300)
        .onAppear { focused = true; captured = 0 }
    }
}

// MARK: - Settings

struct SettingsView: View {
    @Environment(Store.self) private var store
    @AppStorage(TextScale.key) private var scale = 1.0
    @State private var newContext = ""

    var body: some View {
        Form {
            Section {
                ForEach(store.data.contexts, id: \.self) { c in
                    HStack {
                        Text(c)
                        Spacer()
                        Button { store.data.contexts.removeAll { $0 == c } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(Theme.dim)
                        }
                        .buttonStyle(.plain)
                    }
                }
                HStack {
                    TextField("New context", text: $newContext, prompt: Text("@context"))
                        .onSubmit(addContext)
                    Button("Add", action: addContext)
                }
            } header: {
                Text("Contexts")
            } footer: {
                Text("Contexts are the tools, places or people needed to do an action.")
                    .scaledFont(.caption).foregroundStyle(Theme.dim)
            }

            CaptureAndReminderSettings()

            SyncSettings(sync: store.sync)

            Section("Data") {
                LabeledContent("Stored at") {
                    Text(store.fileURL.path).scaledFont(.caption).textSelection(.enabled)
                }
                Button("Show in Finder") {
                    store.saveNow()
                    NSWorkspace.shared.activateFileViewerSelecting([store.fileURL])
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 480 * scale, height: 640 * scale)
    }

    private func addContext() {
        var c = newContext.trimmingCharacters(in: .whitespaces)
        guard !c.isEmpty else { return }
        if !c.hasPrefix("@") { c = "@" + c }
        if !store.data.contexts.contains(c) { store.data.contexts.append(c) }
        newContext = ""
    }
}

// MARK: - Sync settings

struct SyncSettings: View {
    @Bindable var sync: SyncService
    @State private var showConnect = false

    var body: some View {
        Section {
            Toggle("Sync with GitHub", isOn: $sync.enabled)
            TextField("Repository", text: $sync.repo, prompt: Text("you/satori-data"))
            SecureField("Token", text: $sync.token, prompt: Text("github_pat_…"))
            HStack {
                SyncStatusText(status: sync.status)
                Spacer()
                Button("Connect iPhone…") { showConnect = true }
                    .disabled(!sync.isConfigured)
                Button("Sync Now") { Task { await sync.syncNow() } }
                    .disabled(!sync.isConfigured)
            }
            .sheet(isPresented: $showConnect) { ConnectPhoneView(sync: sync) }
        } header: {
            Text("Sync")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Keeps this Mac and the Satori web app on your phone in step, through a private GitHub repo you own.")
                Text("Create a fine-grained token with **Contents: read and write** access to only that repo.")
                Link("Create a token on GitHub ↗", destination: URL(string: "https://github.com/settings/personal-access-tokens/new")!)
            }
            .scaledFont(.caption)
            .foregroundStyle(Theme.dim)
        }
    }
}

struct SyncStatusText: View {
    let status: SyncService.Status

    var body: some View {
        switch status {
        case .off:
            Text("off").foregroundStyle(Theme.faint)
        case .syncing:
            Text("syncing…").foregroundStyle(Theme.dim)
        case .synced(let date):
            Text("synced \(date.formatted(date: .omitted, time: .shortened))").foregroundStyle(Theme.green)
        case .failed(let message):
            Text("⚠ " + message).foregroundStyle(Theme.red).lineLimit(2)
        }
    }
}

// MARK: - Capture & reminder settings

struct CaptureAndReminderSettings: View {
    @Environment(Store.self) private var store
    @AppStorage(GlobalCapture.enabledKey) private var captureEnabled = true
    @AppStorage(Reminders.enabledKey) private var remindersEnabled = true
    @AppStorage(Reminders.hourKey) private var reminderHour = 9

    var body: some View {
        Section("Capture & Reminders") {
            Toggle("Capture from anywhere with \(GlobalCapture.shortcut)", isOn: $captureEnabled)
                .onChange(of: captureEnabled) { store.globalCapture?.update() }
            Toggle("Remind me when a to-do is due", isOn: $remindersEnabled)
                .onChange(of: remindersEnabled) { store.reminders.schedule(for: store.data) }
            if remindersEnabled {
                Picker("Reminder time", selection: $reminderHour) {
                    ForEach(5..<22, id: \.self) { hour in
                        Text(Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: .now)!
                            .formatted(date: .omitted, time: .shortened)).tag(hour)
                    }
                }
                .onChange(of: reminderHour) { store.reminders.schedule(for: store.data) }
            }
        }
    }
}

// MARK: - Connect iPhone

/// Shows a link (and QR code) that sets up sync in the phone app in one step.
struct ConnectPhoneView: View {
    let sync: SyncService
    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    var body: some View {
        let link = sync.setupLink
        VStack(spacing: 16) {
            Text("Connect your iPhone").scaledFont(.title3, weight: .semibold)
            if let link, let qr = QRCode.image(for: link.absoluteString) {
                Image(nsImage: qr)
                    .interpolation(.none)
                    .resizable()
                    .frame(width: 220, height: 220)
                    .padding(10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 8))
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("**Phone app already on your Home Screen?** Copy the link, open Satori on the phone, go to **More → Sync & Settings** and paste it into **Setup link**.")
                Text("**New phone?** Scan the code with the Camera, open the link in Safari, then tap **Share → Add to Home Screen**. If the Home Screen app doesn't show your to-dos, paste the link as above.")
                Text("The link contains your GitHub token. Only share it with your own devices.")
                    .foregroundStyle(Theme.orange)
            }
            .scaledFont(.callout)
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(copied ? "Copied ✓" : "Copy Link") {
                    guard let link else { return }
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(link.absoluteString, forType: .string)
                    copied = true
                }
                .disabled(link == nil)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 420)
    }
}

enum QRCode {
    static func image(for text: String) -> NSImage? {
        guard let filter = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        filter.setValue(Data(text.utf8), forKey: "inputMessage")
        filter.setValue("M", forKey: "inputCorrectionLevel")
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 8, y: 8)) else { return nil }
        let rep = NSCIImageRep(ciImage: output)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
