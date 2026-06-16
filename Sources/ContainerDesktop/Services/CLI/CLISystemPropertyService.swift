import Foundation

/// System property management service.
/// Uses `container system property` CLI commands.
final class CLISystemPropertyService: Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    /// List all system properties.
    /// v1.0.0+: `container system property ls` outputs merged TOML config.
    /// Older versions: `container system property list --format json` outputs JSON.
    func listProperties() async throws -> [SystemProperty] {
        // Try JSON format first (older CLI versions)
        let jsonResult = try await cli.run(["system", "property", "list", "--format", "json"])
        if jsonResult.succeeded, let data = jsonResult.stdout.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { parsePropertyJSON($0) }
        }

        // v1.0.0+: `container system property ls` outputs TOML
        let tomlResult = try await cli.run(["system", "property", "ls"])
        if tomlResult.succeeded {
            return parseTOMLProperties(tomlResult.stdout)
        }

        return []
    }

    /// Get a single property value.
    /// v1.0.0+: `get` subcommand removed. Returns value from TOML listing if found.
    func getProperty(_ id: String) async throws -> String {
        guard InputValidation.isSafePositionalArgument(id) else {
            throw AppError.unknown("Invalid property ID: '\(id)'")
        }
        // Try old get command first
        let result = try await cli.run(["system", "property", "get", id])
        if result.succeeded {
            return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // v1.0.0: look up from TOML listing
        let props = try await listProperties()
        if let prop = props.first(where: { $0.id == id }) {
            return prop.value ?? ""
        }
        throw AppError.unknown("Property '\(id)' not found")
    }

    /// Set a property value.
    /// v1.0.0+: `set` subcommand removed. Users must edit ~/.config/container/config.toml.
    func setProperty(_ id: String, value: String) async throws {
        guard InputValidation.isSafePositionalArgument(id) else {
            throw AppError.unknown("Invalid property ID: '\(id)'")
        }
        guard InputValidation.isSafePositionalArgument(value) else {
            throw AppError.unknown("Invalid property value: '\(value)'")
        }
        // Try old set command first
        let result = try await cli.run(["system", "property", "set", id, value])
        if result.succeeded {
            AppEventLog.shared.info("Set system property '\(id)' = '\(value)'", source: "System")
            return
        }
        throw AppError.unknown("In container v1.0.0+, edit ~/.config/container/config.toml to change settings, then restart the system with 'container system stop && container system start'.")
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

    /// Parse TOML output from `container system property ls` (v1.0.0+).
    /// Example:
    ///   [container]
    ///   cpus = 4
    ///   memory = "1gb"
    ///   [dns]
    ///   domain = "test"
    /// Produces: [SystemProperty(id: "container.cpus", value: "4"), ...]
    private func parseTOMLProperties(_ output: String) -> [SystemProperty] {
        var properties: [SystemProperty] = []
        var currentSection = ""

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }

            // Section header: [build], [container], [dns], etc.
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
                currentSection = String(trimmed.dropFirst().dropLast())
                continue
            }

            // Key = value
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            var value = parts[1].trimmingCharacters(in: .whitespaces)

            // Strip quotes from string values
            if value.hasPrefix("\"") && value.hasSuffix("\"") {
                value = String(value.dropFirst().dropLast())
            }

            let id = currentSection.isEmpty ? key : "\(currentSection).\(key)"

            // Infer type from value
            let type: String
            if value == "true" || value == "false" {
                type = "Bool"
            } else if Int(value) != nil {
                type = "Int"
            } else {
                type = "String"
            }

            properties.append(SystemProperty(id: id, type: type, value: value, description: ""))
        }

        return properties
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
