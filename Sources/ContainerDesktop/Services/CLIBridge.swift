import Foundation

/// Thread-safe container for pipe read results.
/// Used by CLIBridge to collect stdout/stderr from background threads
/// without capturing mutable variables in Sendable closures.
private final class PipeReadResult: @unchecked Sendable {
    var stdout = Data()
    var stderr = Data()
}

/// Bridge to the `container` CLI binary.
///
/// Provides structured execution of CLI commands with proper
/// error handling, output parsing, and streaming support.
/// All CLI service implementations delegate to this class.
actor CLIBridge {

    private let executablePath: String
    private let defaultTimeout: Duration

    /// Result of a CLI command execution.
    struct CommandResult: Sendable {
        let exitCode: Int32
        let stdout: String
        let stderr: String

        var succeeded: Bool { exitCode == 0 }
    }

    init(executablePath: String = "/usr/local/bin/container", defaultTimeout: Duration = .seconds(30)) {
        self.executablePath = executablePath
        self.defaultTimeout = defaultTimeout
    }

    // MARK: - Executable discovery

    /// Verify the CLI binary exists and is executable.
    nonisolated func validateExecutable() throws {
        let fm = FileManager.default
        guard fm.fileExists(atPath: executablePath) else {
            throw AppError.cliNotFound(path: executablePath)
        }
        guard fm.isExecutableFile(atPath: executablePath) else {
            throw AppError.cliNotFound(path: executablePath)
        }
    }

    // MARK: - Synchronous execution (collect all output)

    /// Run a CLI command and collect the full output.
    /// Throws on non-zero exit code.
    func run(_ arguments: [String], timeout: Duration? = nil) async throws -> CommandResult {
        try validateExecutable()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        // Prevent the CLI from prompting for input
        process.standardInput = FileHandle.nullDevice

        // Inherit environment but ensure PATH includes common locations
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AppError.cliExecutionFailed(
                    command: arguments.joined(separator: " "),
                    exitCode: -1,
                    stderr: error.localizedDescription
                ))
                return
            }

            // Read stdout and stderr concurrently to prevent pipe deadlock.
            // If the process writes more than the pipe buffer (64KB on macOS),
            // it blocks until someone drains the pipe. Reading in background
            // threads ensures the pipe is drained while the process runs.
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading
            let pipeResult = PipeReadResult()
            let readGroup = DispatchGroup()

            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pipeResult.stdout = stdoutHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pipeResult.stderr = stderrHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            // Set up timeout
            let effectiveTimeout = timeout ?? defaultTimeout
            let timeoutTask = Task {
                try await Task.sleep(for: effectiveTimeout)
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()

                // Wait for pipe reads to finish (they will, since the process ended
                // and the write ends of the pipes are closed)
                readGroup.wait()

                let stdout = String(data: pipeResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: pipeResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let result = CommandResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// Run a CLI command with data piped to stdin.
    /// Used for secrets like passwords to avoid exposing them in the process list
    /// (which `ps auxww` or similar tools could capture from argv).
    /// Throws on non-zero exit code.
    func runWithStdin(_ arguments: [String], stdinData: Data, timeout: Duration? = nil) async throws -> CommandResult {
        try validateExecutable()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        let stdinPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        process.standardInput = stdinPipe

        // Inherit environment but ensure PATH includes common locations
        var env = ProcessInfo.processInfo.environment
        let extraPaths = ["/usr/local/bin", "/opt/homebrew/bin"]
        let currentPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = (extraPaths + [currentPath]).joined(separator: ":")
        process.environment = env

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: AppError.cliExecutionFailed(
                    command: arguments.joined(separator: " "),
                    exitCode: -1,
                    stderr: error.localizedDescription
                ))
                return
            }

            // Write the secret to stdin and close immediately so the process
            // sees EOF and doesn't hang waiting for more input.
            do {
                try stdinPipe.fileHandleForWriting.write(contentsOf: stdinData)
                try stdinPipe.fileHandleForWriting.close()
            } catch {
                process.terminate()
                continuation.resume(throwing: AppError.cliExecutionFailed(
                    command: arguments.joined(separator: " "),
                    exitCode: -1,
                    stderr: "Failed to write to stdin: \(error.localizedDescription)"
                ))
                return
            }

            // Read stdout and stderr concurrently to prevent pipe deadlock
            let stdoutHandle = stdoutPipe.fileHandleForReading
            let stderrHandle = stderrPipe.fileHandleForReading
            let pipeResult = PipeReadResult()
            let readGroup = DispatchGroup()

            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pipeResult.stdout = stdoutHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            readGroup.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                pipeResult.stderr = stderrHandle.readDataToEndOfFile()
                readGroup.leave()
            }

            let effectiveTimeout = timeout ?? defaultTimeout
            let timeoutTask = Task {
                try await Task.sleep(for: effectiveTimeout)
                if process.isRunning {
                    process.terminate()
                }
            }

            process.terminationHandler = { proc in
                timeoutTask.cancel()
                readGroup.wait()

                let stdout = String(data: pipeResult.stdout, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let stderr = String(data: pipeResult.stderr, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                let result = CommandResult(
                    exitCode: proc.terminationStatus,
                    stdout: stdout,
                    stderr: stderr
                )
                continuation.resume(returning: result)
            }
        }
    }

    /// Run a command and throw if it fails, returning stdout on success.
    func runOrThrow(_ arguments: [String], timeout: Duration? = nil) async throws -> String {
        let result = try await run(arguments, timeout: timeout)
        guard result.succeeded else {
            let safeCmd = Self.redactSensitiveArgs(arguments)
            AppEventLog.shared.cliError(
                command: safeCmd,
                exitCode: result.exitCode,
                stderr: result.stderr
            )
            throw AppError.cliExecutionFailed(
                command: "container \(safeCmd)",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        return result.stdout
    }

    /// Redact sensitive arguments from a command for safe logging.
    /// Replaces values after `-e` / `--env` and `--password` flags with `***`.
    nonisolated static func redactSensitiveArgs(_ args: [String]) -> String {
        var result: [String] = []
        var redactNext = false
        for arg in args {
            if redactNext {
                result.append("***")
                redactNext = false
            } else if arg == "-e" || arg == "--env" {
                result.append(arg)
                redactNext = true
            } else if arg == "--password" {
                result.append(arg)
                redactNext = true
            } else if arg.hasPrefix("-e=") || arg.hasPrefix("--env=") {
                let prefix = arg.hasPrefix("-e=") ? "-e=" : "--env="
                let rest = String(arg.dropFirst(prefix.count))
                if let eqIndex = rest.firstIndex(of: "=") {
                    let key = rest[rest.startIndex..<eqIndex]
                    result.append("\(prefix)\(key)=***")
                } else {
                    result.append("\(prefix)***")
                }
            } else {
                result.append(arg)
            }
        }
        return result.joined(separator: " ")
    }

    // MARK: - Streaming execution (line-by-line output)

    /// Run a CLI command and stream stdout line by line.
    /// Used for log following, build output, pull progress, etc.
    nonisolated func stream(_ arguments: [String]) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try self.validateExecutable()
                } catch {
                    continuation.finish(throwing: error)
                    return
                }

                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.executablePath)
                process.arguments = arguments
                process.standardInput = FileHandle.nullDevice

                let stdoutPipe = Pipe()
                let stderrPipe = Pipe()
                process.standardOutput = stdoutPipe
                process.standardError = stderrPipe

                // Thread-safe line buffers shared between readability and termination handlers
                let stdoutBuffer = LineBuffer()
                let stderrBuffer = LineBuffer()

                stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        if let remainder = stdoutBuffer.flush() {
                            continuation.yield(remainder)
                        }
                        return
                    }
                    guard let chunk = String(data: data, encoding: .utf8) else { return }

                    let lines = stdoutBuffer.append(chunk)
                    for line in lines {
                        continuation.yield(line)
                    }
                }

                // Also stream stderr — build tools like BuildKit write progress to stderr
                stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        if let remainder = stderrBuffer.flush() {
                            continuation.yield(remainder)
                        }
                        return
                    }
                    guard let chunk = String(data: data, encoding: .utf8) else { return }

                    let lines = stderrBuffer.append(chunk)
                    for line in lines {
                        continuation.yield(line)
                    }
                }

                process.terminationHandler = { proc in
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                    if let remainder = stdoutBuffer.flush() {
                        continuation.yield(remainder)
                    }
                    if let remainder = stderrBuffer.flush() {
                        continuation.yield(remainder)
                    }
                    if proc.terminationStatus != 0 {
                        let stderrData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
                        let stderr = String(data: stderrData, encoding: .utf8) ?? ""
                        continuation.finish(throwing: AppError.cliExecutionFailed(
                            command: "container \(CLIBridge.redactSensitiveArgs(arguments))",
                            exitCode: proc.terminationStatus,
                            stderr: stderr
                        ))
                    } else {
                        continuation.finish()
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    if process.isRunning {
                        process.terminate()
                    }
                }

                do {
                    try process.run()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - JSON execution

    /// Run a command that returns JSON and decode it.
    func runJSON<T: Decodable>(_ type: T.Type, arguments: [String]) async throws -> T {
        let output = try await runOrThrow(arguments)
        guard let data = output.data(using: .utf8) else {
            throw AppError.parseError("Failed to convert output to data")
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw AppError.parseError("JSON decode failed: \(error.localizedDescription)\nRaw output: \(output.prefix(500))")
        }
    }
}

// MARK: - Thread-safe line buffer

/// A thread-safe buffer that accumulates text chunks and splits them
/// into complete lines. Used by `CLIBridge.stream()` where the
/// readabilityHandler and terminationHandler closures run on
/// different threads and both need to access the buffer.
private final class LineBuffer: @unchecked Sendable {
    private var buffer = ""
    private let lock = NSLock()

    /// Append a chunk of text. Returns any complete lines
    /// (split on newlines), keeping the last partial line buffered.
    func append(_ chunk: String) -> [String] {
        lock.lock()
        defer { lock.unlock() }

        buffer += chunk
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > 1 else { return [] }

        let completeLines = lines.dropLast().map(String.init)
        buffer = String(lines.last ?? "")
        return completeLines
    }

    /// Flush any remaining buffered text. Returns nil if empty.
    func flush() -> String? {
        lock.lock()
        defer { lock.unlock() }

        guard !buffer.isEmpty else { return nil }
        let remainder = buffer
        buffer = ""
        return remainder
    }
}