import AppKit
import SwiftUI

/// SwiftUI view that renders a log entry with ANSI color codes
/// as a properly colored `AttributedString`.
struct ANSIColoredText: View {
    let entry: LogEntry
    let showTimestamp: Bool
    let fontSize: CGFloat

    init(entry: LogEntry, showTimestamp: Bool = true, fontSize: CGFloat = 11) {
        self.entry = entry
        self.showTimestamp = showTimestamp
        self.fontSize = fontSize
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if showTimestamp, let ts = entry.timestamp {
                Text(Formatters.logTimestamp(ts))
                    .font(.system(size: fontSize, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .frame(width: 110, alignment: .leading)
                    .textSelection(.enabled)
            }

            if entry.source == .stderr {
                // Stderr gets a subtle red indicator
                Circle()
                    .fill(.red.opacity(0.6))
                    .frame(width: 5, height: 5)
                    .padding(.top, 5)
            }

            Text(coloredString)
                .font(.system(size: fontSize, design: .monospaced))
                .textSelection(.enabled)
        }
        .padding(.vertical, 1)
    }

    /// Build an `AttributedString` from the parsed ANSI segments.
    private var coloredString: AttributedString {
        var result = AttributedString()

        for segment in entry.ansiSegments {
            var part = AttributedString(segment.text)

            if let color = segment.color {
                part.foregroundColor = nsColor(for: color)
            }

            if segment.bold {
                part.font = .system(size: fontSize, design: .monospaced).bold()
            }

            result += part
        }

        return result
    }

    /// Map ANSI color codes to SwiftUI-compatible NSColor values.
    /// Uses semantic colors that work in both light and dark mode.
    private func nsColor(for ansi: ANSIColor) -> Color {
        switch ansi {
        case .black:         return .primary.opacity(0.3)
        case .red:           return Color(.systemRed)
        case .green:         return Color(.systemGreen)
        case .yellow:        return Color(.systemYellow)
        case .blue:          return Color(.systemBlue)
        case .magenta:       return Color(.systemPurple)
        case .cyan:          return Color(.systemTeal)
        case .white:         return .primary.opacity(0.9)
        case .brightBlack:   return .secondary
        case .brightRed:     return Color(.systemRed).opacity(0.8)
        case .brightGreen:   return Color(.systemGreen).opacity(0.8)
        case .brightYellow:  return Color(.systemYellow).opacity(0.8)
        case .brightBlue:    return Color(.systemBlue).opacity(0.8)
        case .brightMagenta: return Color(.systemPurple).opacity(0.8)
        case .brightCyan:    return Color(.systemTeal).opacity(0.8)
        case .brightWhite:   return .primary
        case .default:       return .primary
        }
    }
}
