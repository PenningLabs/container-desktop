import Foundation

/// App-level representation of an OCI container image.
struct ImageModel: Identifiable, Hashable, Sendable {
    let id: String
    let repository: String
    let tag: String
    let digest: String
    let size: UInt64
    let createdAt: Date?
    var architecture: Architecture
    var os: String
    let layerCount: Int

    var reference: String {
        "\(repository):\(tag)"
    }

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

/// Detailed image metadata from inspect.
struct ImageDetail: Sendable {
    let model: ImageModel
    let layers: [ImageLayer]
    let config: ImageConfig
    let history: [ImageHistoryEntry]
}

struct ImageLayer: Identifiable, Sendable {
    let id: String
    let digest: String
    let size: UInt64
    let mediaType: String

    var displaySize: String {
        ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}

struct ImageConfig: Sendable {
    let entrypoint: [String]?
    let cmd: [String]?
    let workingDir: String?
    let user: String?
    let environment: [String: String]
    let exposedPorts: [String]
    let labels: [String: String]
}

struct ImageHistoryEntry: Identifiable, Sendable {
    let id: String
    let createdBy: String
    let createdAt: Date?
    let size: UInt64
    let emptyLayer: Bool
}

/// Platform specification for multi-arch operations.
struct PlatformSpec: Sendable {
    let os: String
    let architecture: Architecture

    static let linuxArm64 = PlatformSpec(os: "linux", architecture: .arm64)
    static let linuxAmd64 = PlatformSpec(os: "linux", architecture: .amd64)
}

/// Progress report during image pull operations.
struct PullProgress: Sendable {
    let layer: String
    let status: PullStatus
    let current: UInt64
    let total: UInt64

    var percent: Double {
        guard total > 0 else { return 0 }
        return Double(current) / Double(total) * 100.0
    }
}

enum PullStatus: String, Sendable {
    case downloading = "downloading"
    case extracting  = "extracting"
    case complete    = "complete"
    case waiting     = "waiting"
    case exists      = "exists"
}
