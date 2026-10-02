import SwiftUI

/// Ghostty-inspired palette: One Dark-style charcoal, soft text, a blue
/// cursor-style accent, and muted ANSI colours for metadata.
enum Theme {
    static let bg = Color(hex: 0x282C34)
    static let sidebar = Color(hex: 0x21252B)
    static let panel = Color(hex: 0x2C313A)
    static let border = Color(hex: 0x3E4451)
    static let text = Color(hex: 0xDCDFE4)
    static let dim = Color(hex: 0x8B929E)
    static let faint = Color(hex: 0x5C6370)
    static let accent = Color(hex: 0x61AFEF)

    static let blue = Color(hex: 0x61AFEF)
    static let cyan = Color(hex: 0x56B6C2)
    static let green = Color(hex: 0x98C379)
    static let yellow = Color(hex: 0xE5C07B)
    static let orange = Color(hex: 0xD19A66)
    static let red = Color(hex: 0xE06C75)
    static let magenta = Color(hex: 0xC678DD)
    static let sand = Color(hex: 0xB8A584)
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    /// Applies the terminal look to a window's root view.
    func terminalTheme() -> some View {
        self
            .preferredColorScheme(.dark)
            .tint(Theme.accent)
            .foregroundStyle(Theme.text)
    }
}

/// Bottom status line, like a CLI's: the keys that work right now.
struct StatusLine: View {
    @Environment(Store.self) private var store

    private var hints: [(String, String)] {
        switch store.activePane {
        case .sidebar:
            return [("↑↓", "select"), ("→", "open"), ("space", "new"), ("⌥⌘ letter", "jump")]
        case .newTask:
            return [("↩", "add"), ("@context", "tag"), ("↓/esc", "back to list")]
        case .inspector:
            return [("↩", "done"), ("tab", "next field"), ("esc", "back")]
        case .list, nil:
            switch store.selection {
            case .review:
                return [("↑↓", "move"), ("space", "check"), ("↩", "open"), ("⌘↩", "finish")]
            case .projects:
                return [("↑↓", "move"), ("↩", "open project"), ("←", "sidebar")]
            default:
                return [("space", "new"), ("↩", "edit"), ("⌘K", "done"),
                        ("⌘I T N D W S R", "move"), ("⌘P", "project"), ("⌫", "trash")]
            }
        }
    }

    var body: some View {
        HStack(spacing: 14) {
            ForEach(hints, id: \.0) { key, action in
                HStack(spacing: 5) {
                    Text(key).foregroundStyle(Theme.dim)
                    Text(action).foregroundStyle(Theme.faint)
                }
            }
            Spacer(minLength: 8)
            Text("? for shortcuts").foregroundStyle(Theme.faint)
        }
        .scaledFont(.caption)
        .lineLimit(1)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(Theme.sidebar)
        .overlay(alignment: .top) { Rectangle().fill(Theme.border).frame(height: 1) }
    }
}
