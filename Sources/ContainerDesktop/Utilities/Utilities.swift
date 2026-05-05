import Foundation

// MARK: - ANSI escape code parser

/// Minimal ANSI escape sequence parser for colorizing log output.
/// Handles the most common SGR (Select Graphic Rendition) codes
/// used by container processes.
enum ANSIParser {

    static func parse(_ text: String) -> [ANSISegment] {
        guard !text.isEmpty else { return [] }

        var segments: [ANSISegment] = []
        var currentColor: ANSIColor? = nil
        var currentBold = false
        var buffer = ""

        var i = text.startIndex
        while i < text.endIndex {
            if text[i] == "\u{1B}" {
                // Flush current buffer
                if !buffer.isEmpty {
                    segments.append(ANSISegment(text: buffer, color: currentColor, bold: currentBold))
                    buffer = ""
                }

                // Try to parse ESC[ ... m sequence
                if let (newIndex, codes) = parseCSI(text, from: i) {
                    for code in codes {
                        switch code {
                        case 0:
                            currentColor = nil
                            currentBold = false
                        case 1:
                            currentBold = true
                        case 22:
                            currentBold = false
                        case 30: currentColor = .black
                        case 31: currentColor = .red
                        case 32: currentColor = .green
                        case 33: currentColor = .yellow
                        case 34: currentColor = .blue
                        case 35: currentColor = .magenta
                        case 36: currentColor = .cyan
                        case 37: currentColor = .white
                        case 39: currentColor = .default
                        case 90: currentColor = .brightBlack
                        case 91: currentColor = .brightRed
                        case 92: currentColor = .brightGreen
                        case 93: currentColor = .brightYellow
                        case 94: currentColor = .brightBlue
                        case 95: currentColor = .brightMagenta
                        case 96: currentColor = .brightCyan
                        case 97: currentColor = .brightWhite
                        default: break
                        }
                    }
                    i = newIndex
                } else {
                    // Not a valid CSI sequence — skip the ESC character
                    i = text.index(after: i)
                }
            } else {
                buffer.append(text[i])
                i = text.index(after: i)
            }
        }

        // Flush remaining
        if !buffer.isEmpty {
            segments.append(ANSISegment(text: buffer, color: currentColor, bold: currentBold))
        }

        // If no ANSI codes were found, return a single plain segment
        if segments.isEmpty {
            return [ANSISegment(text: text, color: nil, bold: false)]
        }

        return segments
    }

    /// Parse a CSI sequence: ESC [ <params> m
    /// Returns the index after the sequence and the parsed numeric codes.
    private static func parseCSI(_ text: String, from start: String.Index) -> (String.Index, [Int])? {
        var i = text.index(after: start)
        guard i < text.endIndex, text[i] == "[" else { return nil }
        i = text.index(after: i)

        var paramStr = ""
        while i < text.endIndex {
            let ch = text[i]
            if ch.isNumber || ch == ";" {
                paramStr.append(ch)
                i = text.index(after: i)
            } else if ch == "m" {
                i = text.index(after: i)
                let codes = paramStr.split(separator: ";").compactMap { Int($0) }
                return (i, codes.isEmpty ? [0] : codes)
            } else {
                // Unknown terminator — skip entire sequence
                i = text.index(after: i)
                return (i, [])
            }
        }
        return nil
    }
}

// MARK: - CLI locator

/// Finds the `container` CLI binary on disk.
/// Checks common installation locations and PATH.
enum ContainerCLILocator {

    /// Standard installation paths to check.
    private static let knownPaths: [String] = [
        "/usr/local/bin/container",
        "/opt/homebrew/bin/container",
    ]

    /// Find the container CLI binary, returning the first valid path.
    static func locate() -> String? {
        // Check known paths first
        for path in knownPaths {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }

        // Search PATH
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let candidate = "\(dir)/container"
                if FileManager.default.isExecutableFile(atPath: candidate) {
                    return candidate
                }
            }
        }

        return nil
    }

    /// Get the version of the CLI at the given path.
    static func version(at path: String) async -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = ["--version"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }
}

// MARK: - Formatters

enum Formatters {

    /// Format a byte count for display: "142 MB", "2.1 GB"
    static func bytes(_ count: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(count), countStyle: .file)
    }

    /// Format a duration for display: "4h 32m", "12s"
    static func duration(_ duration: Duration) -> String {
        let total = Int(duration.components.seconds)
        if total < 60 {
            return "\(total)s"
        } else if total < 3600 {
            return "\(total / 60)m \(total % 60)s"
        } else {
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            return "\(hours)h \(minutes)m"
        }
    }

    /// Format a date as a relative time string: "2 minutes ago"
    static func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    /// Format a date as ISO-like timestamp for log display.
    static func logTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: date)
    }
}
