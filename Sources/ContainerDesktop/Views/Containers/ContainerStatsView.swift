import SwiftUI

/// View that shows resource usage stats for a container.
/// Uses `container stats --format json --no-stream` for structured data.
struct ContainerStatsView: View {
    let containerName: String
    @Environment(DependencyContainer.self) private var deps

    @State private var readings: [StatsReading] = []
    @State private var isLoading: Bool = true
    @State private var error: String?
    @State private var refreshTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            if isLoading && readings.isEmpty {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Fetching stats...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = error {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Retry") {
                        self.error = nil
                        startFetching()
                    }
                    .controlSize(.small)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                statsContent
            }
        }
        .onAppear { startFetching() }
        .onDisappear {
            refreshTask?.cancel()
            refreshTask = nil
        }
    }

    @ViewBuilder
    private var statsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let latest = readings.last {
                    // Summary gauges
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12) {
                        StatGaugeCard(
                            label: "CPU",
                            value: cpuPercent,
                            unit: "%",
                            color: .blue
                        )
                        StatGaugeCard(
                            label: "Memory",
                            value: memoryPercent(latest),
                            unit: "%",
                            color: .purple
                        )
                    }

                    // Detail rows — left-aligned
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Details")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        StatRow(label: "CPU usage", value: String(format: "%.1f%%", cpuPercent))
                        StatRow(label: "Memory usage", value: formatBytes(latest.memoryUsageBytes))
                        StatRow(label: "Memory limit", value: formatBytes(latest.memoryLimitBytes))
                        StatRow(label: "Network I/O", value: "\(formatBytes(latest.networkRxBytes)) / \(formatBytes(latest.networkTxBytes))")
                        StatRow(label: "Block I/O", value: "\(formatBytes(latest.blockReadBytes)) / \(formatBytes(latest.blockWriteBytes))")
                        StatRow(label: "PIDs", value: "\(latest.numProcesses)")
                    }
                }

                // Historical readings
                if readings.count > 1 {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("History (\(readings.count) readings)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)

                        ForEach(Array(readings.suffix(10).enumerated()), id: \.offset) { idx, reading in
                            HStack(spacing: 16) {
                                let cpu = cpuPercentForReading(at: readings.count - 10 + idx)
                                Text(String(format: "CPU %.1f%%", cpu))
                                    .font(.system(.caption2, design: .monospaced))
                                    .frame(width: 85, alignment: .leading)
                                Text("MEM \(formatBytes(reading.memoryUsageBytes))")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)
                                Text("NET \(formatBytes(reading.networkRxBytes)) rx")
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - CPU % computation

    /// CPU % is computed from the delta of cpuUsageUsec between consecutive readings
    /// divided by wall-clock time elapsed.
    private var cpuPercent: Double {
        guard readings.count >= 2 else {
            // Single reading — can't compute delta. Show 0.
            return 0
        }
        return cpuPercentForReading(at: readings.count - 1)
    }

    private func cpuPercentForReading(at index: Int) -> Double {
        guard index > 0, index < readings.count else { return 0 }
        let prev = readings[index - 1]
        let curr = readings[index]

        let cpuDelta = Double(curr.cpuUsageUsec - prev.cpuUsageUsec)
        let timeDelta = curr.timestamp.timeIntervalSince(prev.timestamp)
        guard timeDelta > 0 else { return 0 }

        // cpuUsageUsec is microseconds. Convert to seconds, divide by wall time.
        return (cpuDelta / 1_000_000.0) / timeDelta * 100.0
    }

    private func memoryPercent(_ reading: StatsReading) -> Double {
        guard reading.memoryLimitBytes > 0 else { return 0 }
        return Double(reading.memoryUsageBytes) / Double(reading.memoryLimitBytes) * 100.0
    }

    // MARK: - Byte formatting

    private func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .memory
        return formatter.string(fromByteCount: Int64(bytes))
    }

    // MARK: - Data fetching

    private func startFetching() {
        refreshTask?.cancel()
        refreshTask = Task {
            isLoading = true
            do {
                // First reading
                if let reading = try await fetchOneReading() {
                    await MainActor.run {
                        readings.append(reading)
                        isLoading = false
                    }
                } else {
                    await MainActor.run {
                        error = "No stats data returned. Stats requires a running container."
                        isLoading = false
                    }
                    return
                }

                // Auto-refresh every 3 seconds
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(3))
                    guard !Task.isCancelled else { break }
                    if let reading = try await fetchOneReading() {
                        await MainActor.run {
                            readings.append(reading)
                            // Keep last 60 readings (3 minutes at 3s interval)
                            if readings.count > 60 {
                                readings.removeFirst(readings.count - 60)
                            }
                        }
                    }
                }
            } catch is CancellationError {
                // Normal
            } catch {
                await MainActor.run {
                    self.error = "Could not fetch stats: \(error.localizedDescription)"
                    isLoading = false
                }
            }
        }
    }

    private func fetchOneReading() async throws -> StatsReading? {
        // Try JSON format first
        let result = try await deps.containerService.stats(containerID: containerName, json: true)

        if result.succeeded, let data = result.stdout.data(using: .utf8) {
            if let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
               let json = jsonArray.first {
                return StatsReading.fromJSON(json)
            }
            // Maybe it's a single object, not an array
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                return StatsReading.fromJSON(json)
            }
        }

        // Fallback: try table format
        let result2 = try await deps.containerService.stats(containerID: containerName, json: false)
        if result2.succeeded {
            return StatsReading.fromTableOutput(result2.stdout)
        }

        return nil
    }
}

// MARK: - Stats reading model

