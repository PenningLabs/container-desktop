import Foundation
import Testing
@testable import ContainerDesktop

// MARK: - Mock container service

/// Mock service for testing view models without hitting the CLI.
final class MockContainerService: ContainerServiceProtocol, @unchecked Sendable {

    var mockContainers: [ContainerModel] = []
    var createCallCount = 0
    var stopCallCount = 0
    var removeCallCount = 0
    var shouldThrow: AppError?

    func listContainers() async throws -> [ContainerModel] {
        if let error = shouldThrow { throw error }
        return mockContainers
    }

    func createContainer(name: String, image: String, options: ContainerCreateOptions) async throws -> ContainerModel {
        if let error = shouldThrow { throw error }
        createCallCount += 1
        let container = ContainerModel(
            id: name, name: name, image: image, status: .running,
            ipAddress: "192.168.64.\(mockContainers.count + 2)",
            dnsDomain: options.dnsDomain,
                networkName: "default",
            architecture: options.architecture,
            createdAt: Date(), pid: 1234,
            memory: options.memory, cpus: options.cpus
        )
        mockContainers.append(container)
        return container
    }

    func stopContainer(id: String, timeout: Duration) async throws {
        if let error = shouldThrow { throw error }
        stopCallCount += 1
        if let idx = mockContainers.firstIndex(where: { $0.id == id }) {
            let old = mockContainers[idx]
            mockContainers[idx] = ContainerModel(
                id: old.id, name: old.name, image: old.image, status: .stopped,
                ipAddress: nil, dnsDomain: old.dnsDomain,
                networkName: "default",
                architecture: old.architecture, createdAt: old.createdAt,
                pid: nil, memory: old.memory, cpus: old.cpus
            )
        }
    }

    func removeContainer(id: String, force: Bool) async throws {
        if let error = shouldThrow { throw error }
        removeCallCount += 1
        mockContainers.removeAll { $0.id == id }
    }

    func startContainer(id: String) async throws {
        if let error = shouldThrow { throw error }
        if let idx = mockContainers.firstIndex(where: { $0.id == id }) {
            let old = mockContainers[idx]
            mockContainers[idx] = ContainerModel(
                id: old.id, name: old.name, image: old.image, status: .running,
                ipAddress: "192.168.64.2", dnsDomain: old.dnsDomain,
                networkName: "default",
                architecture: old.architecture, createdAt: old.createdAt,
                pid: 1234, memory: old.memory, cpus: old.cpus
            )
        }
    }

    func logs(containerID: String, follow: Bool, includeBoot: Bool) -> AsyncThrowingStream<LogEntry, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(LogEntry(timestamp: Date(), source: .stdout, message: "test log line"))
            continuation.finish()
        }
    }

    func exec(containerID: String, command: [String], tty: Bool) async throws -> any ProcessChannel {
        throw AppError.unknown("Not implemented in mock")
    }

    func inspect(containerID: String) async throws -> ContainerDetail {
        guard let container = mockContainers.first(where: { $0.id == containerID }) else {
            throw AppError.unknown("Not found")
        }
        return ContainerDetail(
            model: container,
            config: ContainerConfig(
                entrypoint: ["/docker-entrypoint.sh"],
                cmd: ["nginx", "-g", "daemon off;"],
                workingDir: "/",
                user: "root",
                environment: [:],
                exposedPorts: ["80/tcp"],
                publishedPorts: [],
                publishedSockets: [],
                mounts: []
            ),
            state: ContainerState(
                status: container.status,
                startedAt: Date(),
                finishedAt: nil,
                exitCode: nil,
                error: nil
            )
        )
    }

    func killContainer(id: String) async throws {
        if let error = shouldThrow { throw error }
    }

    func copyToContainer(id: String, hostPath: String, containerPath: String) async throws {
        if let error = shouldThrow { throw error }
    }

    func copyFromContainer(id: String, containerPath: String, hostPath: String) async throws {
        if let error = shouldThrow { throw error }
    }
}

// MARK: - Mock image service

final class MockImageService: ImageServiceProtocol, @unchecked Sendable {

    var mockImages: [ImageModel] = []
    var shouldThrow: AppError?

    func listImages() async throws -> [ImageModel] {
        if let error = shouldThrow { throw error }
        return mockImages
    }

    func pullImage(reference: String, platform: PlatformSpec?) -> AsyncThrowingStream<PullProgress, Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(PullProgress(layer: "sha256:abc", status: .downloading, current: 50, total: 100))
            continuation.yield(PullProgress(layer: "sha256:abc", status: .complete, current: 100, total: 100))
            let parts = reference.split(separator: ":")
            let repo = String(parts.first ?? Substring(reference))
            let tag = parts.count > 1 ? String(parts[1]) : "latest"
            let image = ImageModel(
                id: "sha256:test", repository: repo, tag: tag,
                digest: "sha256:test123", size: 142_000_000,
                createdAt: Date(), architecture: .arm64, os: "linux", layerCount: 3
            )
            self.mockImages.append(image)
            continuation.finish()
        }
    }

    func pushImage(reference: String) async throws {
        if let error = shouldThrow { throw error }
    }

    func removeImage(id: String, force: Bool) async throws {
        if let error = shouldThrow { throw error }
        mockImages.removeAll { $0.id == id }
    }

    func inspect(imageID: String) async throws -> ImageDetail {
        throw AppError.unknown("Not implemented in mock")
    }

    func tagImage(source: String, target: String) async throws {
        if let error = shouldThrow { throw error }
    }

    func pruneImages(all: Bool) async throws -> Int {
        if let error = shouldThrow { throw error }
        return 0
    }

    func resolveArchitecture(reference: String) async -> Architecture {
        return .arm64
    }
}

