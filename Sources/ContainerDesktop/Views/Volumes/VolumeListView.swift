import AppKit
import SwiftUI

struct VolumeListView: View {
    @Environment(VolumeViewModel.self) private var viewModel
    @Environment(DependencyContainer.self) private var deps

    @State private var selectedVolumeID: String?
    @State private var newVolumeName: String = ""
    @State private var newVolumeSize: String = ""
    @State private var sortOrder = [KeyPathComparator(\VolumeModel.name)]

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            volumeToolbar

            VSplitView {
                // Top: volume table
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.volumes.isEmpty {
                        ProgressView("Loading volumes...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if viewModel.volumes.isEmpty {
                        EmptyStateView(
                            icon: "externaldrive",
                            message: "No volumes",
                            detail: "Volumes provide persistent storage for containers.",
                            action: { viewModel.showCreateSheet = true },
                            actionLabel: "Create Volume"
                        )
                    } else {
                        volumeTable
                    }
                }
                .frame(minHeight: 150, idealHeight: 500)

                // Bottom: detail panel
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(height: 2)

                    if let selected = selectedVolume {
                        VolumeDetailPanel(
                            volume: selected,
                            deps: deps,
                            onDelete: {
                                Task {
                                    await viewModel.removeVolume(selected.name)
                                    selectedVolumeID = nil
                                }
                            }
                        )
                        .id(selected.id)
                    } else {
                        EmptyStateView(
                            icon: "externaldrive",
                            message: "No volume selected",
                            detail: "Select a volume above to view details."
                        )
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .frame(minHeight: 150, idealHeight: 170)
            }
        }
        .task {
            await viewModel.loadVolumes()
        }
        .sheet(isPresented: $vm.showCreateSheet) {
            createVolumeSheet
        }
        .confirmationDialog(
            "Prune unused volumes?",
            isPresented: $vm.showPruneConfirmation
        ) {
            Button("Prune", role: .destructive) {
                Task { await viewModel.pruneVolumes() }
            }
        } message: {
            Text("This will remove all volumes not attached to a container. This cannot be undone.")
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }

