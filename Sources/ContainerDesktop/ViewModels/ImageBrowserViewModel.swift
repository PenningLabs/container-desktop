import Foundation
import SwiftUI

/// View model for the image browser view.
@Observable
final class ImageBrowserViewModel {

    private let imageService: any ImageServiceProtocol
    let registryService: CLIRegistryService
    private var pullTask: Task<Void, Never>?

    // MARK: - State

    var images: [ImageModel] = []
    var selectedImageID: String?
    var filterText: String = ""
    var isLoading: Bool = false
    var error: AppError?

    // Pull state
    var showPullSheet: Bool = false
    var pullReference: String = ""
    var pullPlatform: PlatformSpec? = nil
    var isPulling: Bool = false
    var pullProgressEntries: [PullProgress] = []
    var pullError: AppError?

    // Registry state
    var showRegistrySheet: Bool = false

    // Tag state
    var showTagSheet: Bool = false
    var tagSourceImage: ImageModel?

    // Push state
    var isPushing: Bool = false
    var pushReference: String = ""

    // Prune state
    var showPruneConfirmation: Bool = false
    var pruneAll: Bool = false

    // MARK: - Computed

    var filteredImages: [ImageModel] {
        let list: [ImageModel]
        if filterText.isEmpty {
            list = images
        } else {
            list = images.filter {
                $0.repository.localizedCaseInsensitiveContains(filterText) ||
                $0.tag.localizedCaseInsensitiveContains(filterText)
            }
        }
        return list.sorted { $0.repository.localizedCaseInsensitiveCompare($1.repository) == .orderedAscending }
    }

    var selectedImage: ImageModel? {
        images.first { $0.id == selectedImageID }
    }

    var totalImageSize: UInt64 {
        images.reduce(0) { $0 + $1.size }
    }

    // MARK: - Init

    init(imageService: any ImageServiceProtocol, registryService: CLIRegistryService) {
        self.imageService = imageService
        self.registryService = registryService
    }

    // MARK: - Actions

    func loadImages() async {
        isLoading = true
        defer { isLoading = false }
        do {
            images = try await imageService.listImages()
            error = nil
        } catch {
            self.error = .loadFailed(error)
        }

        // Resolve architectures concurrently in the background
        await resolveArchitectures()
    }

    /// Cache of resolved architectures keyed by image reference.
    /// Persists across refreshes so we don't re-inspect unchanged images.
    private var archCache: [String: Architecture] = [:]

    /// Resolve architecture for images that show as .unknown, using concurrent inspect calls.
    private func resolveArchitectures() async {
        // Apply cached values first
        for i in images.indices {
            if images[i].architecture == .unknown,
               let cached = archCache[images[i].reference] {
                images[i].architecture = cached
            }
        }

        // Collect references (not indices) that still need resolution.
        // Indices would race against concurrent list refreshes that replace `images`.
        let unresolvedRefs = images
            .filter { $0.architecture == .unknown }
            .map { $0.reference }
        guard !unresolvedRefs.isEmpty else { return }

        // Resolve concurrently (max 5 at a time to avoid hammering the CLI)
        await withTaskGroup(of: (String, Architecture).self) { group in
            var refIterator = unresolvedRefs.makeIterator()

            // Seed initial batch
            for _ in 0..<min(5, unresolvedRefs.count) {
                if let ref = refIterator.next() {
                    group.addTask {
                        let arch = await self.imageService.resolveArchitecture(reference: ref)
                        return (ref, arch)
                    }
                }
            }

            // Process results and add more tasks as slots free up.
            // Look up by reference at write time — the images array may have been
            // replaced by a concurrent refresh, so indices would be invalid.
            for await (ref, arch) in group {
                if arch != .unknown {
                    archCache[ref] = arch
                    if let idx = images.firstIndex(where: { $0.reference == ref }) {
                        images[idx].architecture = arch
                    }
                }
                if let nextRef = refIterator.next() {
                    group.addTask {
                        let arch = await self.imageService.resolveArchitecture(reference: nextRef)
                        return (nextRef, arch)
                    }
                }
            }
        }
    }

