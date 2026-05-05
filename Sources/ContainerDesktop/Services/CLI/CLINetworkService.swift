import Foundation

/// Network management service.
/// Uses `container network` CLI commands (macOS 26+).
final class CLINetworkService: Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    /// List all networks.
    func listNetworks() async throws -> [NetworkInfo] {
        // Try JSON format first
        let result = try await cli.run(["network", "list", "--format", "json"])
        if result.succeeded, let data = result.stdout.data(using: .utf8) {
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return jsonArray.compactMap { parseNetworkJSON($0) }
            }
        }

        // Try table format (might be "list" or "ls")
        let tableResult = try await cli.run(["network", "list"])
        if tableResult.succeeded {
            return parseNetworkTable(tableResult.stdout)
        }

        // Try "ls" alias
        let lsResult = try await cli.run(["network", "ls"])
        if lsResult.succeeded {
            return parseNetworkTable(lsResult.stdout)
        }

        // If all failed, the subcommand probably doesn't exist on this version
        throw AppError.cliExecutionFailed(
            command: "container network list",
            exitCode: result.exitCode,
            stderr: result.stderr.isEmpty ? "Network management may require macOS 26 or later." : result.stderr
        )
    }

    /// Create a new network with optional custom subnets.
    func createNetwork(name: String, subnet: String? = nil, subnetV6: String? = nil) async throws {
        // Validate inputs
        guard InputValidation.isValidNetworkName(name) else {
            throw AppError.unknown("Invalid network name: '\(name)'")
        }
        if let s = subnet, !s.isEmpty {
            guard InputValidation.isValidCIDR(s) else {
                throw AppError.unknown("Invalid IPv4 subnet: '\(s)'")
            }
        }
        if let s6 = subnetV6, !s6.isEmpty {
            guard InputValidation.isValidCIDR(s6) else {
                throw AppError.unknown("Invalid IPv6 subnet: '\(s6)'")
            }
        }

        var args = ["network", "create"]
        if let s = subnet, !s.isEmpty {
            args += ["--subnet", s]
        }
        if let s6 = subnetV6, !s6.isEmpty {
            args += ["--subnet-v6", s6]
        }
        args.append(name)
        _ = try await cli.runOrThrow(args)
        AppEventLog.shared.info("Network '\(name)' created", source: "Network")
    }

    /// Delete a network.
    func deleteNetwork(name: String) async throws {
        guard InputValidation.isValidNetworkName(name) else {
            throw AppError.unknown("Invalid network name: '\(name)'")
        }
        _ = try await cli.runOrThrow(["network", "delete", name])
        AppEventLog.shared.info("Network '\(name)' deleted", source: "Network")
    }

    // MARK: - Parsing

    private func parseNetworkJSON(_ json: [String: Any]) -> NetworkInfo? {
        // Actual format from CLI:
        // { "id": "test", "state": "running",
        //   "config": { "id": "test", "mode": "nat", ... },
        //   "status": { "ipv4Subnet": "192.168.66.0/24", "ipv4Gateway": "...", "ipv6Subnet": "..." } }
        guard let name = json["id"] as? String else { return nil }
        let state = json["state"] as? String ?? "unknown"
        let status = json["status"] as? [String: Any] ?? [:]
        let config = json["config"] as? [String: Any] ?? [:]
        let subnet = status["ipv4Subnet"] as? String
            ?? config["ipv4Subnet"] as? String
            ?? ""
        let gateway = status["ipv4Gateway"] as? String ?? ""
        let ipv6 = status["ipv6Subnet"] as? String ?? ""
        let mode = config["mode"] as? String ?? ""
        return NetworkInfo(
            name: name,
            state: state,
            subnet: subnet,
            gateway: gateway,
            ipv6Subnet: ipv6,
            mode: mode
        )
    }

    private func parseNetworkTable(_ output: String) -> [NetworkInfo] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        // Skip header
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
            guard parts.count >= 2 else { return nil }
            return NetworkInfo(
                name: parts[0],
                state: parts.count > 1 ? parts[1] : "unknown",
                subnet: parts.count > 2 ? parts[2] : "",
                gateway: "",
                ipv6Subnet: "",
                mode: ""
            )
        }
    }
}

/// Network info model.
struct NetworkInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    let state: String
    let subnet: String
    let gateway: String
    let ipv6Subnet: String
    let mode: String

    var isRunning: Bool {
        state.lowercased() == "running"
    }
}
