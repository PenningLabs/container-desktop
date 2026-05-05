import Foundation

/// App-level representation of a container volume.
struct VolumeModel: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let driver: String
    let mountpoint: String
    let createdAt: Date?
    let size: UInt64?

    var displaySize: String {
        guard let size = size else { return "—" }
        return Formatters.bytes(size)
    }

    /// Size for sorting — 0 if nil so unknown sizes sort last.
    var sizeForSort: UInt64 {
        size ?? 0
    }
}

/// Abstraction over volume management operations.
protocol VolumeServiceProtocol: Sendable {
    func listVolumes() async throws -> [VolumeModel]
    func createVolume(name: String, size: String?) async throws -> VolumeModel
    func removeVolume(name: String, force: Bool) async throws
    func pruneVolumes() async throws -> Int
}
