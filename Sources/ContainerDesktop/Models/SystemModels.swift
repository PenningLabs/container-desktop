import Foundation

// MARK: - System status

/// Overall status of the container system service.
struct SystemStatus: Sendable {
    let isRunning: Bool
    let version: String?
    let containerCount: Int
    let runningCount: Int
    let imageCount: Int
    let kernelVersion: String?
    let uptime: Duration?

    static let offline = SystemStatus(
        isRunning: false,
        version: nil,
        containerCount: 0,
        runningCount: 0,
        imageCount: 0,
        kernelVersion: nil,
        uptime: nil
    )
}

/// Builder service state.
struct BuilderStatus: Sendable {
    let isRunning: Bool
    let memory: UInt64?
    let cpus: Int?
}

/// Disk usage breakdown from `container system df`.
struct DiskUsage: Sendable {
    let containers: DiskUsageCategory
    let images: DiskUsageCategory
    let volumes: DiskUsageCategory
    let builder: DiskUsageCategory
    let total: UInt64

    struct DiskUsageCategory: Sendable {
        let count: Int
        let size: UInt64
        let reclaimable: UInt64
    }

    static let empty = DiskUsage(
        containers: DiskUsageCategory(count: 0, size: 0, reclaimable: 0),
        images: DiskUsageCategory(count: 0, size: 0, reclaimable: 0),
        volumes: DiskUsageCategory(count: 0, size: 0, reclaimable: 0),
        builder: DiskUsageCategory(count: 0, size: 0, reclaimable: 0),
        total: 0
    )
}

// MARK: - Log entries

/// A single log line from a container.
/// A single log line. ANSI parsing is deferred until the view
/// actually renders this entry — saves CPU and memory for entries
/// that are in the disk cache and never displayed.
struct LogEntry: Identifiable, Sendable {
    let id: UUID
    let timestamp: Date?
    let source: LogSource
    let message: String

    /// Lazy ANSI parsing — computed on demand. Since entries live in
    /// a LazyVStack, this only runs for visible rows.
    var ansiSegments: [ANSISegment] {
        ANSIParser.parse(message)
    }

    init(timestamp: Date? = nil, source: LogSource = .stdout, message: String) {
        self.id = UUID()
        self.timestamp = timestamp
        self.source = source
        self.message = message
    }

    /// Serialise to a single line for disk storage.
    var serialized: String {
        let ts = timestamp.map { String($0.timeIntervalSinceReferenceDate) } ?? "-"
        // Escape any tabs/newlines in message to keep one-line-per-entry
        let safeMsg = message.replacingOccurrences(of: "\t", with: "\\t")
            .replacingOccurrences(of: "\n", with: "\\n")
        return "\(ts)\t\(source.rawValue)\t\(safeMsg)"
    }

    /// Deserialise from a line written by `serialized`.
    static func deserialize(_ line: String) -> LogEntry? {
        let parts = line.split(separator: "\t", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count == 3 else { return nil }
        let ts: Date? = (parts[0] == "-") ? nil : Double(parts[0]).map { Date(timeIntervalSinceReferenceDate: $0) }
        let source = LogSource(rawValue: String(parts[1])) ?? .stdout
        let msg = String(parts[2])
            .replacingOccurrences(of: "\\t", with: "\t")
            .replacingOccurrences(of: "\\n", with: "\n")
        return LogEntry(timestamp: ts, source: source, message: msg)
    }
}

enum LogSource: String, Sendable {
    case stdout = "stdout"
    case stderr = "stderr"
    case system = "system"
}

/// A segment of text with optional ANSI color information.
struct ANSISegment: Sendable {
    let text: String
    let color: ANSIColor?
    let bold: Bool
}

enum ANSIColor: Sendable {
    case black, red, green, yellow, blue, magenta, cyan, white
    case brightBlack, brightRed, brightGreen, brightYellow
    case brightBlue, brightMagenta, brightCyan, brightWhite
    case `default`
}

// MARK: - Process channel (for exec / terminal)

/// Bidirectional channel for communicating with a process inside a container.
/// Used for `container exec` / terminal functionality.
protocol ProcessChannel: Sendable {
    /// Send data to the process stdin.
    func write(_ data: Data) async throws
    /// Receive output from stdout/stderr as an async stream.
    var output: AsyncThrowingStream<ProcessOutput, Error> { get }
    /// Resize the terminal (if TTY mode).
    func resize(cols: Int, rows: Int) async throws
    /// Close the channel.
    func close() async
}

struct ProcessOutput: Sendable {
    let source: LogSource
    let data: Data

    var text: String? {
        String(data: data, encoding: .utf8)
    }
}

// MARK: - App errors

/// Unified error type for the application.
enum AppError: LocalizedError, Sendable {
    case systemNotRunning
    case cliNotFound(path: String)
    case cliExecutionFailed(command: String, exitCode: Int32, stderr: String)
    case loadFailed(Error)
    case actionFailed(String, Error)
    case parseError(String)
    case timeout(String)
    case unknown(String)

    var errorDescription: String? {
        switch self {
        case .systemNotRunning:
            return "Container system is not running. Start it from System settings."
        case .cliNotFound(let path):
            return "Container CLI not found at \(path). Install it from GitHub releases or via Homebrew."
        case .cliExecutionFailed(let cmd, let code, let stderr):
            return "Command '\(cmd)' failed (exit \(code)): \(stderr)"
        case .loadFailed(let error):
            return "Failed to load data: \(error.localizedDescription)"
        case .actionFailed(let action, let error):
            return "Failed to \(action): \(error.localizedDescription)"
        case .parseError(let detail):
            return "Failed to parse output: \(detail)"
        case .timeout(let operation):
            return "Operation timed out: \(operation)"
        case .unknown(let msg):
            return msg
        }
    }
}
