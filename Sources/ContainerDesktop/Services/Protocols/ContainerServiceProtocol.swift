import Foundation

/// Abstraction over container lifecycle operations.
///
/// Two implementations exist:
/// - `CLIContainerService`: shells out to the `container` CLI binary
/// - `FrameworkContainerService`: uses `Containerization` Swift package directly (future migration)
///
/// The protocol boundary insulates the UI from API churn in the
/// Containerization framework (currently v0.1.0, source stability
/// only guaranteed within minor versions).
protocol ContainerServiceProtocol: Sendable {

    /// List all containers with their current status.
    func listContainers() async throws -> [ContainerModel]

    /// Create and optionally start a container from an image reference.
    func createContainer(
        name: String,
        image: String,
        options: ContainerCreateOptions
    ) async throws -> ContainerModel

    /// Stop a running container.
    func stopContainer(id: String, timeout: Duration) async throws

    /// Start a stopped container.
    func startContainer(id: String) async throws

    /// Remove a container. If `force` is true, stop it first.
    func removeContainer(id: String, force: Bool) async throws

    /// Stream logs from a container as an AsyncSequence.
    /// If `follow` is true, the stream stays open for new entries.
    /// If `includeBoot` is true, includes VM boot logs.
    func logs(
        containerID: String,
        follow: Bool,
        includeBoot: Bool
    ) -> AsyncThrowingStream<LogEntry, Error>

    /// Execute a process inside a running container.
    /// Returns a bidirectional channel for stdin/stdout/stderr.
    func exec(
        containerID: String,
        command: [String],
        tty: Bool
    ) async throws -> any ProcessChannel

    /// Inspect detailed container metadata.
    func inspect(containerID: String) async throws -> ContainerDetail

    /// Immediately kill a container (SIGKILL). No graceful shutdown.
    func killContainer(id: String) async throws
}

/// Extension with convenience defaults.
extension ContainerServiceProtocol {
    func stopContainer(id: String) async throws {
        try await stopContainer(id: id, timeout: .seconds(10))
    }

    func removeContainer(id: String) async throws {
        try await removeContainer(id: id, force: false)
    }

    func logs(containerID: String) -> AsyncThrowingStream<LogEntry, Error> {
        logs(containerID: containerID, follow: true, includeBoot: false)
    }
}
