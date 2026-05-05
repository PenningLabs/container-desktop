import Foundation
import Observation
import SwiftUI

/// Central dependency container that creates and holds all services
/// and view models. Injected into the SwiftUI environment at the app root.
///
/// This is where you swap between CLI and Framework service implementations.
/// Currently uses CLI services exclusively. The protocol-based design allows
/// migration to Apple's Containerization framework APIs when they stabilize.
@Observable
final class DependencyContainer {

    // MARK: - Configuration

    let cliBinaryPath: String

    // MARK: - Sidebar badge data
    var networkCount: Int = 0

    // MARK: - Services

    let cliBridge: CLIBridge
    let containerService: CLIContainerService
    let imageService: CLIImageService
    let systemService: CLISystemService
    let builderService: CLIBuilderService
    let volumeService: CLIVolumeService
    let dnsService: CLIDNSService
    let networkService: CLINetworkService
    let registryService: CLIRegistryService
    let propertyService: CLISystemPropertyService

    // MARK: - View Models

    let containerListVM: ContainerListViewModel
    let imageBrowserVM: ImageBrowserViewModel
    let systemVM: SystemViewModel
    let logStreamVM: LogStreamViewModel
    let volumeVM: VolumeViewModel
    let dnsVM: DNSViewModel

    // MARK: - Init

    init(cliBinaryPath: String? = nil) {
        // Resolve CLI path
        let resolvedPath = cliBinaryPath
            ?? ContainerCLILocator.locate()
            ?? "/usr/local/bin/container"

        self.cliBinaryPath = resolvedPath
        self.cliBridge = CLIBridge(executablePath: resolvedPath)

        // All services use CLI implementation
        let containerSvc = CLIContainerService(cli: cliBridge)
        let imageSvc = CLIImageService(cli: cliBridge)
        let systemSvc = CLISystemService(cli: cliBridge)
        let builderSvc = CLIBuilderService(cli: cliBridge)
        let volumeSvc = CLIVolumeService(cli: cliBridge)
        let dnsSvc = CLIDNSService(cli: cliBridge, cliPath: resolvedPath)
        let networkSvc = CLINetworkService(cli: cliBridge)
        let registrySvc = CLIRegistryService(cli: cliBridge)
        let propertySvc = CLISystemPropertyService(cli: cliBridge)

        self.containerService = containerSvc
        self.imageService = imageSvc
        self.systemService = systemSvc
        self.builderService = builderSvc
        self.volumeService = volumeSvc
        self.dnsService = dnsSvc
        self.networkService = networkSvc
        self.registryService = registrySvc
        self.propertyService = propertySvc

        // Create view models
        self.containerListVM = ContainerListViewModel(containerService: containerSvc)
        self.imageBrowserVM = ImageBrowserViewModel(imageService: imageSvc, registryService: registrySvc)
        self.systemVM = SystemViewModel(systemService: systemSvc, builderService: builderSvc)
        self.logStreamVM = LogStreamViewModel(containerService: containerSvc)
        self.volumeVM = VolumeViewModel(volumeService: volumeSvc)
        self.dnsVM = DNSViewModel(dnsService: dnsSvc)
    }

    /// Refresh the network count for sidebar badge.
    func loadNetworkCount() async {
        networkCount = (try? await networkService.listNetworks())?.count ?? 0
    }

    /// Clean up resources on app termination.
    func cleanup() {
        // Stop log streaming and remove temp cache files
        logStreamVM.stopStreaming()
        logStreamVM.clearLogs()

        // Stop auto-refresh timers
        containerListVM.stopAutoRefresh()
        systemVM.stopPeriodicRefresh()

        // Clean up any stale temp files from previous sessions
        let tempDir = FileManager.default.temporaryDirectory
        if let files = try? FileManager.default.contentsOfDirectory(
            at: tempDir, includingPropertiesForKeys: nil
        ) {
            for file in files where file.lastPathComponent.hasPrefix("container-logs-") {
                try? FileManager.default.removeItem(at: file)
            }
        }
    }
}