    func pullImage() async {
        let ref = pullReference.trimmingCharacters(in: .whitespaces)
        guard !ref.isEmpty else { return }

        isPulling = true
        pullProgressEntries = []
        pullError = nil

        pullTask = Task {
            do {
                for try await progress in imageService.pullImage(reference: ref, platform: pullPlatform) {
                    await MainActor.run {
                        if let idx = pullProgressEntries.firstIndex(where: { $0.layer == progress.layer }) {
                            pullProgressEntries[idx] = progress
                        } else {
                            pullProgressEntries.append(progress)
                        }
                    }
                }
                await MainActor.run {
                    isPulling = false
                    showPullSheet = false
                    pullReference = ""
                }
                NotificationManager.shared.notifyPullComplete(reference: ref)
                await loadImages()
            } catch {
                await MainActor.run {
                    isPulling = false
                    pullError = .actionFailed("pull", error)
                }
            }
        }
    }

    func cancelPull() {
        pullTask?.cancel()
        pullTask = nil
        isPulling = false
    }

    func removeImage(_ id: String, force: Bool = false) async {
        do {
            let ref: String
            if let image = images.first(where: { $0.id == id }) {
                ref = image.reference
            } else {
                ref = id
            }
            try await imageService.removeImage(id: ref, force: force)
            if selectedImageID == id {
                selectedImageID = nil
            }
            await loadImages()
        } catch {
            self.error = .actionFailed("remove image", error)
        }
    }

    // MARK: - Push

    func pushImage(_ reference: String) async {
        isPushing = true
        pushReference = reference
        defer { isPushing = false; pushReference = "" }
        do {
            try await registryService.pushImage(reference: reference)
            NotificationManager.shared.send(
                title: "Image Pushed",
                body: "Successfully pushed \(reference)"
            )
        } catch {
            self.error = .actionFailed("push image '\(reference)'", error)
        }
    }

    // MARK: - Tag

    func tagImage(source: String, target: String) async {
        do {
            try await registryService.tagImage(source: source, target: target)
            await loadImages()
        } catch {
            self.error = .actionFailed("tag image", error)
        }
    }

    // MARK: - Registry

    func registryLogin(server: String, username: String, password: String) async throws {
        try await registryService.login(server: server, username: username, password: password)
    }

    func registryLogout(server: String) async throws {
        try await registryService.logout(server: server)
    }

    func listLoggedInRegistries() async -> [RegistryLogin] {
        (try? await registryService.listLoggedInRegistries()) ?? []
    }

    // MARK: - Prune

    func pruneImages(all: Bool) async {
        do {
            let count = try await imageService.pruneImages(all: all)
            AppEventLog.shared.info("Pruned \(count) image(s)\(all ? " (all unused)" : "")", source: "Images")
            await loadImages()
        } catch {
            self.error = .actionFailed("prune images", error)
        }
    }

    // MARK: - Save / Load

    func saveImage(_ reference: String, to outputPath: String) async {
        do {
            try await registryService.saveImage(reference: reference, outputPath: outputPath)
            NotificationManager.shared.send(
                title: "Image Saved",
                body: "Exported \(reference) to \(URL(fileURLWithPath: outputPath).lastPathComponent)"
            )
        } catch {
            self.error = .actionFailed("save image '\(reference)'", error)
        }
    }

    func loadImage(from inputPath: String) async {
        do {
            try await registryService.loadImage(inputPath: inputPath)
            await loadImages()
            NotificationManager.shared.send(
                title: "Image Loaded",
                body: "Imported image from \(URL(fileURLWithPath: inputPath).lastPathComponent)"
            )
        } catch {
            self.error = .actionFailed("load image", error)
        }
    }
}
