import Foundation

/// System service implementation that shells out to the `container` CLI.
final class CLISystemService: SystemServiceProtocol, Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    // MARK: - Status

    func status() async throws -> SystemStatus {
        // The `container system info` command doesn't exist.
        // Instead, we check if the system is running by attempting
        // to list containers. If that succeeds, the system is up.
        do {
            let output = try await cli.runOrThrow(["ls", "--format", "json", "--all"])

            // Parse container count from the JSON
            var containerCount = 0
            var runningCount = 0
            if let data = output.data(using: .utf8),
               let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                containerCount = jsonArray.count
                runningCount = jsonArray.filter { ($0["status"] as? String) == "running" }.count
            }

            // Get image count (best effort)
            var imageCount = 0
            if let imageOutput = try? await cli.runOrThrow(["image", "list", "--format", "json"]),
               let imageData = imageOutput.data(using: .utf8),
               let imageArray = try? JSONSerialization.jsonObject(with: imageData) as? [[String: Any]] {
                imageCount = imageArray.count
            }

            // Get version
            let version = try? await cli.runOrThrow(["--version"])

            return SystemStatus(
                isRunning: true,
                version: version?.trimmingCharacters(in: .whitespacesAndNewlines),
                containerCount: containerCount,
                runningCount: runningCount,
                imageCount: imageCount,
                kernelVersion: nil,
                uptime: nil
            )
        } catch {
            return .offline
        }
    }

    func info() async throws -> SystemStatus {
        return try await status()
    }

    // MARK: - Start / Stop

    func startSystem() async throws {
        _ = try await cli.runOrThrow(["system", "start"], timeout: .seconds(30))
    }

    func stopSystem() async throws {
        _ = try await cli.runOrThrow(["system", "stop"], timeout: .seconds(30))
    }

    // MARK: - System logs

    func systemLogs(follow: Bool) -> AsyncThrowingStream<LogEntry, Error> {
        var args = ["system", "logs"]
        if follow {
            args.append("--follow")
        }

        let lineStream = cli.stream(args)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in lineStream {
                        let entry = LogEntry(
                            timestamp: Date(),
                            source: .system,
                            message: line
                        )
                        continuation.yield(entry)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Disk usage

    /// Get disk usage breakdown via `container system df`.
    /// Tries JSON format first, falls back to table parsing.
    func diskUsage() async throws -> DiskUsage {
        // Try JSON format first — gives us exact byte counts
        let jsonResult = try await cli.run(["system", "df", "--format", "json"])
        if jsonResult.succeeded, let data = jsonResult.stdout.data(using: .utf8) {
            if let parsed = parseDiskUsageJSON(data) {
                return parsed
            }
        }

        // Fallback: table format
        let tableResult = try await cli.run(["system", "df"])
        if tableResult.succeeded {
            return parseDiskUsageTable(tableResult.stdout)
        }

        throw AppError.parseError("Failed to parse system df output")
    }

    private func parseDiskUsageJSON(_ data: Data) -> DiskUsage? {
        // The JSON could be either:
        // 1. An array of objects: [{"type":"Images","total":5,"active":2,"size":123456,"reclaimable":789}]
        // 2. An object with category keys: {"images":{"total":5,...},"containers":{...}}
        // Try both approaches.

        if let array = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            return parseDiskUsageJSONArray(array)
        }
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            // Could be a single-level dict with category keys, or a wrapper
            if let array = dict.values.first as? [[String: Any]] {
                return parseDiskUsageJSONArray(array)
            }
            return parseDiskUsageJSONDict(dict)
        }
        return nil
    }

    private func parseDiskUsageJSONArray(_ array: [[String: Any]]) -> DiskUsage {
        var containers = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        var images = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        var volumes = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        var builder = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)

        for item in array {
            let typeName = (item["type"] as? String ?? item["Type"] as? String ?? "").lowercased()
            let cat = parseCategoryFromDict(item)

            if typeName.contains("image") { images = cat }
            else if typeName.contains("container") { containers = cat }
            else if typeName.contains("volume") { volumes = cat }
            else if typeName.contains("build") { builder = cat }
        }

        let total = containers.size + images.size + volumes.size + builder.size
        return DiskUsage(containers: containers, images: images, volumes: volumes, builder: builder, total: total)
    }

    private func parseDiskUsageJSONDict(_ dict: [String: Any]) -> DiskUsage {
        func find(_ keys: [String]) -> DiskUsage.DiskUsageCategory {
            for key in keys {
                // Try exact match and case-insensitive
                for (k, v) in dict {
                    if k.lowercased() == key.lowercased(), let cat = v as? [String: Any] {
                        return parseCategoryFromDict(cat)
                    }
                }
            }
            return DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        }

        let images = find(["images", "Images"])
        let containers = find(["containers", "Containers"])
        let volumes = find(["volumes", "Volumes", "localVolumes", "LocalVolumes"])
        let builder = find(["builder", "Builder", "buildCache", "BuildCache"])
        let total = containers.size + images.size + volumes.size + builder.size
        return DiskUsage(containers: containers, images: images, volumes: volumes, builder: builder, total: total)
    }

    private func parseCategoryFromDict(_ dict: [String: Any]) -> DiskUsage.DiskUsageCategory {
        // Actual keys from Apple CLI: "total", "active", "sizeInBytes", "reclaimable"
        let count = anyInt(dict, ["total", "Total", "count", "Count", "totalCount", "TotalCount"]) ?? 0
        let size = anyUInt64(dict, ["sizeInBytes", "size", "Size", "totalSize", "TotalSize"]) ?? 0
        let reclaimable = anyUInt64(dict, ["reclaimable", "Reclaimable", "reclaimableSize", "ReclaimableSize"]) ?? 0
        return DiskUsage.DiskUsageCategory(count: count, size: size, reclaimable: reclaimable)
    }

    private func anyInt(_ dict: [String: Any], _ keys: [String]) -> Int? {
        for key in keys {
            if let v = dict[key] as? Int { return v }
            if let v = dict[key] as? Double { return Int(v) }
        }
        return nil
    }

    private func anyUInt64(_ dict: [String: Any], _ keys: [String]) -> UInt64? {
        for key in keys {
            if let v = dict[key] as? UInt64 { return v }
            if let v = dict[key] as? Int { return UInt64(max(0, v)) }
            if let v = dict[key] as? Int64 { return UInt64(max(0, v)) }
            if let v = dict[key] as? Double { return UInt64(max(0, v)) }
            // Handle string sizes like "15.2GB"
            if let v = dict[key] as? String { return parseSizeString(v) }
        }
        return nil
    }

    private func parseDiskUsageTable(_ output: String) -> DiskUsage {
        // Parse table format:
        // TYPE            TOTAL   ACTIVE  SIZE        RECLAIMABLE
        // Images          5       2       1.2 GiB     800 MiB
        // Containers      3       1       500 MiB     200 MiB
        // Volumes         2       1       100 MiB     50 MiB
        // Builder                         2.0 GiB     2.0 GiB
        var containers = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        var images = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        var volumes = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)
        var builder = DiskUsage.DiskUsageCategory(count: 0, size: 0, reclaimable: 0)

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let lower = trimmed.lowercased()
            if lower.hasPrefix("images") { images = parseTableLine(trimmed) }
            else if lower.hasPrefix("containers") { containers = parseTableLine(trimmed) }
            else if lower.hasPrefix("volumes") || lower.hasPrefix("local volumes") { volumes = parseTableLine(trimmed) }
            else if lower.hasPrefix("build") { builder = parseTableLine(trimmed) }
        }

        let total = containers.size + images.size + volumes.size + builder.size
        return DiskUsage(containers: containers, images: images, volumes: volumes, builder: builder, total: total)
    }

    private func parseTableLine(_ line: String) -> DiskUsage.DiskUsageCategory {
        // Extract all number+unit groups and standalone numbers from the line.
        // Example: "Images          10      5       15.2GB      8.1GB (49%)"
        // Tokens:  ["Images", "10", "5", "15.2GB", "8.1GB", "(49%)"]
        let tokens = line.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var numbers: [Int] = []      // standalone integers (count, active)
        var sizes: [UInt64] = []     // parsed sizes (bytes)

        for token in tokens.dropFirst() {  // skip the category name
            let cleaned = token.replacingOccurrences(of: "(", with: "").replacingOccurrences(of: ")", with: "")
            if cleaned.hasSuffix("%") { continue }  // skip percentage
            if let size = parseSizeString(cleaned), size > 0 {
                sizes.append(size)
            } else if let n = Int(cleaned) {
                numbers.append(n)
            }
        }

        let count = numbers.first ?? 0
        let size = sizes.count > 0 ? sizes[0] : 0
        let reclaimable = sizes.count > 1 ? sizes[1] : 0

        return DiskUsage.DiskUsageCategory(count: count, size: size, reclaimable: reclaimable)
    }

    /// Parse a human-readable size string into bytes.
    /// Handles: "15.2GB", "1.2 GiB", "800MiB", "500MB", "2.0G", "100K", "0B"
    private func parseSizeString(_ str: String) -> UInt64? {
        let s = str.trimmingCharacters(in: .whitespaces).uppercased()
        if s == "0B" || s == "0" { return 0 }

        // Match number followed by optional unit
        let pattern = #"^([\d.]+)\s*(B|KB|KIB|K|MB|MIB|M|GB|GIB|G|TB|TIB|T|PB|PIB|P)?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let numRange = Range(match.range(at: 1), in: s),
              let number = Double(s[numRange]) else {
            return nil
        }

        let unit: String
        if match.range(at: 2).location != NSNotFound, let unitRange = Range(match.range(at: 2), in: s) {
            unit = String(s[unitRange])
        } else {
            return UInt64(number)  // no unit, assume bytes
        }

        let multiplier: Double
        switch unit {
        case "B":                     multiplier = 1
        case "K", "KB", "KIB":       multiplier = 1024
        case "M", "MB", "MIB":       multiplier = 1024 * 1024
        case "G", "GB", "GIB":       multiplier = 1024 * 1024 * 1024
        case "T", "TB", "TIB":       multiplier = 1024 * 1024 * 1024 * 1024
        case "P", "PB", "PIB":       multiplier = 1024 * 1024 * 1024 * 1024 * 1024
        default:                      multiplier = 1
        }

        return UInt64(number * multiplier)
    }
}