struct StatsReading {
    let timestamp: Date
    let id: String
    let memoryUsageBytes: UInt64
    let memoryLimitBytes: UInt64
    let cpuUsageUsec: UInt64
    let networkRxBytes: UInt64
    let networkTxBytes: UInt64
    let blockReadBytes: UInt64
    let blockWriteBytes: UInt64
    let numProcesses: Int

    /// Parse from JSON format:
    /// { "id": "...", "memoryUsageBytes": 47431680, "memoryLimitBytes": 1073741824,
    ///   "cpuUsageUsec": 1234567, "networkRxBytes": ..., "networkTxBytes": ...,
    ///   "blockReadBytes": ..., "blockWriteBytes": ..., "numProcesses": 3 }
    static func fromJSON(_ json: [String: Any]) -> StatsReading? {
        return StatsReading(
            timestamp: Date(),
            id: json["id"] as? String ?? "",
            memoryUsageBytes: jsonUInt64(json, "memoryUsageBytes"),
            memoryLimitBytes: jsonUInt64(json, "memoryLimitBytes"),
            cpuUsageUsec: jsonUInt64(json, "cpuUsageUsec"),
            networkRxBytes: jsonUInt64(json, "networkRxBytes"),
            networkTxBytes: jsonUInt64(json, "networkTxBytes"),
            blockReadBytes: jsonUInt64(json, "blockReadBytes"),
            blockWriteBytes: jsonUInt64(json, "blockWriteBytes"),
            numProcesses: json["numProcesses"] as? Int
                ?? (json["numProcesses"] as? UInt64).map { Int($0) }
                ?? 0
        )
    }

    /// Parse from table output as a fallback.
    /// Format: Container ID  Cpu %  Memory Usage  Net Rx/Tx  Block I/O  Pids
    static func fromTableOutput(_ output: String) -> StatsReading? {
        let lines = output.components(separatedBy: .newlines)
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }

        // Find data line (skip header)
        guard let dataLine = lines.last(where: { !$0.lowercased().hasPrefix("container") }) else {
            return nil
        }

        let parts = dataLine.split(whereSeparator: { $0.isWhitespace }).map(String.init)

        var memUsage: UInt64 = 0
        var memLimit: UInt64 = 0
        var netRx: UInt64 = 0
        var netTx: UInt64 = 0
        var blockRead: UInt64 = 0
        var blockWrite: UInt64 = 0
        var pids: Int = 0
        var slashCount = 0

        for (i, part) in parts.enumerated() {
            // Parse "X / Y" patterns — Memory Usage, Net Rx/Tx, Block I/O
            if part == "/" && i > 0 && i + 1 < parts.count {
                let left = parseByteValue(parts[i - 1])
                let right = parseByteValue(parts[i + 1])
                switch slashCount {
                case 0: memUsage = left; memLimit = right
                case 1: netRx = left; netTx = right
                case 2: blockRead = left; blockWrite = right
                default: break
                }
                slashCount += 1
            }
        }

        // Last part is PIDs
        if let lastPart = parts.last, let p = Int(lastPart) {
            pids = p
        }

        return StatsReading(
            timestamp: Date(),
            id: parts.first ?? "",
            memoryUsageBytes: memUsage,
            memoryLimitBytes: memLimit,
            cpuUsageUsec: 0,  // Can't get raw usec from table format
            networkRxBytes: netRx,
            networkTxBytes: netTx,
            blockReadBytes: blockRead,
            blockWriteBytes: blockWrite,
            numProcesses: pids
        )
    }

    // MARK: - Helpers

    private static func jsonUInt64(_ json: [String: Any], _ key: String) -> UInt64 {
        if let v = json[key] as? UInt64 { return v }
        if let v = json[key] as? Int { return UInt64(max(0, v)) }
        if let v = json[key] as? Double { return UInt64(max(0, v)) }
        return 0
    }

    private static func parseByteValue(_ str: String) -> UInt64 {
        let trimmed = str.trimmingCharacters(in: .whitespaces)
        let number: Double
        let multiplier: UInt64

        if trimmed.hasSuffix("GiB") || trimmed.hasSuffix("GB") {
            number = Double(trimmed.replacingOccurrences(of: "GiB", with: "")
                .replacingOccurrences(of: "GB", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            multiplier = 1024 * 1024 * 1024
        } else if trimmed.hasSuffix("MiB") || trimmed.hasSuffix("MB") {
            number = Double(trimmed.replacingOccurrences(of: "MiB", with: "")
                .replacingOccurrences(of: "MB", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            multiplier = 1024 * 1024
        } else if trimmed.hasSuffix("KiB") || trimmed.hasSuffix("KB") {
            number = Double(trimmed.replacingOccurrences(of: "KiB", with: "")
                .replacingOccurrences(of: "KB", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            multiplier = 1024
        } else if trimmed.hasSuffix("B") {
            number = Double(trimmed.replacingOccurrences(of: "B", with: "").trimmingCharacters(in: .whitespaces)) ?? 0
            multiplier = 1
        } else {
            number = Double(trimmed) ?? 0
            multiplier = 1
        }

        return UInt64(number * Double(multiplier))
    }
}

// MARK: - Stat gauge card

struct StatGaugeCard: View {
    let label: String
    let value: Double
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle()
                    .stroke(color.opacity(0.15), lineWidth: 6)
                Circle()
                    .trim(from: 0, to: min(value / 100.0, 1.0))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .rotationEffect(.degrees(-90))

                Text("\(Int(value))\(unit)")
                    .font(.system(.callout, design: .monospaced))
                    .fontWeight(.medium)
            }
            .frame(width: 64, height: 64)

            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(12)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Stat row (left-aligned)

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
            Spacer()
        }
    }
}
