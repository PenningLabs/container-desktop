import Foundation

/// Container service implementation that shells out to the `container` CLI.
/// The protocol-based design allows future migration to Apple's Containerization
/// framework Swift APIs once they stabilize.
final class CLIContainerService: ContainerServiceProtocol, Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    // MARK: - List

    func listContainers() async throws -> [ContainerModel] {
        // `container ls --format json --all` returns JSON array
        let output = try await cli.runOrThrow(["ls", "--format", "json", "--all"])

        guard !output.isEmpty else { return [] }

        // The CLI may output one JSON object per line (NDJSON) or a JSON array.
        // Handle both formats.
        let containers = try parseContainerList(output)
        return containers
    }

    /// Parse the CLI's JSON output into ContainerModel instances.
    /// Handles both JSON array format and newline-delimited JSON.
    private func parseContainerList(_ output: String) throws -> [ContainerModel] {
        // Try JSON array first
        if let data = output.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { parseContainerJSON($0) }
        }

        // Fall back to newline-delimited JSON
        return output
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> ContainerModel? in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return parseContainerJSON(json)
            }
    }

    private func parseContainerJSON(_ json: [String: Any]) -> ContainerModel? {
        // v1.0.0 JSON structure:
        // {
        //   "configuration": {
        //     "id": "my-container",
        //     "image": { "reference": "...", "descriptor": {...} },
        //     "platform": { "architecture": "arm64", "os": "linux" },
        //     "resources": { "cpus": 4, "memoryInBytes": 1073741824, "cpuOverhead": 1 },
        //     "networks": [{ "network": "default", "options": { "hostname": "...", "mtu": 1280 }}],
        //     "dns": { "domain": "test", ... },
        //     "publishedPorts": [{ "containerPort": 80, "hostPort": 8080, "proto": "tcp", ... }],
        //     "mounts": [{ "destination": "/app", "source": "/host", "type": {"virtiofs": {}}, "options": [] }]
        //   },
        //   "id": "my-container",
        //   "status": { "state": "stopped", "networks": [...] }
        // }

        let config = json["configuration"] as? [String: Any] ?? [:]

        // Container name/id
        let name = config["id"] as? String ?? json["id"] as? String
        guard let name = name, !name.isEmpty else { return nil }

        // Status: v1.0.0 uses {"state": "stopped"}, older used plain string
        let statusObj = json["status"] as? [String: Any]
        let statusStr = statusObj?["state"] as? String
            ?? json["status"] as? String
            ?? "unknown"
        let status = ContainerStatus(rawValue: statusStr.lowercased()) ?? .unknown

        // Image reference
        let imageConfig = config["image"] as? [String: Any] ?? [:]
        var imageRef = imageConfig["reference"] as? String ?? "unknown"
        if imageRef.hasPrefix("docker.io/library/") {
            imageRef = String(imageRef.dropFirst("docker.io/library/".count))
        }

        // IP address: v1.0.0 moved into status.networks
        let statusNetworks = statusObj?["networks"] as? [[String: Any]]
            ?? json["networks"] as? [[String: Any]]
            ?? []
        var ipAddress: String? = nil
        if let firstNetwork = statusNetworks.first,
           let ipWithCIDR = firstNetwork["ipv4Address"] as? String {
            ipAddress = ipWithCIDR.components(separatedBy: "/").first
        }

        // Network name and DNS domain from configuration
        let configNetworks = config["networks"] as? [[String: Any]] ?? []
        let networkName = configNetworks.first?["network"] as? String

        let dnsConfig = config["dns"] as? [String: Any] ?? [:]
        let dnsDomain = dnsConfig["domain"] as? String

        // Architecture
        let platform = config["platform"] as? [String: Any] ?? [:]
        let archStr = platform["architecture"] as? String ?? "arm64"
        let arch = Architecture(rawValue: archStr) ?? .unknown

        // Resources
        let resources = config["resources"] as? [String: Any] ?? [:]
        let cpus = resources["cpus"] as? Int
        let memoryBytes = resources["memoryInBytes"] as? UInt64
            ?? (resources["memoryInBytes"] as? Int).map({ UInt64($0) })

        // Started date
        var createdAt: Date? = nil
        if let ts = statusObj?["startedDate"] as? Double ?? json["startedDate"] as? Double {
            createdAt = Date(timeIntervalSinceReferenceDate: ts)
        }

        return ContainerModel(
            id: name,
            name: name,
            image: imageRef,
            status: status,
            ipAddress: ipAddress,
            dnsDomain: dnsDomain,
            networkName: networkName ?? "default",
            architecture: arch,
            createdAt: createdAt,
            pid: nil,
            memory: memoryBytes,
            cpus: cpus
        )
    }

    // MARK: - Create

    func createContainer(
        name: String,
        image: String,
        options: ContainerCreateOptions
    ) async throws -> ContainerModel {
        // Defense-in-depth: validate inputs even though the UI should have checked
        guard InputValidation.isValidContainerName(name) else {
            throw AppError.unknown("Invalid container name: '\(name)'")
        }
        guard InputValidation.isValidImageReference(image) else {
            throw AppError.unknown("Invalid image reference: '\(image)'")
        }

        var args = ["run"]

        // Detached mode
        if options.detached {
            args.append("-d")
        }

        // Interactive / TTY
        if options.interactive {
            args += ["-t", "-i"]
        }

        // Name
        args += ["--name", name]

        // Resource limits
        if let memory = options.memory {
            args += ["--memory", "\(memory / (1024 * 1024 * 1024))g"]
        }
        if let cpus = options.cpus {
            args += ["--cpus", "\(cpus)"]
        }

        // Architecture
        if options.architecture != .arm64 {
            args += ["--arch", options.architecture.rawValue]
        }

        // DNS domain
        if let dns = options.dnsDomain {
            args += ["--dns-domain", dns]
        }

        // Environment variables
        for (key, value) in options.environment {
            args += ["-e", "\(key)=\(value)"]
        }

        // Mounts
        for mount in options.mounts {
            let ro = mount.readOnly ? ":ro" : ""
            args += ["-v", "\(mount.source):\(mount.destination)\(ro)"]
        }

        // Port forwarding (--publish must come before image name)
        for port in options.portMappings {
            args += ["--publish", port.cliFlag]
        }

        // Socket forwarding
        for socket in options.socketMappings {
            args += ["--publish-socket", socket.cliFlag]
        }

        // SSH agent forwarding
        if options.sshForwarding {
            args.append("--ssh")
        }

        // Init process (lightweight init as PID 1)
        if options.initProcess {
            args.append("--init")
        }

        // Nested virtualization (M3+ only)
        if options.virtualization {
            args.append("--virtualization")
        }

        // Network selection with optional MAC address
        if let network = options.network, !network.isEmpty {
            if let mac = options.macAddress, !mac.isEmpty {
                args += ["--network", "\(network),mac=\(mac)"]
            } else {
                args += ["--network", network]
            }
        } else if let mac = options.macAddress, !mac.isEmpty {
            args += ["--network", "default,mac=\(mac)"]
        }

        // Auto-remove on stop
        if options.autoRemove {
            args.append("--rm")
        }

        // Environment file
        if let envFile = options.envFile, !envFile.isEmpty {
            args += ["--env-file", envFile]
        }

        // Working directory
        if let workDir = options.workingDir, !workDir.isEmpty {
            args += ["--workdir", workDir]
        }

        // Entrypoint override
        if let entrypoint = options.entrypoint, !entrypoint.isEmpty {
            args += ["--entrypoint", entrypoint]
        }

        // User
        if let user = options.user, !user.isEmpty {
            args += ["--user", user]
        }

        // Hostname
        if let hostname = options.hostname, !hostname.isEmpty {
            args += ["--hostname", hostname]
        }

        // Image (must be after all flags)
        args.append(image)

        // Command override
        if let command = options.command {
            args += command
        }

        _ = try await cli.runOrThrow(args, timeout: .seconds(60))

        // Refresh the list to get the created container with its full metadata
        let containers = try await listContainers()
        guard let created = containers.first(where: { $0.name == name }) else {
            // Container was created but couldn't be found in listing —
            // return a minimal model
            return ContainerModel(
                id: name,
                name: name,
                image: image,
                status: options.detached ? .running : .stopped,
                ipAddress: nil,
                dnsDomain: options.dnsDomain,
                networkName: options.network ?? "default",
                architecture: options.architecture,
                createdAt: Date(),
                pid: nil,
                memory: options.memory,
                cpus: options.cpus
            )
        }
        return created
    }

    // MARK: - Stop

    func stopContainer(id: String, timeout: Duration) async throws {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        _ = try await cli.runOrThrow(
            ["stop", id],
            timeout: timeout + .seconds(5)
        )
    }

    // MARK: - Start

    func startContainer(id: String) async throws {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        _ = try await cli.runOrThrow(
            ["start", id],
            timeout: .seconds(30)
        )
    }

    // MARK: - Remove

    func removeContainer(id: String, force: Bool) async throws {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        var args = ["rm"]
        if force {
            args.append("--force")
        }
        args.append(id)
        _ = try await cli.runOrThrow(args)
    }

    // MARK: - Logs

    func logs(
        containerID: String,
        follow: Bool,
        includeBoot: Bool
    ) -> AsyncThrowingStream<LogEntry, Error> {
        guard InputValidation.isValidContainerName(containerID) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AppError.unknown("Invalid container ID: '\(containerID)'"))
            }
        }

        var args = ["logs"]
        if follow {
            args.append("--follow")
        }
        if includeBoot {
            args.append("--boot")
        }
        args.append(containerID)

        let lineStream = cli.stream(args)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in lineStream {
                        let entry = Self.parseLogLine(line)
                        continuation.yield(entry)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    /// Parse a raw log line into a LogEntry.
    /// Expected format: "2024-01-15T10:30:00Z  source  | message"
    /// Falls back to treating the whole line as the message.
    static func parseLogLine(_ line: String) -> LogEntry {
        // Try to extract timestamp and source from structured log format
        let pattern = #"^(\d{4}-\d{2}-\d{2}T[\d:.]+Z?)\s+(\w+)\s+\|\s*(.*)$"#
        if let regex = try? NSRegularExpression(pattern: pattern),
           let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) {

            let timestampStr = String(line[Range(match.range(at: 1), in: line)!])
            let sourceStr = String(line[Range(match.range(at: 2), in: line)!])
            let message = String(line[Range(match.range(at: 3), in: line)!])

            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            let timestamp = formatter.date(from: timestampStr) ?? Date()

            let source: LogSource = sourceStr.lowercased() == "stderr" ? .stderr : .stdout

            return LogEntry(timestamp: timestamp, source: source, message: message)
        }

        // Unstructured line
        return LogEntry(timestamp: Date(), source: .stdout, message: line)
    }

    // MARK: - Exec

    func exec(
        containerID: String,
        command: [String],
        tty: Bool
    ) async throws -> any ProcessChannel {
        // Terminal exec uses PTY via SwiftTerm in the UI layer.
        // This protocol method is not used directly — see TerminalPanelView.
        throw AppError.unknown("Use the Terminal tab for interactive exec sessions")
    }

    // MARK: - Inspect

    func inspect(containerID: String) async throws -> ContainerDetail {
        // Use the list command and find the matching container —
        // the JSON from `container ls --format json --all` contains
        // all the config detail we need.
        let output = try await cli.runOrThrow(["ls", "--format", "json", "--all"])

        guard let data = output.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            throw AppError.parseError("Failed to parse container list for inspect")
        }

        // Find the container by configuration.id
        guard let json = jsonArray.first(where: {
            let config = $0["configuration"] as? [String: Any] ?? [:]
            return (config["id"] as? String) == containerID
        }) else {
            throw AppError.unknown("Container '\(containerID)' not found")
        }

        guard let model = parseContainerJSON(json) else {
            throw AppError.parseError("Failed to parse container data")
        }

        // Extract detailed config from configuration.initProcess
        let configJSON = json["configuration"] as? [String: Any] ?? [:]
        let initProcess = configJSON["initProcess"] as? [String: Any] ?? [:]

        let envArray = initProcess["environment"] as? [String] ?? []
        var envDict: [String: String] = [:]
        for envStr in envArray {
            let parts = envStr.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                envDict[String(parts[0])] = String(parts[1])
            }
        }

        // Parse user from initProcess.user
        // Two formats: {"raw":{"userString":"1000:1000"}} or {"id":{"uid":0,"gid":0}}
        let userConfig = initProcess["user"] as? [String: Any] ?? [:]
        let userString: String
        if let raw = userConfig["raw"] as? [String: Any],
           let rawStr = raw["userString"] as? String {
            userString = rawStr
        } else if let idConfig = userConfig["id"] as? [String: Any] {
            let uid = idConfig["uid"] as? Int ?? 0
            userString = uid == 0 ? "root" : "\(uid)"
        } else {
            userString = "root"
        }

        // Parse published ports from configuration.publishedPorts
        // Actual format: [{"hostPort": 8000, "hostAddress": "0.0.0.0", "containerPort": 8000, "proto": "tcp", "count": 1}]
        let publishedPortsJSON = configJSON["publishedPorts"] as? [[String: Any]] ?? []
        let publishedPorts: [PortMapping] = publishedPortsJSON.compactMap { portJSON in
            let hp = portJSON["hostPort"] as? Int ?? 0
            let cp = portJSON["containerPort"] as? Int ?? 0
            guard hp > 0 || cp > 0 else { return nil }
            let protoStr = portJSON["proto"] as? String ?? portJSON["protocol"] as? String ?? "tcp"
            let proto = protoStr == "udp" ? PortProtocol.udp : PortProtocol.tcp
            let hostIP = portJSON["hostAddress"] as? String ?? portJSON["hostIP"] as? String ?? ""
            return PortMapping(hostIP: hostIP, hostPort: hp, containerPort: cp, protocol_: proto)
        }

        // Parse published sockets from configuration.publishedSockets
        let publishedSocketsJSON = configJSON["publishedSockets"] as? [[String: Any]] ?? []
        let publishedSockets: [SocketMapping] = publishedSocketsJSON.compactMap { sockJSON in
            let hostPath = sockJSON["hostPath"] as? String ?? ""
            let containerPath = sockJSON["containerPath"] as? String ?? ""
            guard !hostPath.isEmpty && !containerPath.isEmpty else { return nil }
            // Strip file:// prefix if present
            let cleanHost = hostPath.replacingOccurrences(of: "file://", with: "")
            let cleanContainer = containerPath.replacingOccurrences(of: "file://", with: "")
            guard cleanHost != "/" && cleanContainer != "/" else { return nil }
            return SocketMapping(hostPath: cleanHost, containerPath: cleanContainer)
        }

        // Parse mounts from configuration.mounts
        // Actual format: [{"source": "/path", "destination": "/path", "type": {"virtiofs": {}}, "options": []}]
        let mountsJSON = configJSON["mounts"] as? [[String: Any]] ?? []
        let parsedMounts: [MountSpec] = mountsJSON.compactMap { mountJSON in
            let source = mountJSON["source"] as? String ?? ""
            let destination = mountJSON["destination"] as? String ?? ""
            // Skip tmpfs and other mounts without a host source path
            guard !source.isEmpty && !destination.isEmpty else { return nil }
            let options = mountJSON["options"] as? [String] ?? []
            let readOnly = options.contains("ro")
            return MountSpec(source: source, destination: destination, readOnly: readOnly)
        }

        let config = ContainerConfig(
            entrypoint: [initProcess["executable"] as? String ?? ""],
            cmd: initProcess["arguments"] as? [String] ?? [],
            workingDir: initProcess["workingDirectory"] as? String ?? "/",
            user: userString,
            environment: envDict,
            exposedPorts: [],
            publishedPorts: publishedPorts,
            publishedSockets: publishedSockets,
            mounts: parsedMounts
        )

        let state = ContainerState(
            status: model.status,
            startedAt: model.createdAt,
            finishedAt: nil,
            exitCode: nil,
            error: nil
        )

        return ContainerDetail(model: model, config: config, state: state)
    }

    // MARK: - Kill

    func killContainer(id: String) async throws {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        _ = try await cli.runOrThrow(["kill", id])
        AppEventLog.shared.containerEvent(id, "Container killed (SIGKILL)")
    }

    // MARK: - File Copy

    /// Copy a file or directory from the host into a running container.
    func copyToContainer(id: String, hostPath: String, containerPath: String) async throws {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        guard InputValidation.isValidPath(hostPath) else {
            throw AppError.unknown("Invalid host path: '\(hostPath)'")
        }
        guard InputValidation.isValidPath(containerPath) else {
            throw AppError.unknown("Invalid container path: '\(containerPath)'")
        }
        _ = try await cli.runOrThrow(["cp", hostPath, "\(id):\(containerPath)"], timeout: .seconds(120))
        AppEventLog.shared.containerEvent(id, "Copied '\(hostPath)' → container:\(containerPath)")
    }

    /// Copy a file or directory from a running container to the host.
    func copyFromContainer(id: String, containerPath: String, hostPath: String) async throws {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        guard InputValidation.isValidPath(containerPath) else {
            throw AppError.unknown("Invalid container path: '\(containerPath)'")
        }
        guard InputValidation.isValidPath(hostPath) else {
            throw AppError.unknown("Invalid host path: '\(hostPath)'")
        }
        _ = try await cli.runOrThrow(["cp", "\(id):\(containerPath)", hostPath], timeout: .seconds(120))
        AppEventLog.shared.containerEvent(id, "Copied container:\(containerPath) → '\(hostPath)'")
    }

    // MARK: - Disk Cleanup

    /// Reclaim unused space on a running container's root filesystem and named volumes.
    func cleanContainer(id: String) async throws -> String {
        guard InputValidation.isValidContainerName(id) else {
            throw AppError.unknown("Invalid container ID: '\(id)'")
        }
        // Trimming a large filesystem can take a while, so allow a generous timeout.
        return try await cli.runOrThrow(["clean", id], timeout: .seconds(300))
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Stats

    /// Fetch a single stats snapshot for a container.
    /// Returns the raw command result for parsing by the caller.
    func stats(containerID: String, json: Bool) async throws -> CLIBridge.CommandResult {
        guard InputValidation.isValidContainerName(containerID) else {
            throw AppError.unknown("Invalid container ID: '\(containerID)'")
        }
        var args = ["stats", containerID, "--no-stream"]
        if json {
            args += ["--format", "json"]
        }
        return try await cli.run(args, timeout: .seconds(10))
    }

    // MARK: - Prune

    /// Remove all stopped containers.
    func pruneContainers() async throws {
        _ = try await cli.runOrThrow(["prune", "--force"])
    }
}