// MARK: - Tests

@Suite("ContainerListViewModel")
struct ContainerListViewModelTests {

    @Test("Load containers populates list")
    func loadContainers() async throws {
        let mock = MockContainerService()
        mock.mockContainers = [
            ContainerModel(
                id: "web", name: "web-server", image: "nginx:latest",
                status: .running, ipAddress: "192.168.64.2", dnsDomain: "test",
                networkName: "default",
                architecture: .arm64, createdAt: Date(), pid: 100,
                memory: nil, cpus: nil
            ),
            ContainerModel(
                id: "db", name: "postgres-dev", image: "postgres:16",
                status: .stopped, ipAddress: nil, dnsDomain: nil,
                networkName: "default",
                architecture: .arm64, createdAt: Date(), pid: nil,
                memory: nil, cpus: nil
            ),
        ]

        let vm = ContainerListViewModel(containerService: mock)
        await vm.loadContainers()

        #expect(vm.containers.count == 2)
        #expect(vm.runningCount == 1)
        #expect(vm.stoppedCount == 1)
        #expect(vm.error == nil)
    }

    @Test("Filter containers by name")
    func filterContainers() async throws {
        let mock = MockContainerService()
        mock.mockContainers = [
            ContainerModel(
                id: "web", name: "web-server", image: "nginx:latest",
                status: .running, ipAddress: nil, dnsDomain: nil,
                networkName: "default",
                architecture: .arm64, createdAt: nil, pid: nil,
                memory: nil, cpus: nil
            ),
            ContainerModel(
                id: "db", name: "postgres-dev", image: "postgres:16",
                status: .stopped, ipAddress: nil, dnsDomain: nil,
                networkName: "default",
                architecture: .arm64, createdAt: nil, pid: nil,
                memory: nil, cpus: nil
            ),
        ]

        let vm = ContainerListViewModel(containerService: mock)
        await vm.loadContainers()

        vm.filterText = "web"
        #expect(vm.filteredContainers.count == 1)
        #expect(vm.filteredContainers.first?.name == "web-server")

        vm.filterText = "postgres"
        #expect(vm.filteredContainers.count == 1)

        vm.filterText = ""
        #expect(vm.filteredContainers.count == 2)
    }

    @Test("Stop container calls service and refreshes")
    func stopContainer() async throws {
        let mock = MockContainerService()
        mock.mockContainers = [
            ContainerModel(
                id: "web", name: "web-server", image: "nginx:latest",
                status: .running, ipAddress: "192.168.64.2", dnsDomain: nil,
                networkName: "default",
                architecture: .arm64, createdAt: nil, pid: 100,
                memory: nil, cpus: nil
            ),
        ]

        let vm = ContainerListViewModel(containerService: mock)
        await vm.loadContainers()
        await vm.stopContainer("web")

        #expect(mock.stopCallCount == 1)
        #expect(vm.containers.first?.status == .stopped)
    }

    @Test("Remove container clears selection")
    func removeContainer() async throws {
        let mock = MockContainerService()
        mock.mockContainers = [
            ContainerModel(
                id: "web", name: "web-server", image: "nginx:latest",
                status: .stopped, ipAddress: nil, dnsDomain: nil,
                networkName: "default",
                architecture: .arm64, createdAt: nil, pid: nil,
                memory: nil, cpus: nil
            ),
        ]

        let vm = ContainerListViewModel(containerService: mock)
        await vm.loadContainers()
        vm.selectedContainerID = "web"

        await vm.removeContainer("web")

        #expect(mock.removeCallCount == 1)
        #expect(vm.containers.isEmpty)
        #expect(vm.selectedContainerID == nil)
    }

    @Test("Load failure sets error state")
    func loadFailure() async throws {
        let mock = MockContainerService()
        mock.shouldThrow = .systemNotRunning

        let vm = ContainerListViewModel(containerService: mock)
        await vm.loadContainers()

        #expect(vm.containers.isEmpty)
        #expect(vm.error != nil)
    }
}

@Suite("CLI log line parsing")
struct CLILogParsingTests {

    @Test("Structured log line parsed")
    func structuredLog() {
        let line = "2026-03-25T14:02:31Z  nginx  | GET /index.html 200"
        let entry = CLIContainerService.parseLogLine(line)
        #expect(entry.source == .stdout)
        #expect(entry.message == "GET /index.html 200")
        #expect(entry.timestamp != nil)
    }

    @Test("Unstructured log line treated as stdout")
    func unstructuredLog() {
        let line = "Some random output"
        let entry = CLIContainerService.parseLogLine(line)
        #expect(entry.source == .stdout)
        #expect(entry.message == "Some random output")
    }
}
