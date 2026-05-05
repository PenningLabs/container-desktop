import AppKit
import Foundation
import SwiftUI

// MARK: - Log stream view model

/// View model for real-time container log streaming.
///
/// Architecture:
/// - ALL incoming log entries are written to a temp file on disk (the "full log")
/// - Only the last `displayBufferSize` entries are kept in the `entries` array for display
/// - "Load earlier" pages in older entries from the disk file
/// - The filter searches the in-memory `entries` array (which is the visible window)
/// - "Save to file" and "Copy all" export from the full disk cache
@Observable
final class LogStreamViewModel {

    private let containerService: any ContainerServiceProtocol
    private var streamTask: Task<Void, Never>?

    // MARK: - State

    /// The visible entries — limited to `displayBufferSize`.
    var entries: [LogEntry] = []
    var isStreaming: Bool = false
    var autoScroll: Bool = true
    var filterText: String = ""
    var showTimestamps: Bool = true
    var showBootLogs: Bool = false
    var currentContainerID: String?

    /// Number of entries to keep in the display buffer.
    /// Reads from user's Settings preference; defaults to 10,000.
    var displayBufferSize: Int {
        let stored = UserDefaults.standard.integer(forKey: "maxLogEntries")
        return stored > 0 ? stored : 10_000
    }

    /// Total entries written to disk (including those not displayed).
    var totalEntryCount: Int = 0

    /// Whether there are earlier entries on disk that aren't displayed.
    var hasEarlierEntries: Bool { totalEntryCount > entries.count }

    /// How many entries are hidden (on disk but not in the display buffer).
    var hiddenEntryCount: Int { max(0, totalEntryCount - entries.count) }

    // MARK: - Disk cache

    /// File handle for writing entries to disk.
    private var cacheFileHandle: FileHandle?
    private var cacheFilePath: URL?

    // MARK: - Computed

    var filteredEntries: [LogEntry] {
        guard !filterText.isEmpty else { return entries }
        return entries.filter {
            $0.message.localizedCaseInsensitiveContains(filterText)
        }
    }

    var entryCount: Int { entries.count }

    // MARK: - Init

    init(containerService: any ContainerServiceProtocol) {
        self.containerService = containerService
    }

    deinit {
        cleanupCacheFile()
    }

    // MARK: - Actions

    func startStreaming(containerID: String, includeBoot: Bool = false) {
        stopStreaming()
        entries = []
        totalEntryCount = 0
        currentContainerID = containerID
        isStreaming = true

        // Create a new temp file for this stream
        setupCacheFile(containerID: containerID)

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for try await entry in containerService.logs(
                    containerID: containerID,
                    follow: true,
                    includeBoot: includeBoot
                ) {
                    guard !Task.isCancelled else { break }
                    await MainActor.run {
                        self.appendEntry(entry)
                    }
                }
            } catch is CancellationError {
                // Normal cancellation — ignore
            } catch {
                // Stream ended with error
            }
            await MainActor.run {
                self.isStreaming = false
            }
        }
    }

    func stopStreaming() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }

    func clearLogs() {
        entries = []
        totalEntryCount = 0
        cleanupCacheFile()
        if let id = currentContainerID {
            setupCacheFile(containerID: id)
        }
    }

    /// Load earlier entries from the disk cache.
    func loadEarlierEntries(count: Int = 500) {
        guard let path = cacheFilePath else { return }
        guard let data = try? String(contentsOf: path, encoding: .utf8) else { return }

        let allLines = data.components(separatedBy: "\n").filter { !$0.isEmpty }
        let currentlyShowing = entries.count
        let totalOnDisk = allLines.count

        // How many more can we load?
        let alreadyLoadedFromEnd = currentlyShowing
        let availableToLoad = totalOnDisk - alreadyLoadedFromEnd
        guard availableToLoad > 0 else { return }

        let loadCount = min(count, availableToLoad)
        let startIndex = availableToLoad - loadCount

        let olderEntries = allLines[startIndex..<(startIndex + loadCount)]
            .compactMap { LogEntry.deserialize($0) }

        // Prepend older entries
        entries.insert(contentsOf: olderEntries, at: 0)
    }

    /// Copy all visible log entries as plain text.
    func copyLogsToClipboard() {
        let text = filteredEntries.map { entry in
            let ts = entry.timestamp.map { Formatters.logTimestamp($0) } ?? ""
            return "\(ts)  \(entry.message)"
        }.joined(separator: "\n")

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    /// Copy ALL entries from disk cache (not just visible buffer).
    func copyAllLogsToClipboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(fullLogText(), forType: .string)
    }

    /// Get the full log text from disk for export.
    func fullLogText() -> String {
        guard let path = cacheFilePath,
              let data = try? String(contentsOf: path, encoding: .utf8) else {
            // Fall back to in-memory entries
            return entries.map { entry in
                let ts = entry.timestamp.map { Formatters.logTimestamp($0) } ?? ""
                return "\(ts)  \(entry.message)"
            }.joined(separator: "\n")
        }

        // Deserialise and format
        return data.components(separatedBy: "\n")
            .filter { !$0.isEmpty }
            .compactMap { LogEntry.deserialize($0) }
            .map { entry in
                let ts = entry.timestamp.map { Formatters.logTimestamp($0) } ?? ""
                return "\(ts)  \(entry.message)"
            }
            .joined(separator: "\n")
    }

    // MARK: - Internal

    private func appendEntry(_ entry: LogEntry) {
        // Write to disk cache
        writeToDisk(entry)
        totalEntryCount += 1

        // Add to display buffer
        entries.append(entry)

        // Trim display buffer to keep only the tail
        if entries.count > displayBufferSize {
            let overflow = entries.count - displayBufferSize
            entries.removeFirst(overflow)
        }
    }

    // MARK: - Disk cache management

    private func setupCacheFile(containerID: String) {
        cleanupCacheFile()

        let tempDir = FileManager.default.temporaryDirectory
        // Sanitize containerID for safe use in filename
        let safeID = InputValidation.sanitizeContainerName(containerID)
        let fileName = "container-logs-\(safeID)-\(UUID().uuidString.prefix(8)).log"
        let path = tempDir.appendingPathComponent(fileName)

        // Create with restrictive permissions (owner read/write only)
        // Container logs may contain sensitive output
        FileManager.default.createFile(
            atPath: path.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        )
        cacheFilePath = path
        cacheFileHandle = try? FileHandle(forWritingTo: path)
        cacheFileHandle?.seekToEndOfFile()
    }

    private func writeToDisk(_ entry: LogEntry) {
        guard let handle = cacheFileHandle else { return }
        let line = entry.serialized + "\n"
        if let data = line.data(using: .utf8) {
            handle.write(data)
        }
    }

    private func cleanupCacheFile() {
        cacheFileHandle?.closeFile()
        cacheFileHandle = nil
        if let path = cacheFilePath {
            try? FileManager.default.removeItem(at: path)
        }
        cacheFilePath = nil
    }
}

