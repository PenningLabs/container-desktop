import Foundation
import SwiftUI

/// View model for the container list view.
/// Manages container listing, filtering, selection, and lifecycle actions.
@Observable
final class ContainerListViewModel {

    // MARK: - Dependencies

    private let containerService: any ContainerServiceProtocol
    private var refreshTask: Task<Void, Never>?

    // MARK: - State

    var containers: [ContainerModel] = []
    var selectedContainerID: String?
    var filterText: String = ""
    var isLoading: Bool = false
    var error: AppError?
    var showCreateSheet: Bool = false
    var showDeleteConfirmation: Bool = false
    var containerToDelete: ContainerModel?

    // Auto-refresh interval (seconds) — reads from user's Settings preference
    var autoRefreshInterval: TimeInterval {
        let stored = UserDefaults.standard.double(forKey: "autoRefreshInterval")
        return stored > 0 ? stored : 5.0
    }

    /// Set to true during user-initiated operations (start, stop, delete, create)
    /// to prevent auto-refresh from overwriting the container list mid-operation.
    private var isOperationInProgress: Bool = false

    // MARK: - Computed

    var filteredContainers: [ContainerModel] {
        let list: [ContainerModel]
        if filterText.isEmpty {
            list = containers
        } else {
            list = containers.filter {
                $0.name.localizedCaseInsensitiveContains(filterText) ||
                $0.image.localizedCaseInsensitiveContains(filterText) ||
                $0.status.rawValue.localizedCaseInsensitiveContains(filterText)
            }
        }
        // Running containers first, then by name
        return list.sorted { a, b in
            if a.status.isActive != b.status.isActive {
                return a.status.isActive
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }
    }

    var selectedContainer: ContainerModel? {
        containers.first { $0.id == selectedContainerID }
    }

    var runningCount: Int {
        containers.filter { $0.status == .running }.count
    }

    var stoppedCount: Int {
        containers.filter { $0.status == .stopped }.count
    }

    // MARK: - Init

    init(containerService: any ContainerServiceProtocol) {
        self.containerService = containerService
    }

    // MARK: - Actions

    func loadContainers() async {
        // Skip auto-refresh if a user operation is in progress
        guard !isOperationInProgress else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            containers = try await containerService.listContainers()
            error = nil
        } catch {
            self.error = .loadFailed(error)
        }
    }

    func startAutoRefresh() {
        stopAutoRefresh()
        refreshTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.loadContainers()
                try? await Task.sleep(for: .seconds(self?.autoRefreshInterval ?? 5.0))
            }
        }
    }

    func stopAutoRefresh() {
        refreshTask?.cancel()
        refreshTask = nil
    }

    func stopContainer(_ id: String) async {
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        do {
            try await containerService.stopContainer(id: id, timeout: .seconds(10))
            NotificationManager.shared.notifyContainerStopped(name: id)
            AppEventLog.shared.containerEvent(id, "Container stopped")
            await forceLoadContainers()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to stop container '\(id)'", source: id)
            self.error = .actionFailed("stop", error)
        }
    }

    func startContainer(_ id: String) async {
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        do {
            try await containerService.startContainer(id: id)
            NotificationManager.shared.notifyContainerStarted(name: id)
            AppEventLog.shared.containerEvent(id, "Container started")
            await forceLoadContainers()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to start container '\(id)'", source: id)
            self.error = .actionFailed("start", error)
        }
    }

    func removeContainer(_ id: String, force: Bool = false) async {
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        do {
            try await containerService.removeContainer(id: id, force: force)
            if selectedContainerID == id {
                selectedContainerID = nil
            }
            AppEventLog.shared.containerEvent(id, "Container removed")
            await forceLoadContainers()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to remove container '\(id)'", source: id)
            self.error = .actionFailed("remove", error)
        }
    }

    func createContainer(name: String, image: String, options: ContainerCreateOptions) async {
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        do {
            let container = try await containerService.createContainer(
                name: name, image: image, options: options
            )
            AppEventLog.shared.containerEvent(name, "Container created from \(image)")
            await forceLoadContainers()
            selectedContainerID = container.id
            showCreateSheet = false
        } catch {
            AppEventLog.shared.error(error, context: "Failed to create container '\(name)'", source: name)
            self.error = .actionFailed("create", error)
        }
    }

    /// Force-load containers, bypassing the operation guard.
    /// Used internally after a lifecycle operation completes.
    private func forceLoadContainers() async {
        isLoading = true
        defer { isLoading = false }
        do {
            containers = try await containerService.listContainers()
            error = nil
        } catch {
            self.error = .loadFailed(error)
        }
    }

    // Edit container
    var showEditSheet: Bool = false
    var containerToEdit: ContainerModel?

    func editContainer(_ container: ContainerModel) {
        containerToEdit = container
        showEditSheet = true
    }

    func confirmDelete(_ container: ContainerModel) {
        containerToDelete = container
        showDeleteConfirmation = true
    }

    func executeDelete() async {
        guard let container = containerToDelete else { return }
        let force = container.status.isActive
        await removeContainer(container.id, force: force)
        containerToDelete = nil
        showDeleteConfirmation = false
    }

    func killContainer(_ id: String) async {
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        do {
            try await containerService.killContainer(id: id)
            NotificationManager.shared.notifyContainerStopped(name: id)
            AppEventLog.shared.containerEvent(id, "Container killed (force)")
            await forceLoadContainers()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to kill container '\(id)'", source: id)
            self.error = .actionFailed("kill", error)
        }
    }

    /// Reclaim unused disk space inside a running container (`container clean`).
    func cleanContainer(_ id: String) async {
        isOperationInProgress = true
        defer { isOperationInProgress = false }
        do {
            let summary = try await containerService.cleanContainer(id: id)
            let detail = summary.isEmpty ? "Unused disk space reclaimed" : summary
            AppEventLog.shared.containerEvent(id, "Disk cleanup complete: \(detail)")
            NotificationManager.shared.send(title: "Cleaned \(id)", body: detail)
        } catch {
            AppEventLog.shared.error(error, context: "Failed to clean container '\(id)'", source: id)
            self.error = .actionFailed("clean", error)
        }
    }
}
