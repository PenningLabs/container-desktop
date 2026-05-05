import Foundation

/// Volume service implementation using the `container` CLI.
/// CLI: `container volume ls`, `container volume create`, `container volume rm`
final class CLIVolumeService: VolumeServiceProtocol, Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    func listVolumes() async throws -> [VolumeModel] {
        // Try JSON format first, fall back to plain text
        let result: CLIBridge.CommandResult
        do {
            result = try await cli.run(["volume", "ls", "--format", "json"])
        } catch {
            // Volume subcommand may not support --format json
            return try await listVolumesPlainText()
        }

        if !result.succeeded {
            // Fallback to plain text listing
            return try await listVolumesPlainText()
        }

        let output = result.stdout
        guard !output.isEmpty else { return [] }

        // Try JSON array
        if let data = output.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { parseVolumeJSON($0) }
        }

        // If JSON parsing fails, try plain text
        return parseVolumePlainText(output)
    }

    /// Fallback: list volumes without --format json
    private func listVolumesPlainText() async throws -> [VolumeModel] {
        let result = try await cli.run(["volume", "ls"])
        guard result.succeeded else { return [] }
        return parseVolumePlainText(result.stdout)
    }

    /// Parse plain text volume listing (lines of volume names)
    private func parseVolumePlainText(_ output: String) -> [VolumeModel] {
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.lowercased().starts(with: "name") && !$0.starts(with: "-") }
            .map { line in
                // Each line might be just a name, or "name  driver  mountpoint"
                let parts = line.split(whereSeparator: { $0.isWhitespace })
                let name = String(parts.first ?? Substring(line))
                return VolumeModel(
                    id: name, name: name, driver: "local",
                    mountpoint: "", createdAt: nil, size: nil
                )
            }
    }

    func createVolume(name: String, size: String? = nil) async throws -> VolumeModel {
        guard InputValidation.isValidVolumeName(name) else {
            throw AppError.unknown("Invalid volume name: '\(name)'")
        }
        var args = ["volume", "create"]
        if let size = size, !size.isEmpty {
            guard InputValidation.isValidVolumeSize(size) else {
                throw AppError.unknown("Invalid volume size: '\(size)'. Use digits with an optional K, M, G, T, or P suffix.")
            }
            args += ["-s", size]
        }
        args.append(name)
        _ = try await cli.runOrThrow(args)
        let volumes = try await listVolumes()
        return volumes.first { $0.name == name } ?? VolumeModel(
            id: name, name: name, driver: "local",
            mountpoint: "", createdAt: Date(), size: nil
        )
    }

    func removeVolume(name: String, force: Bool) async throws {
        guard InputValidation.isValidVolumeName(name) else {
            throw AppError.unknown("Invalid volume name: '\(name)'")
        }
        var args = ["volume", "rm"]
        if force { args.append("--force") }
        args.append(name)
        _ = try await cli.runOrThrow(args)
    }

    func pruneVolumes() async throws -> Int {
        let output = try await cli.runOrThrow(["volume", "prune", "--force"])
        let numbers = output.components(separatedBy: .whitespaces).compactMap { Int($0) }
        return numbers.first ?? 0
    }

    private func parseVolumeJSON(_ json: [String: Any]) -> VolumeModel? {
        // Actual format: {"name":"my-volume","driver":"local","source":"/path/volume.img",
        //   "format":"ext4","sizeInBytes":549755813888,"createdAt":796226740.028912,
        //   "options":{},"labels":{}}
        let name = json["name"] as? String
            ?? json["Name"] as? String
            ?? json["id"] as? String
        guard let name = name else { return nil }

        let source = json["source"] as? String
            ?? json["mountpoint"] as? String
            ?? json["Mountpoint"] as? String
            ?? ""

        var createdAt: Date? = nil
        if let ts = json["createdAt"] as? Double {
            createdAt = Date(timeIntervalSinceReferenceDate: ts)
        }

        let size = json["sizeInBytes"] as? UInt64
            ?? (json["sizeInBytes"] as? Int).map({ UInt64($0) })
            ?? json["size"] as? UInt64

        return VolumeModel(
            id: name,
            name: name,
            driver: json["driver"] as? String ?? json["Driver"] as? String ?? "local",
            mountpoint: source,
            createdAt: createdAt,
            size: size
        )
    }
}
