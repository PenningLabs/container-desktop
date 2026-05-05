import Foundation

/// App-level representation of a container.
/// Decoupled from the Containerization framework types so the UI
/// never depends directly on framework internals.
struct ContainerModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let image: String
    let status: ContainerStatus
    let ipAddress: String?
    let dnsDomain: String?
    let networkName: String
    let architecture: Architecture
    let createdAt: Date?
    let pid: Int?
    let memory: UInt64?
    let cpus: Int?

    var displayAddress: String? {
        if let domain = dnsDomain, let ip = ipAddress {
            return "\(name).\(domain) (\(ip))"
        }
        return ipAddress
    }

    /// IP address for sorting — empty string if nil so it sorts last.
    var ipAddressForSort: String {
        ipAddress ?? ""
    }
}

enum ContainerStatus: String, Sendable, CaseIterable, Comparable {
    case running  = "running"
    case stopped  = "stopped"
    case creating = "creating"
    case stopping = "stopping"
    case unknown  = "unknown"

    var isActive: Bool {
        self == .running || self == .creating
    }

    var displayName: String {
        rawValue.capitalized
    }

    // Sort order: running first, then creating, stopping, stopped, unknown
    private var sortIndex: Int {
        switch self {
        case .running:  return 0
        case .creating: return 1
        case .stopping: return 2
        case .stopped:  return 3
        case .unknown:  return 4
        }
    }

    static func < (lhs: ContainerStatus, rhs: ContainerStatus) -> Bool {
        lhs.sortIndex < rhs.sortIndex
    }
}

enum Architecture: String, Sendable, CaseIterable, Comparable {
    case arm64 = "arm64"
    case amd64 = "amd64"
    case multi = "multi"
    case unknown = "unknown"

    var displayName: String {
        switch self {
        case .arm64: return "ARM64 (native)"
        case .amd64: return "AMD64 (Rosetta)"
        case .multi: return "Multi-arch"
        case .unknown: return "Unknown"
        }
    }

    static func < (lhs: Architecture, rhs: Architecture) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

/// Options for creating a new container.
struct ContainerCreateOptions: Sendable {
    var memory: UInt64?
    var cpus: Int?
    var architecture: Architecture = .arm64
    var dnsDomain: String?
    var environment: [String: String] = [:]
    var mounts: [MountSpec] = []
    var portMappings: [PortMapping] = []
    var socketMappings: [SocketMapping] = []
    var interactive: Bool = false
    var detached: Bool = true
    var command: [String]?

    // Advanced options
    var sshForwarding: Bool = false       // --ssh (mount host SSH agent)
    var initProcess: Bool = false          // --init (lightweight init as PID 1)
    var network: String?                   // --network (specific network name)
    var macAddress: String?                // --network default,mac=XX:XX:XX:XX:XX:XX
    var virtualization: Bool = false        // --virtualization (nested virt, M3+ only)

    // Process and runtime options
    var autoRemove: Bool = false           // --rm (remove container when it stops)
    var envFile: String?                   // --env-file <path> (load env vars from file)
    var workingDir: String?                // --workdir <dir> (working directory inside container)
    var entrypoint: String?                // --entrypoint <cmd> (override image entrypoint)
    var user: String?                      // --user <user> (run as user inside container)
    var hostname: String?                  // --hostname <name> (container hostname)

    static let `default` = ContainerCreateOptions()
}

/// Port forwarding rule: host port → container port.
/// Format for CLI: [host-ip:]host-port:container-port[/protocol]
struct PortMapping: Sendable, Hashable, Identifiable {
    let id = UUID()
    var hostIP: String       // e.g. "127.0.0.1" or "" for all interfaces
    var hostPort: Int
    var containerPort: Int
    var protocol_: PortProtocol

    /// Format for the --publish flag
    var cliFlag: String {
        var parts = ""
        if !hostIP.isEmpty {
            parts += "\(hostIP):"
        }
        parts += "\(hostPort):\(containerPort)"
        if protocol_ != .tcp {
            parts += "/\(protocol_.rawValue)"
        }
        return parts
    }

    /// Human-readable display
    var displayString: String {
        let host = hostIP.isEmpty ? "*" : hostIP
        return "\(host):\(hostPort) → \(containerPort)/\(protocol_.rawValue)"
    }

    init(hostIP: String = "", hostPort: Int = 0, containerPort: Int = 0, protocol_: PortProtocol = .tcp) {
        self.hostIP = hostIP
        self.hostPort = hostPort
        self.containerPort = containerPort
        self.protocol_ = protocol_
    }

    /// Parse from CLI flag format: [host-ip:]host-port:container-port[/protocol]
    static func parse(_ str: String) -> PortMapping? {
        var s = str.trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }

        // Extract protocol
        var proto: PortProtocol = .tcp
        if s.hasSuffix("/udp") {
            proto = .udp
            s = String(s.dropLast(4))
        } else if s.hasSuffix("/tcp") {
            s = String(s.dropLast(4))
        }

        let parts = s.split(separator: ":")
        switch parts.count {
        case 2:
            // hostPort:containerPort
            guard let hp = Int(parts[0]), let cp = Int(parts[1]) else { return nil }
            return PortMapping(hostPort: hp, containerPort: cp, protocol_: proto)
        case 3:
            // hostIP:hostPort:containerPort
            let ip = String(parts[0])
            guard let hp = Int(parts[1]), let cp = Int(parts[2]) else { return nil }
            return PortMapping(hostIP: ip, hostPort: hp, containerPort: cp, protocol_: proto)
        default:
            return nil
        }
    }
}

enum PortProtocol: String, Sendable, CaseIterable {
    case tcp = "tcp"
    case udp = "udp"
}

/// Unix socket forwarding: host path → container path.
/// Format for CLI: --publish-socket host-path:container-path
struct SocketMapping: Sendable, Hashable, Identifiable {
    let id = UUID()
    var hostPath: String
    var containerPath: String

    var cliFlag: String {
        "\(hostPath):\(containerPath)"
    }

    var displayString: String {
        "\(hostPath) → \(containerPath)"
    }
}

struct MountSpec: Sendable, Hashable {
    let source: String
    let destination: String
    let readOnly: Bool

    init(source: String, destination: String, readOnly: Bool = false) {
        self.source = source
        self.destination = destination
        self.readOnly = readOnly
    }
}

/// Detailed container metadata returned by inspect.
struct ContainerDetail: Sendable {
    let model: ContainerModel
    let config: ContainerConfig
    let state: ContainerState
}

struct ContainerConfig: Sendable {
    let entrypoint: [String]
    let cmd: [String]
    let workingDir: String
    let user: String
    let environment: [String: String]
    let exposedPorts: [String]
    let publishedPorts: [PortMapping]
    let publishedSockets: [SocketMapping]
    let mounts: [MountSpec]
}

struct ContainerState: Sendable {
    let status: ContainerStatus
    let startedAt: Date?
    let finishedAt: Date?
    let exitCode: Int?
    let error: String?
}

/// Resource usage stats for a running container.
struct ContainerStats: Sendable {
    let containerID: String
    let timestamp: Date
    let cpuPercent: Double
    let memoryUsageBytes: UInt64
    let memoryLimitBytes: UInt64
    let networkRxBytes: UInt64
    let networkTxBytes: UInt64
    let blockReadBytes: UInt64
    let blockWriteBytes: UInt64

    var memoryPercent: Double {
        guard memoryLimitBytes > 0 else { return 0 }
        return Double(memoryUsageBytes) / Double(memoryLimitBytes) * 100.0
    }
}
