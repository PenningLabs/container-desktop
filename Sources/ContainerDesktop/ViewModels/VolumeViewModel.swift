import Foundation
import SwiftUI

@Observable
final class VolumeViewModel {

    private let volumeService: CLIVolumeService

    var volumes: [VolumeModel] = []
    var isLoading: Bool = false
    var error: AppError?
    var showCreateSheet: Bool = false
    var showPruneConfirmation: Bool = false

    init(volumeService: CLIVolumeService) {
        self.volumeService = volumeService
    }

    func loadVolumes() async {
        isLoading = true
        defer { isLoading = false }
        do {
            volumes = try await volumeService.listVolumes()
            error = nil
        } catch {
            self.error = .loadFailed(error)
        }
    }

    func createVolume(name: String, size: String? = nil) async {
        do {
            _ = try await volumeService.createVolume(name: name, size: size)
            await loadVolumes()
            showCreateSheet = false
        } catch {
            self.error = .actionFailed("create volume", error)
        }
    }

    func removeVolume(_ name: String, force: Bool = false) async {
        do {
            try await volumeService.removeVolume(name: name, force: force)
            await loadVolumes()
        } catch {
            self.error = .actionFailed("remove volume", error)
        }
    }

    func pruneVolumes() async {
        do {
            _ = try await volumeService.pruneVolumes()
            await loadVolumes()
            showPruneConfirmation = false
        } catch {
            self.error = .actionFailed("prune volumes", error)
        }
    }
}
