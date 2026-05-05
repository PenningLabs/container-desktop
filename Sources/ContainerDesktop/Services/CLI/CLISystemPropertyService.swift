import Foundation

/// System property management service.
/// Uses `container system property` CLI commands.
final class CLISystemPropertyService: Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    /// List all system properties.
    func listProperties() async throws -> [SystemProperty] {
        // Prefer JSON format for reliable parsing
        let result = try await cli.run(["system", "property", "list", "--format", "json"])
        if result.succeeded, let data = result.stdout.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { parsePropertyJSON($0) }
        }

        // Fallback to table
        let output = try await cli.runOrThrow(["system", "property", "list"])
        return parsePropertyTable(output)
    }

    /// Get a single property value.
    func getProperty(_ id: String) async throws -> String {
        guard InputValidation.isSafePositionalArgument(id) else {
            throw AppError.unknown("Invalid property ID: '\(id)'")
        }
        let output = try await cli.runOrThrow(["system", "property", "get", id])
        return output.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Set a property value.
    func setProperty(_ id: String, value: String) async throws {
        guard InputValidation.isSafePositionalArgument(id) else {
            throw AppError.unknown("Invalid property ID: '\(id)'")
        }
        guard InputValidation.isSafePositionalArgument(value) else {
            throw AppError.unknown("Invalid property value: '\(value)'")
        }
        _ = try await cli.runOrThrow(["system", "property", "set", id, value])
        AppEventLog.shared.info("Set system property '\(id)' = '\(value)'", source: "System")
    }

    // MARK: - Parsing

    /// Parse a property from JSON format:
    /// {"id":"dns.domain","type":"String","value":"test","description":"..."}
    private func parsePropertyJSON(_ json: [String: Any]) -> SystemProperty? {
        guard let id = json["id"] as? String else { return nil }
        let type = json["type"] as? String ?? "String"
        // value can be null, a string, or a bool
        let value: String?
        if let str = json["value"] as? String {
            value = str
        } else if let bool = json["value"] as? Bool {
            value = bool ? "true" : "false"
        } else {
            value = nil  // JSON null
        }
        let description = json["description"] as? String ?? ""
        return SystemProperty(id: id, type: type, value: value, description: description)
    }

    private func parsePropertyTable(_ output: String) -> [SystemProperty] {
        let lines = output.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line in
            let parts = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true)
                .map { String($0).trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }

            let id = parts[0]
            let type = parts[1]
            let value: String
            let description: String
            if parts.count >= 4 {
                value = parts[2]
                description = parts[3]
            } else {
                value = parts[2]
                description = ""
            }

            return SystemProperty(
                id: id,
                type: type,
                value: value == "*undefined*" ? nil : value,
                description: description
            )
        }
    }
}

/// A system property.
struct SystemProperty: Identifiable, Sendable {
    var id: String
    let type: String
    let value: String?
    let description: String

    var displayValue: String {
        value ?? "(undefined)"
    }

    /// Known property IDs
    static let buildCpus = "build.cpus"
    static let buildMemory = "build.memory"
    static let buildRosetta = "build.rosetta"
    static let containerCpus = "container.cpus"
    static let containerMemory = "container.memory"
    static let dnsDomain = "dns.domain"
    static let imageBuilder = "image.builder"
    static let imageInit = "image.init"
    static let kernelBinaryPath = "kernel.binaryPath"
    static let kernelURL = "kernel.url"
    static let networkSubnet = "network.subnet"
    static let networkSubnetV6 = "network.subnetv6"
    static let registryDomain = "registry.domain"
}