/// Builder service implementation that shells out to the `container` CLI.
/// Build operations are complex (XPC-backed) so CLI is the preferred
/// approach even if other services migrate to the framework API.
final class CLIBuilderService: BuilderServiceProtocol, Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    func status() async throws -> BuilderStatus {
        // Try to check builder status — fail gracefully if command doesn't exist
        do {
            let result = try await cli.run(["builder", "ls"])
            return BuilderStatus(
                isRunning: result.succeeded,
                memory: nil,
                cpus: nil
            )
        } catch {
            return BuilderStatus(isRunning: false, memory: nil, cpus: nil)
        }
    }

    func startBuilder(memory: UInt64?, cpus: Int?) async throws {
        var args = ["builder", "start"]
        if let memory = memory {
            args += ["--memory", "\(memory / (1024 * 1024 * 1024))g"]
        }
        if let cpus = cpus {
            args += ["--cpus", "\(cpus)"]
        }
        _ = try await cli.runOrThrow(args, timeout: .seconds(60))
    }

    func stopBuilder() async throws {
        _ = try await cli.runOrThrow(["builder", "stop"], timeout: .seconds(30))
    }

    func deleteBuilder() async throws {
        _ = try await cli.runOrThrow(["builder", "delete"])
    }

    func build(
        contextPath: String,
        tag: String,
        architectures: [Architecture],
        buildArgs: [String: String],
        dockerfile: String? = nil,
        target: String? = nil,
        noCache: Bool = false
    ) -> AsyncThrowingStream<LogEntry, Error> {
        var args = ["build"]

        // Show all build steps in plain text
        args += ["--progress", "plain"]

        // Custom Dockerfile path
        if let file = dockerfile, !file.isEmpty {
            args += ["--file", file]
        }

        // Multi-arch
        for arch in architectures {
            args += ["--arch", arch.rawValue]
        }

        // Tag
        args += ["--tag", tag]

        // Target stage (multi-stage builds)
        if let target = target, !target.isEmpty {
            args += ["--target", target]
        }

        // No cache
        if noCache {
            args.append("--no-cache")
        }

        // Build args
        for (key, value) in buildArgs {
            args += ["--build-arg", "\(key)=\(value)"]
        }

        // Context path (must be last)
        args.append(contextPath)

        let lineStream = cli.stream(args)

        return AsyncThrowingStream { continuation in
            Task {
                do {
                    for try await line in lineStream {
                        let entry = LogEntry(
                            timestamp: Date(),
                            source: .stdout,
                            message: line
                        )
                        continuation.yield(entry)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}