    private var selectedVolume: VolumeModel? {
        viewModel.volumes.first { $0.id == selectedVolumeID }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var volumeToolbar: some View {
        HStack(spacing: 12) {
            Text("Volumes")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            Text("\(viewModel.volumes.count) volumes")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.loadVolumes() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                viewModel.showPruneConfirmation = true
            } label: {
                Image(systemName: "trash.circle")
            }
            .help("Prune unused volumes")

            Button {
                viewModel.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Create volume")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Table

    @ViewBuilder
    private var volumeTable: some View {
        let sorted = viewModel.volumes.sorted(using: sortOrder)
        Table(sorted, selection: $selectedVolumeID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { volume in
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(volume.name)
                        .fontWeight(.medium)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("Driver", value: \.driver) { volume in
                Text(volume.driver)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .width(80)

            TableColumn("Mountpoint", value: \.mountpoint) { volume in
                Text(volume.mountpoint)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .help(volume.mountpoint)
            }
            .width(min: 150, ideal: 300)

            TableColumn("Size", value: \.sizeForSort) { volume in
                Text(volume.displaySize)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(70)

            TableColumn("Actions") { volume in
                Button(role: .destructive) {
                    Task { await viewModel.removeVolume(volume.name) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Remove volume")
            }
            .width(50)
        }
    }

    // MARK: - Create sheet

    @ViewBuilder
    private var createVolumeSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Create volume")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Cancel") {
                    viewModel.showCreateSheet = false
                    newVolumeName = ""
                    newVolumeSize = ""
                }
                .keyboardShortcut(.cancelAction)
            }

            LabeledContent("Name") {
                TextField("my-volume", text: $newVolumeName)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Size") {
                HStack(spacing: 8) {
                    TextField("e.g. 512M, 2G", text: $newVolumeSize)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                    Text("optional")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Text("Size accepts K, M, G, T, or P suffixes. Leave empty for the default size.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                Spacer()
                Button("Create") {
                    let size = newVolumeSize.trimmingCharacters(in: .whitespaces)
                    Task {
                        await viewModel.createVolume(
                            name: newVolumeName.trimmingCharacters(in: .whitespaces),
                            size: size.isEmpty ? nil : size
                        )
                        newVolumeName = ""
                        newVolumeSize = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreateVolume)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
    }

    /// Whether the Create button should be enabled.
    /// Name must be valid, and size — if provided — must also be valid.
    private var canCreateVolume: Bool {
        let trimmedSize = newVolumeSize.trimmingCharacters(in: .whitespaces)
        let sizeIsValid = trimmedSize.isEmpty || InputValidation.isValidVolumeSize(trimmedSize)
        return InputValidation.isValidVolumeName(newVolumeName) && sizeIsValid
    }
}

// MARK: - Volume detail panel

struct VolumeDetailPanel: View {
    let volume: VolumeModel
    let deps: DependencyContainer
    let onDelete: () -> Void
    @State private var containerMounts: [(container: ContainerModel, destination: String, readOnly: Bool)] = []
    @State private var isLoadingContainers: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundStyle(.blue)
                    Text(volume.name)
                        .font(.headline)
                }

                Spacer()

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(volume.mountpoint, forType: .string)
                } label: {
                    Label("Copy path", systemImage: "doc.on.doc")
                        .font(.caption)
                }
                .controlSize(.small)

                if !volume.mountpoint.isEmpty {
                    Button {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: volume.mountpoint)
                    } label: {
                        Label("Reveal in Finder", systemImage: "folder")
                            .font(.caption)
                    }
                    .controlSize(.small)
                }

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    volumeInfoSection
                    containersSection
                    usageSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .task {
            await loadContainerUsage()
        }
    }

    @ViewBuilder
    private var volumeInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Volume details")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Name")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(volume.name)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Driver")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(volume.driver.isEmpty ? "local" : volume.driver)
                        .font(.callout)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Size")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(volume.displaySize)
                        .font(.callout)
                }

                if let created = volume.createdAt {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Created")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(Formatters.relativeTime(created))
                            .font(.callout)
                    }
                }
            }

            if !volume.mountpoint.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Mountpoint")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(volume.mountpoint)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Containers using this volume (\(containerMounts.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if isLoadingContainers {
                ProgressView("Checking containers...")
                    .font(.caption)
            } else if containerMounts.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No containers are using this volume")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("This volume can be safely deleted or pruned.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(Array(containerMounts.enumerated()), id: \.offset) { _, mount in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(mount.container.status == .running ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(mount.container.name)
                                .font(.callout)
                                .fontWeight(.medium)
                            HStack(spacing: 4) {
                                Text("→ \(mount.destination)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                if mount.readOnly {
                                    Text("RO")
                                        .font(.system(size: 9, design: .monospaced))
                                        .fontWeight(.medium)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.orange.opacity(0.15))
                                        .foregroundStyle(.orange)
                                        .clipShape(RoundedRectangle(cornerRadius: 3))
                                }
                            }
                        }

                        Spacer()

                        StatusBadge(status: mount.container.status)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                usageRow("Mount this volume in a container:",
                         "container run -v \(volume.name):/data my-image")
                usageRow("Mount as read-only:",
                         "container run -v \(volume.name):/data:ro my-image")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func usageRow(_ label: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }

    // MARK: - Load container usage

    private func loadContainerUsage() async {
        isLoadingContainers = true
        defer { isLoadingContainers = false }

        var results: [(container: ContainerModel, destination: String, readOnly: Bool)] = []

        // Inspect each container to find mounts referencing this volume
        let containers = (try? await deps.containerService.listContainers()) ?? []
        for container in containers {
            if let detail = try? await deps.containerService.inspect(containerID: container.id) {
                for mount in detail.config.mounts {
                    // Check if mount source matches volume name or mountpoint
                    if mount.source == volume.name || mount.source == volume.mountpoint {
                        results.append((container: container, destination: mount.destination, readOnly: mount.readOnly))
                    }
                }
            }
        }

        await MainActor.run {
            containerMounts = results
        }
    }
}
