import Foundation

/// Abstraction over the container system service lifecycle.
/// The system service must be running before any container
/// operations can be performed.
protocol SystemServiceProtocol: Sendable {

    /// Get the current system status.
    func status() async throws -> SystemStatus

    /// Start the container system service.
    func startSystem() async throws

    /// Stop the container system service.
    func stopSystem() async throws

    /// Stream system logs.
    func systemLogs(follow: Bool) -> AsyncThrowingStream<LogEntry, Error>

    /// Get system info (version, resource usage, etc).
    func info() async throws -> SystemStatus
}

/// Abstraction over the container builder service.
/// The builder is used for `container build` (Dockerfile builds).
protocol BuilderServiceProtocol: Sendable {

    /// Get builder status.
    func status() async throws -> BuilderStatus

    /// Start the builder with given resource limits.
    func startBuilder(memory: UInt64?, cpus: Int?) async throws

    /// Stop the builder.
    func stopBuilder() async throws

    /// Delete the builder (removes cached layers).
    func deleteBuilder() async throws

    /// Build an image from a context directory.
    /// Returns a stream of build log output.
    func build(
        contextPath: String,
        tag: String,
        architectures: [Architecture],
        buildArgs: [String: String],
        dockerfile: String?,
        target: String?,
        noCache: Bool
    ) -> AsyncThrowingStream<LogEntry, Error>
}
