import SwiftUI

/// App-wide text zoom (⌘+ / ⌘- / ⌘0). macOS ignores Dynamic Type, so every
/// font in the app goes through `scaledFont` which reads this setting.
enum TextScale {
    static let key = "textScale"
    static let steps: [Double] = [0.85, 1.0, 1.15, 1.3, 1.5, 1.75, 2.0]

    static var current: Double { UserDefaults.standard.object(forKey: key) as? Double ?? 1.0 }

    static func bigger() { set(steps.first { $0 > current + 0.001 } ?? current) }
    static func smaller() { set(steps.last { $0 < current - 0.001 } ?? current) }
    static func reset() { set(1.0) }

    private static func set(_ value: Double) { UserDefaults.standard.set(value, forKey: key) }
}

extension Font.TextStyle {
    /// Default macOS point sizes for each text style.
    var macPointSize: CGFloat {
        switch self {
        case .largeTitle: 26
        case .title: 22
        case .title2: 17
        case .title3: 15
        case .headline, .body: 13
        case .callout: 12
        case .subheadline: 11
        default: 10 // footnote, caption, caption2
        }
    }
}

private struct ScaledFont: ViewModifier {
    @AppStorage(TextScale.key) private var scale = 1.0
    let style: Font.TextStyle
    let weight: Font.Weight?

    func body(content: Content) -> some View {
        content.font(.system(size: style.macPointSize * scale,
                             weight: weight ?? (style == .headline ? .semibold : .regular),
                             design: .monospaced))
    }
}

extension View {
    func scaledFont(_ style: Font.TextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(ScaledFont(style: style, weight: weight))
    }
}
