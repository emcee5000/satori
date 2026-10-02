import AppKit
import Carbon.HIToolbox
import SwiftUI

/// ⌃⌥Space from any app opens a small capture box, like Spotlight.
/// Uses a Carbon hot key, which needs no accessibility permission.
@MainActor
final class GlobalCapture {
    static let enabledKey = "globalCaptureEnabled"
    static let shortcut = "⌃⌥Space"

    private let store: Store
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var panel: CapturePanel?

    init(store: Store) {
        self.store = store
        UserDefaults.standard.register(defaults: [Self.enabledKey: true])
        installHandler()
        update()
    }

    /// Registers or removes the hot key to match the setting.
    func update() {
        let enabled = UserDefaults.standard.bool(forKey: Self.enabledKey)
        if enabled, hotKey == nil {
            let id = EventHotKeyID(signature: OSType(0x5341_5452), id: 1) // "SATR"
            RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id,
                                GetApplicationEventTarget(), 0, &hotKey)
        } else if !enabled, let hotKey {
            UnregisterEventHotKey(hotKey)
            self.hotKey = nil
        }
    }

    private func installHandler() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let me = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return noErr }
            let capture = Unmanaged<GlobalCapture>.fromOpaque(context).takeUnretainedValue()
            DispatchQueue.main.async { MainActor.assumeIsolated { capture.toggle() } }
            return noErr
        }, 1, &spec, me, &handler)
    }

    func toggle() {
        if let panel, panel.isVisible { panel.close(); return }
        let panel = self.panel ?? CapturePanel(store: store)
        self.panel = panel
        panel.present()
    }
}

/// A floating capture box that takes typing without bringing Satori's main window forward.
final class CapturePanel: NSPanel {
    init(store: Store) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 560, height: 64),
                   styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
                   backing: .buffered, defer: false)
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        standardWindowButton(.closeButton)?.isHidden = true
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        isMovableByWindowBackground = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        contentView = NSHostingView(rootView: CapturePanelView { [weak self] in self?.close() }
            .environment(store)
            .terminalTheme())
    }

    override var canBecomeKey: Bool { true }

    func present() {
        // Upper third of the screen with the mouse, where Spotlight sits.
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            setFrameOrigin(NSPoint(x: area.midX - frame.width / 2, y: area.minY + area.height * 0.68))
        }
        NotificationCenter.default.post(name: .capturePanelWillShow, object: nil)
        makeKeyAndOrderFront(nil)
    }

    override func resignKey() {
        super.resignKey()
        close()
    }

    override func cancelOperation(_ sender: Any?) { close() }
}

extension Notification.Name {
    static let capturePanelWillShow = Notification.Name("capturePanelWillShow")
}

private struct CapturePanelView: View {
    let close: () -> Void
    @Environment(Store.self) private var store
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text("❯").scaledFont(.title2, weight: .bold).foregroundStyle(Theme.blue)
            TextField("Capture to Inbox… (@context works)", text: $text)
                .textFieldStyle(.plain)
                .scaledFont(.title2)
                .focused($focused)
                .onSubmit {
                    let title = text.trimmingCharacters(in: .whitespaces)
                    if !title.isEmpty { store.addTask(title, to: .inbox) }
                    text = ""
                    close()
                }
                .onExitCommand { text = ""; close() }
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.panel)
        .onAppear { focused = true }
        .onReceive(NotificationCenter.default.publisher(for: .capturePanelWillShow)) { _ in
            DispatchQueue.main.async { focused = true }
        }
    }
}
