import Foundation

/// Abstraction over OCI image management operations.
protocol ImageServiceProtocol: Sendable {

    /// List all locally stored images.
    func listImages() async throws -> [ImageModel]

    /// Pull an image from a remote registry.
    /// Returns an async stream of progress updates.
    func pullImage(
        reference: String,
        platform: PlatformSpec?
    ) -> AsyncThrowingStream<PullProgress, Error>

    /// Remove a local image.
    func removeImage(id: String, force: Bool) async throws

    /// Inspect image layers and configuration.
    func inspect(imageID: String) async throws -> ImageDetail

    /// Remove unused/dangling images. With `all`, removes all unreferenced images.
    func pruneImages(all: Bool) async throws -> Int

    /// Resolve the architecture of an image from inspect data.
    func resolveArchitecture(reference: String) async -> Architecture
}

extension ImageServiceProtocol {
    func pullImage(reference: String) -> AsyncThrowingStream<PullProgress, Error> {
        pullImage(reference: reference, platform: nil)
    }

    func removeImage(id: String) async throws {
        try await removeImage(id: id, force: false)
    }
}
