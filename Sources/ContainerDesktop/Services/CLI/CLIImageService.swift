import Foundation

/// Image service implementation that shells out to the `container` CLI.
///
/// CLI command reference:
///   container image list --format json
///   container image pull <reference>
///   container image push <reference>
///   container image rm <id>
///   container image inspect <id>
///   container image tag <source> <target>
final class CLIImageService: ImageServiceProtocol, Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    // MARK: - List

    func listImages() async throws -> [ImageModel] {
        let output = try await cli.runOrThrow(["image", "list", "--format", "json"])
        guard !output.isEmpty else { return [] }
        return try parseImageList(output)
    }

    private func parseImageList(_ output: String) throws -> [ImageModel] {
        if let data = output.data(using: .utf8),
           let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return jsonArray.compactMap { parseImageJSON($0) }
        }

        // NDJSON fallback
        return output
            .components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .compactMap { line -> ImageModel? in
                guard let data = line.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
                else { return nil }
                return parseImageJSON(json)
            }
    }

    /// Parse the v1.0.0 CLI JSON format:
    /// {
    ///   "configuration": {
    ///     "name": "docker.io/library/nginx:latest",
    ///     "descriptor": { "digest": "sha256:...", "mediaType": "...", "size": 10229 },
    ///     "creationDate": "2026-03-24T22:12:00Z"
    ///   },
    ///   "id": "7150b3a...",
    ///   "variants": [
    ///     { "platform": { "architecture": "arm64", "os": "linux" }, "size": 61295296, ... }
    ///   ]
    /// }
    private func parseImageJSON(_ json: [String: Any]) -> ImageModel? {
        let config = json["configuration"] as? [String: Any] ?? [:]

        // v1.0.0: reference is in configuration.name; fallback for older CLI
        let reference = config["name"] as? String
            ?? json["reference"] as? String
            ?? "unknown"
        let descriptor = config["descriptor"] as? [String: Any]
            ?? json["descriptor"] as? [String: Any]
            ?? [:]

        let digest = descriptor["digest"] as? String ?? ""

        // Parse reference into repository and tag
        let (repository, tag) = Self.parseReference(reference)

        // Size: v1.0.0 has per-variant sizes. Use the largest real variant.
        let variants = json["variants"] as? [[String: Any]] ?? []
        var size: UInt64 = 0

        if !variants.isEmpty {
            let realVariants = variants.filter { variant in
                let platform = variant["platform"] as? [String: Any] ?? [:]
                let arch = platform["architecture"] as? String ?? "unknown"
                return arch != "unknown"
            }
            size = realVariants.compactMap { variant -> UInt64? in
                variant["size"] as? UInt64 ?? (variant["size"] as? Int).map({ UInt64($0) })
            }.max() ?? 0
        }

        if size == 0 {
            // Fallback for older CLI
            let fullSizeStr = json["fullSize"] as? String
            if let fullSizeStr = fullSizeStr {
                size = Self.parseSizeString(fullSizeStr)
            } else {
                size = descriptor["size"] as? UInt64
                    ?? (descriptor["size"] as? Int).map({ UInt64($0) })
                    ?? 0
            }
        }

        // Architecture: resolve from variants directly (no separate inspect needed)
        var architecture: Architecture = .unknown
        if !variants.isEmpty {
            let realArchitectures = Set(variants.compactMap { variant -> String? in
                let platform = variant["platform"] as? [String: Any] ?? [:]
                let arch = platform["architecture"] as? String ?? "unknown"
                return arch == "unknown" ? nil : arch
            })
            if realArchitectures.count > 1 {
                architecture = .multi
            } else if let first = realArchitectures.first {
                architecture = Architecture(rawValue: first) ?? .unknown
            }
        }

        return ImageModel(
            id: digest.isEmpty ? reference : digest,
            repository: repository,
            tag: tag,
            digest: digest,
            size: size,
            createdAt: nil,
            architecture: architecture,
            os: "linux",
            layerCount: 0
        )
    }

    /// Parse an OCI reference into (repository, tag).
    /// "docker.io/library/nginx:latest" → ("nginx", "latest")
    /// "ghcr.io/user/app:v1.2" → ("ghcr.io/user/app", "v1.2")
    /// "alpine" → ("alpine", "latest")
    static func parseReference(_ ref: String) -> (String, String) {
        // Split off tag
        let parts = ref.split(separator: ":", maxSplits: 1)
        let withoutTag: String
        let tag: String
        if parts.count == 2, !parts[1].contains("/") {
            withoutTag = String(parts[0])
            tag = String(parts[1])
        } else {
            withoutTag = ref
            tag = "latest"
        }

        // Strip docker.io/library/ prefix for cleaner display
        var repo = withoutTag
        if repo.hasPrefix("docker.io/library/") {
            repo = String(repo.dropFirst("docker.io/library/".count))
        } else if repo.hasPrefix("docker.io/") {
            repo = String(repo.dropFirst("docker.io/".count))
        }

        return (repo, tag)
    }

    static func parseSizeString(_ str: String) -> UInt64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces).uppercased()
        let multipliers: [(String, UInt64)] = [
            ("GB", 1_073_741_824),
            ("MB", 1_048_576),
            ("KB", 1_024),
            ("B", 1),
        ]
        for (suffix, mult) in multipliers {
            if trimmed.hasSuffix(suffix) {
                let numStr = trimmed.dropLast(suffix.count).trimmingCharacters(in: .whitespaces)
                if let num = Double(numStr) {
                    return UInt64(num * Double(mult))
                }
            }
        }
        return UInt64(str) ?? 0
    }

    // MARK: - Pull

    func pullImage(
        reference: String,
        platform: PlatformSpec?
    ) -> AsyncThrowingStream<PullProgress, Error> {
        // Validate the reference before streaming — reject dash-prefix to prevent argument injection
        guard InputValidation.isValidImageReference(reference) else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: AppError.unknown("Invalid image reference: '\(reference)'"))
            }
        }

        var args = ["image", "pull"]
        if let platform = platform {
            args += ["--arch", platform.architecture.rawValue]
        }
        args.append(reference)

        let lineStream = cli.stream(args)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in lineStream {
                        if let progress = Self.parsePullProgress(line) {
                            continuation.yield(progress)
                        }
                    }
                    continuation.yield(PullProgress(
                        layer: "all",
                        status: .complete,
                        current: 1,
                        total: 1
                    ))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    private static func parsePullProgress(_ line: String) -> PullProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }

        let lower = trimmed.lowercased()

        // Check for completion/exists patterns
        if lower.contains("already exists") || lower.contains("exists") {
            return PullProgress(layer: trimmed, status: .exists, current: 1, total: 1)
        }
        if lower.contains("pull complete") || lower.contains("complete") || lower.contains("done") {
            return PullProgress(layer: trimmed, status: .complete, current: 1, total: 1)
        }
        if lower.contains("extracting") {
            return PullProgress(layer: trimmed, status: .extracting, current: 0, total: 0)
        }
        if lower.contains("downloading") {
            return PullProgress(layer: trimmed, status: .downloading, current: 0, total: 0)
        }

        // Generic line — treat as downloading progress
        return PullProgress(layer: trimmed, status: .downloading, current: 0, total: 0)
    }

    // MARK: - Remove

    func removeImage(id: String, force: Bool) async throws {
        guard InputValidation.isSafePositionalArgument(id) else {
            throw AppError.unknown("Invalid image ID: '\(id)'")
        }
        var args = ["image", "rm"]
        if force { args.append("--force") }
        args.append(id)
        _ = try await cli.runOrThrow(args)
    }

    // MARK: - Inspect

    func inspect(imageID: String) async throws -> ImageDetail {
        guard InputValidation.isSafePositionalArgument(imageID) else {
            throw AppError.unknown("Invalid image ID: '\(imageID)'")
        }
        let output = try await cli.runOrThrow(["image", "inspect", imageID])

        guard let data = output.data(using: .utf8) else {
            throw AppError.parseError("Failed to parse image inspect output")
        }

        // inspect returns an array with one element
        let jsonArray: [[String: Any]]
        if let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            jsonArray = arr
        } else if let single = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            jsonArray = [single]
        } else {
            throw AppError.parseError("Failed to parse image inspect output")
        }

        guard let json = jsonArray.first else {
            throw AppError.parseError("Empty inspect result")
        }

        // Build base model from list-style fields
        var model = parseImageJSON(json) ?? ImageModel(
            id: imageID, repository: imageID, tag: "latest",
            digest: "", size: 0, createdAt: nil,
            architecture: .unknown, os: "linux", layerCount: 0
        )

        // Parse variants to get architecture, config, history, layers
        let variants = json["variants"] as? [[String: Any]] ?? []
        let (arch, os, config, history, layers) = Self.parseVariants(variants)
        model.architecture = arch
        model.os = os

        return ImageDetail(
            model: model,
            layers: layers,
            config: config,
            history: history
        )
    }

    /// Resolve just the architecture for an image without full inspect parsing.
    func resolveArchitecture(reference: String) async -> Architecture {
        guard InputValidation.isSafePositionalArgument(reference) else {
            return .unknown
        }
        do {
            let output = try await cli.runOrThrow(["image", "inspect", reference])
            guard let data = output.data(using: .utf8),
                  let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
                  let json = jsonArray.first else {
                return .unknown
            }

            let variants = json["variants"] as? [[String: Any]] ?? []
            // Find the best architecture from variants
            let realVariants = variants.compactMap { variant -> String? in
                let platform = variant["platform"] as? [String: Any] ?? [:]
                let arch = platform["architecture"] as? String ?? "unknown"
                return arch == "unknown" ? nil : arch
            }

            // De-duplicate — same architecture can appear in multiple variants
            // (e.g., arm64 and arm64/v8)
            let uniqueArches = Set(realVariants)

            if uniqueArches.count > 1 {
                return .multi
            } else if uniqueArches.count == 1, let first = uniqueArches.first {
                return Architecture(rawValue: first) ?? .unknown
            }
            return .unknown
        } catch {
            return .unknown
        }
    }

    /// Parse the variants array from image inspect.
    /// Returns (architecture, os, config, history, layers) from the best variant.
    private static func parseVariants(_ variants: [[String: Any]]) -> (Architecture, String, ImageConfig, [ImageHistoryEntry], [ImageLayer]) {
        // Find the best variant: prefer arm64, then amd64, then first non-unknown
        let ranked = variants.filter {
            let platform = $0["platform"] as? [String: Any] ?? [:]
            let arch = platform["architecture"] as? String ?? "unknown"
            return arch != "unknown"
        }

        let best: [String: Any]?
        if let arm64 = ranked.first(where: {
            ($0["platform"] as? [String: Any])?["architecture"] as? String == "arm64"
        }) {
            best = arm64
        } else if let amd64 = ranked.first(where: {
            ($0["platform"] as? [String: Any])?["architecture"] as? String == "amd64"
        }) {
            best = amd64
        } else {
            best = ranked.first
        }

        guard let variant = best else {
            return (.unknown, "linux", ImageConfig(entrypoint: nil, cmd: nil, workingDir: nil, user: nil, environment: [:], exposedPorts: [], labels: [:]), [], [])
        }

        let platform = variant["platform"] as? [String: Any] ?? [:]
        let archStr = platform["architecture"] as? String ?? "unknown"
        let arch = Architecture(rawValue: archStr) ?? .unknown
        let os = platform["os"] as? String ?? "linux"

        // Parse config from variant.config.config
        let variantConfig = variant["config"] as? [String: Any] ?? [:]
        let innerConfig = variantConfig["config"] as? [String: Any] ?? [:]

        let envArray = innerConfig["Env"] as? [String] ?? []
        var envDict: [String: String] = [:]
        for e in envArray {
            let parts = e.split(separator: "=", maxSplits: 1)
            if parts.count == 2 { envDict[String(parts[0])] = String(parts[1]) }
        }

        let config = ImageConfig(
            entrypoint: innerConfig["Entrypoint"] as? [String],
            cmd: innerConfig["Cmd"] as? [String],
            workingDir: innerConfig["WorkingDir"] as? String,
            user: innerConfig["User"] as? String,
            environment: envDict,
            exposedPorts: [],
            labels: innerConfig["Labels"] as? [String: String] ?? [:]
        )

        // Parse history
        let historyArray = variantConfig["history"] as? [[String: Any]] ?? []
        let history: [ImageHistoryEntry] = historyArray.enumerated().map { (i, h) in
            ImageHistoryEntry(
                id: "\(i)",
                createdBy: h["created_by"] as? String ?? "",
                createdAt: (h["created"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) },
                size: 0,
                emptyLayer: h["empty_layer"] as? Bool ?? false
            )
        }

        return (arch, os, config, history, [])
    }

    // MARK: - Prune

    /// Remove dangling images to reclaim disk space.
    /// With `all: true`, also removes images not referenced by any container.
    /// Returns the number of images removed.
    func pruneImages(all: Bool = false) async throws -> Int {
        var args = ["image", "prune", "--force"]
        if all { args.append("-a") }
        let output = try await cli.runOrThrow(args)
        // Try to parse count from output
        let lines = output.components(separatedBy: .newlines).filter { !$0.isEmpty }
        return lines.count
    }
}