// MARK: - System view model

/// View model for system status and lifecycle management.
@Observable
final class SystemViewModel {

    private let systemService: any SystemServiceProtocol
    private let builderService: any BuilderServiceProtocol
    private var statusTask: Task<Void, Never>?

    // MARK: - State

    var systemStatus: SystemStatus = .offline
    var builderStatus: BuilderStatus = BuilderStatus(isRunning: false, memory: nil, cpus: nil)
    var isLoading: Bool = false
    var isStartingSystem: Bool = false
    var isStoppingSystem: Bool = false
    var error: AppError?

    // CLI info
    var cliPath: String?
    var cliVersion: String?

    // MARK: - Computed

    var isSystemRunning: Bool { systemStatus.isRunning }

    // MARK: - Init

    init(systemService: any SystemServiceProtocol, builderService: any BuilderServiceProtocol) {
        self.systemService = systemService
        self.builderService = builderService
    }

    // MARK: - Actions

    func detectCLI() async {
        cliPath = ContainerCLILocator.locate()
        if let path = cliPath {
            cliVersion = await ContainerCLILocator.version(at: path)
            AppEventLog.shared.info("CLI found at \(path) (version: \(cliVersion ?? "unknown"))", source: "System")
        } else {
            AppEventLog.shared.error("Container CLI not found. Install from github.com/apple/container/releases", source: "System")
        }
    }

    func refreshStatus() async {
        isLoading = true
        defer { isLoading = false }
        do {
            systemStatus = try await systemService.status()
            do {
                builderStatus = try await builderService.status()
            } catch {
                builderStatus = BuilderStatus(isRunning: false, memory: nil, cpus: nil)
            }
            self.error = nil
        } catch {
            systemStatus = .offline
            self.error = .loadFailed(error)
        }
    }

    func startSystem() async {
        isStartingSystem = true
        defer { isStartingSystem = false }
        do {
            try await systemService.startSystem()
            AppEventLog.shared.info("Container system started", source: "System")
            await refreshStatus()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to start system", source: "System")
            self.error = .actionFailed("start system", error)
        }
    }

    func stopSystem() async {
        isStoppingSystem = true
        defer { isStoppingSystem = false }
        do {
            try await systemService.stopSystem()
            AppEventLog.shared.info("Container system stopped", source: "System")
            NotificationManager.shared.notifySystemStopped()
            await refreshStatus()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to stop system", source: "System")
            self.error = .actionFailed("stop system", error)
        }
    }

    func startPeriodicRefresh(interval: TimeInterval = 10) {
        stopPeriodicRefresh()
        statusTask = Task {
            while !Task.isCancelled {
                await refreshStatus()
                try? await Task.sleep(for: .seconds(interval))
            }
        }
    }

    func stopPeriodicRefresh() {
        statusTask?.cancel()
        statusTask = nil
    }
}
