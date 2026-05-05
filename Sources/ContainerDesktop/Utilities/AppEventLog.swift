import AppKit
import Foundation
import Observation

/// Application-level event log that captures everything that happens
/// outside of container logs: CLI errors, notification failures,
/// container start failures, system issues, etc.
///
/// This solves the problem where a container fails to start but there
/// are no container logs because the container never ran — the error
/// only appeared in Xcode's console.
@Observable
final class AppEventLog {

    static let shared = AppEventLog()

    var events: [AppEvent] = []
    var maxEvents: Int = 5_000

    var unreadCount: Int {
        events.filter { !$0.isRead && $0.level == .error }.count
    }

    // MARK: - Logging

    func info(_ message: String, source: String = "App") {
        append(AppEvent(level: .info, source: source, message: message))
    }

    func warning(_ message: String, source: String = "App") {
        append(AppEvent(level: .warning, source: source, message: message))
    }

    func error(_ message: String, source: String = "App") {
        append(AppEvent(level: .error, source: source, message: message))
    }

    func error(_ error: Error, context: String, source: String = "App") {
        append(AppEvent(
            level: .error,
            source: source,
            message: "\(context): \(error.localizedDescription)"
        ))
    }

    func cliError(command: String, exitCode: Int32, stderr: String) {
        let msg = "CLI command failed: `container \(command)` (exit \(exitCode))"
        let detail = stderr.isEmpty ? msg : "\(msg)\n\(stderr)"
        append(AppEvent(level: .error, source: "CLI", message: detail))
    }

    func containerEvent(_ containerName: String, _ message: String, level: AppEventLevel = .info) {
        append(AppEvent(level: level, source: containerName, message: message))
    }

    func markAllRead() {
        for i in events.indices {
            events[i].isRead = true
        }
    }

    func clear() {
        events.removeAll()
    }

    // MARK: - Export

    func exportAsText() -> String {
        events.map { event in
            let ts = Formatters.logTimestamp(event.timestamp)
            return "[\(ts)] [\(event.level.rawValue.uppercased())] [\(event.source)] \(event.message)"
        }.joined(separator: "\n")
    }

    // MARK: - Internal

    private func append(_ event: AppEvent) {
        events.append(event)
        if events.count > maxEvents {
            events.removeFirst(events.count - maxEvents)
        }

        // Also print to console for Xcode debugging
        print("[\(event.level.rawValue)] [\(event.source)] \(event.message)")
    }
}

// MARK: - Event model

struct AppEvent: Identifiable {
    let id = UUID()
    let timestamp = Date()
    let level: AppEventLevel
    let source: String
    let message: String
    var isRead: Bool = false
}

enum AppEventLevel: String, CaseIterable {
    case info    = "info"
    case warning = "warning"
    case error   = "error"

    var iconName: String {
        switch self {
        case .info:    return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error:   return "xmark.circle.fill"
        }
    }
}
