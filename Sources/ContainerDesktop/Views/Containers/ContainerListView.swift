import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Container list view

struct ContainerListView: View {
    @Environment(ContainerListViewModel.self) private var viewModel
    @Environment(LogStreamViewModel.self) private var logVM
    @Environment(DependencyContainer.self) private var deps
    @State private var sortOrder = [KeyPathComparator(\ContainerModel.name)]

    var body: some View {
        @Bindable var vm = viewModel

        VSplitView {
            // Top: container table
            VStack(spacing: 0) {
                containerToolbar

                if viewModel.isLoading && viewModel.containers.isEmpty {
                    ProgressView("Loading containers...")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if viewModel.filteredContainers.isEmpty {
                    emptyState
                } else {
                    containerTable
                }
            }
            .frame(minHeight: 200, idealHeight: 500)

            // Bottom: detail panel (always present to preserve divider position)
            VStack(spacing: 0) {
                // Accent separator line
                Rectangle()
                    .fill(Color.accentColor.opacity(0.4))
                    .frame(height: 2)

                if let container = viewModel.selectedContainer {
                    ContainerDetailPanel(container: container)
                        .id(container.id)
                } else {
                    EmptyStateView(
                        icon: "shippingbox",
                        message: "No container selected",
                        detail: "Select a container above to view details."
                    )
                }
            }
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
            .frame(minHeight: 150, idealHeight: 170)
        }
        .task {
            await viewModel.loadContainers()
            viewModel.startAutoRefresh()
        }
        .onDisappear {
            viewModel.stopAutoRefresh()
        }
        .confirmationDialog(
            "Delete container?",
            isPresented: $vm.showDeleteConfirmation,
            presenting: viewModel.containerToDelete
        ) { container in
            Button("Delete", role: .destructive) {
                Task { await viewModel.executeDelete() }
            }
            if container.status.isActive {
                Button("Stop and Delete", role: .destructive) {
                    Task { await viewModel.executeDelete() }
                }
            }
        } message: { container in
            if container.status.isActive {
                Text("'\(container.name)' is running. It will be stopped and removed.")
            } else {
                Text("Remove container '\(container.name)'? This cannot be undone.")
            }
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var containerToolbar: some View {
        @Bindable var vm = viewModel
        HStack(spacing: 12) {
            Text("Containers")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 6) {
                Text("\(viewModel.runningCount) running")
                    .font(.caption)
                    .foregroundStyle(.green)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(viewModel.stoppedCount) stopped")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            TextField("Filter...", text: $vm.filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Button {
                Task { await viewModel.loadContainers() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Menu {
                Button("Prune stopped containers") {
                    Task {
                        do {
                            try await deps.containerService.pruneContainers()
                            AppEventLog.shared.info("Pruned stopped containers", source: "Containers")
                        } catch {
                            AppEventLog.shared.error(error, context: "Prune stopped containers", source: "Containers")
                        }
                        await viewModel.loadContainers()
                    }
                }
                Button("Stop all running") {
                    Task {
                        for c in viewModel.containers where c.status == .running {
                            await viewModel.stopContainer(c.id)
                        }
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .help("More actions")

            Button {
                viewModel.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("New container")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Table

    @ViewBuilder
    private var containerTable: some View {
        @Bindable var vm = viewModel
        let sorted = viewModel.filteredContainers.sorted(using: sortOrder)
        Table(sorted, selection: $vm.selectedContainerID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { container in
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusColor(container.status))
                        .frame(width: 8, height: 8)
                    Text(container.name)
                        .fontWeight(.medium)
                }
            }
            .width(min: 120, ideal: 180)

            TableColumn("Image", value: \.image) { container in
                Text(container.image)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .width(min: 120, ideal: 200)

            TableColumn("Status", value: \.status) { container in
                StatusBadge(status: container.status)
            }
            .width(80)

            TableColumn("IP", value: \.ipAddressForSort) { container in
                Text(container.ipAddress ?? "—")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Arch", value: \.architecture) { container in
                ArchBadge(architecture: container.architecture)
            }
            .width(60)

            TableColumn("Actions") { container in
                ContainerActionButtons(
                    container: container,
                    onStart: { Task { await viewModel.startContainer(container.id) } },
                    onStop: { Task { await viewModel.stopContainer(container.id) } },
                    onKill: { Task { await viewModel.killContainer(container.id) } },
                    onDelete: { viewModel.confirmDelete(container) }
                )
            }
            .width(80)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let container = viewModel.containers.first(where: { $0.id == id }) {
                if container.status == .running {
                    Button("Stop") { Task { await viewModel.stopContainer(id) } }
                    Button("Kill (force)") { Task { await viewModel.killContainer(id) } }
                    Button("Reclaim Disk Space") { Task { await viewModel.cleanContainer(id) } }
                } else if container.status == .stopped {
                    Button("Start") { Task { await viewModel.startContainer(id) } }
                    Button("Export Filesystem...") { exportContainer(container) }
                }
                Button("Edit...") { viewModel.editContainer(container) }
                Divider()
                Button("Delete", role: .destructive) { viewModel.confirmDelete(container) }
            }
        }
        .onChange(of: viewModel.selectedContainerID) { _, newID in
            if let id = newID {
                logVM.startStreaming(containerID: id)
            } else {
                logVM.stopStreaming()
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "shippingbox")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            if viewModel.filterText.isEmpty {
                Text("No containers")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Create a container to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Button("New Container") {
                    viewModel.showCreateSheet = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No matching containers")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func statusColor(_ status: ContainerStatus) -> Color {
        switch status {
        case .running:  return .green
        case .stopped:  return .secondary
        case .creating: return .blue
        case .stopping: return .orange
        case .unknown:  return .secondary
        }
    }

    private func exportContainer(_ container: ContainerModel) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(container.name).tar"
        panel.canCreateDirectories = true
        panel.message = "Export '\(container.name)' filesystem as tar archive. The container must be stopped."

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await deps.registryService.exportContainer(name: container.name, outputPath: url.path)
                NotificationManager.shared.send(
                    title: "Container Exported",
                    body: "Exported \(container.name) to \(url.lastPathComponent)"
                )
            } catch {
                viewModel.error = .actionFailed("export container '\(container.name)'", error)
            }
        }
    }
}

// MARK: - Container action buttons

struct ContainerActionButtons: View {
    let container: ContainerModel
    let onStart: () -> Void
    let onStop: () -> Void
    let onKill: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if container.status == .running {
                Button(action: onStop) {
                    Image(systemName: "stop.fill")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Stop (graceful)")

                Button(action: onKill) {
                    Image(systemName: "bolt.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.borderless)
                .help("Kill (force SIGKILL)")
            } else if container.status == .stopped {
                Button(action: onStart) {
                    Image(systemName: "play.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                .buttonStyle(.borderless)
                .help("Start")
            }

            Button(role: .destructive, action: onDelete) {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Delete")
        }
    }
}

// MARK: - Container detail panel (bottom split)

struct ContainerDetailPanel: View {
    let container: ContainerModel
    @State private var selectedTab: DetailTab = .inspect
    @Environment(LogStreamViewModel.self) private var logVM
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(DependencyContainer.self) private var deps

    enum DetailTab: String, CaseIterable {
        case inspect  = "Inspect"
        case terminal = "Terminal"
        case logs     = "Logs"
        case stats    = "Stats"
        case files    = "Files"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab bar with actions
            HStack(spacing: 0) {
                ForEach(DetailTab.allCases, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Text(tab.rawValue)
                            .font(.caption)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .background(selectedTab == tab ? Color.accentColor.opacity(0.1) : .clear)
                }
                Spacer()

                // Inline actions
                HStack(spacing: 6) {
                    StatusBadge(status: container.status)

                    if container.status == .running {
                        Button("Stop") {
                            Task { await containerVM.stopContainer(container.id) }
                        }
                        .font(.caption)
                        .controlSize(.small)
                    } else if container.status == .stopped {
                        Button("Start") {
                            Task { await containerVM.startContainer(container.id) }
                        }
                        .font(.caption)
                        .controlSize(.small)
                        .tint(.green)
                    }

                    Button {
                        containerVM.editContainer(container)
                    } label: {
                        Image(systemName: "pencil")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Edit container settings")

                    if container.status == .running {
                        Button {
                            Task { await containerVM.cleanContainer(container.id) }
                        } label: {
                            Image(systemName: "sparkles")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Reclaim unused disk space (container clean)")
                    }

                    if container.status == .stopped {
                        Button {
                            exportContainerFromDetail()
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.caption)
                        }
                        .buttonStyle(.borderless)
                        .help("Export filesystem to tar")
                    }

                    Button(role: .destructive) {
                        containerVM.confirmDelete(container)
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.trailing, 12)
            }
            .background(.bar)

            Divider()

            // Tab content
            switch selectedTab {
            case .logs:
                LogPanelView()
            case .terminal:
                if container.status == .running {
                    TerminalView(containerName: container.name)
                } else {
                    EmptyStateView(
                        icon: "terminal",
                        message: "Container is not running",
                        detail: "Start the container to use the terminal."
                    )
                }
            case .inspect:
                InspectPanelView(container: container)
            case .stats:
                if container.status == .running {
                    ContainerStatsView(containerName: container.name)
                } else {
                    EmptyStateView(
                        icon: "gauge.with.dots.needle.33percent",
                        message: "Container is not running",
                        detail: "Start the container to view resource stats."
                    )
                }
            case .files:
                if container.status == .running {
                    ContainerFilesView(containerName: container.name, deps: deps)
                } else {
                    EmptyStateView(
                        icon: "doc.on.doc",
                        message: "Container is not running",
                        detail: "Start the container to copy files."
                    )
                }
            }
        }
        .frame(minHeight: 150)
    }

    private func exportContainerFromDetail() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(container.name).tar"
        panel.canCreateDirectories = true
        panel.message = "Export '\(container.name)' filesystem as tar archive"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            do {
                try await deps.registryService.exportContainer(name: container.name, outputPath: url.path)
                NotificationManager.shared.send(
                    title: "Container Exported",
                    body: "Exported \(container.name) to \(url.lastPathComponent)"
                )
            } catch {
                containerVM.error = .actionFailed("export container '\(container.name)'", error)
            }
        }
    }
}

// MARK: - Log panel

struct LogPanelView: View {
    @Environment(LogStreamViewModel.self) private var logVM

    var body: some View {
        @Bindable var vm = logVM
        VStack(spacing: 0) {
            // Log filter bar
            HStack(spacing: 8) {
                TextField("Filter logs...", text: $vm.filterText)
                    .textFieldStyle(.roundedBorder)
                    .font(.caption)
                    .frame(maxWidth: 200)

                Toggle("Timestamps", isOn: $vm.showTimestamps)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Toggle("Boot logs", isOn: $vm.showBootLogs)
                    .toggleStyle(.checkbox)
                    .font(.caption)
                    .onChange(of: logVM.showBootLogs) { _, includeBoot in
                        if let id = logVM.currentContainerID {
                            logVM.startStreaming(containerID: id, includeBoot: includeBoot)
                        }
                    }

                Spacer()

                if logVM.isStreaming {
                    HStack(spacing: 4) {
                        Circle().fill(.green).frame(width: 6, height: 6)
                        Text("Live").font(.caption2).foregroundStyle(.secondary)
                    }
                }

                Text("\(logVM.entryCount) of \(logVM.totalEntryCount) lines")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button("Clear") { logVM.clearLogs() }
                    .buttonStyle(.borderless)
                    .font(.caption)

                Button("Copy") { logVM.copyLogsToClipboard() }
                    .buttonStyle(.borderless)
                    .font(.caption)

                Button("Save...") { saveLogsToFile() }
                    .buttonStyle(.borderless)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            // Log entries
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        // Load earlier button
                        if logVM.hasEarlierEntries {
                            Button {
                                logVM.loadEarlierEntries()
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.up.circle")
                                        .font(.caption)
                                    Text("Load \(min(500, logVM.hiddenEntryCount)) earlier entries (\(logVM.hiddenEntryCount) hidden)")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                            }
                            .buttonStyle(.borderless)
                            .foregroundStyle(Color.accentColor)
                        }

                        ForEach(logVM.filteredEntries) { entry in
                            ANSIColoredText(entry: entry, showTimestamp: logVM.showTimestamps)
                                .id(entry.id)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .font(.system(.caption, design: .monospaced))
                .onChange(of: logVM.entries.count) { _, _ in
                    if logVM.autoScroll, let last = logVM.filteredEntries.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }
        }
    }

    private func saveLogsToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "container-logs.txt"
        panel.allowedContentTypes = [.plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }

        // Export the FULL log from disk cache, not just the visible buffer
        let text = logVM.fullLogText()

        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AppEventLog.shared.error(error, context: "Save logs to \(url.lastPathComponent)", source: "Logs")
        }
    }
}

// MARK: - Inspect panel

struct InspectPanelView: View {
    let container: ContainerModel
    @Environment(DependencyContainer.self) private var deps
    @State private var detail: ContainerDetail?
    @State private var isLoading: Bool = false
    @State private var loadError: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Identity section
                inspectSection("Identity") {
                    inspectRow("Name", container.name)
                    inspectRow("ID", container.id)
                    inspectRow("Image", container.image)
                    inspectRow("Architecture", container.architecture.displayName)
                }

                // Status section
                inspectSection("Status") {
                    inspectRow("Status", container.status.displayName)
                    if let pid = container.pid {
                        inspectRow("PID", "\(pid)")
                    }
                    if let created = container.createdAt {
                        inspectRow("Created", Formatters.relativeTime(created))
                    }
                }

                // Network section
                if container.ipAddress != nil || container.dnsDomain != nil {
                    inspectSection("Network") {
                        if let ip = container.ipAddress {
                            inspectRow("IP address", ip)
                        }
                        if let dns = container.dnsDomain {
                            inspectRow("DNS domain", dns)
                            inspectRow("Hostname", "\(container.name).\(dns)")
                        }
                    }
                }

                // Port forwarding section
                if let detail = detail {
                    if !detail.config.publishedPorts.isEmpty || !detail.config.publishedSockets.isEmpty {
                        inspectSection("Port forwarding") {
                            ForEach(detail.config.publishedPorts) { port in
                                inspectRow("Port", port.displayString)
                            }
                            ForEach(detail.config.publishedSockets) { socket in
                                inspectRow("Socket", socket.displayString)
                            }
                        }
                    }

                    // Process section
                    inspectSection("Process") {
                        if !detail.config.entrypoint.isEmpty {
                            inspectRow("Entrypoint", detail.config.entrypoint.joined(separator: " "))
                        }
                        if !detail.config.cmd.isEmpty {
                            inspectRow("Command", detail.config.cmd.joined(separator: " "))
                        }
                        inspectRow("Working dir", detail.config.workingDir)
                        inspectRow("User", detail.config.user)
                    }

                    // Environment section
                    if !detail.config.environment.isEmpty {
                        inspectSection("Environment (\(detail.config.environment.count) vars)") {
                            ForEach(
                                detail.config.environment.sorted(by: { $0.key < $1.key }),
                                id: \.key
                            ) { key, value in
                                inspectRow(key, value)
                            }
                        }
                    }

                    // Volume mounts section
                    if !detail.config.mounts.isEmpty {
                        inspectSection("Volume mounts (\(detail.config.mounts.count))") {
                            ForEach(Array(detail.config.mounts.enumerated()), id: \.offset) { _, mount in
                                inspectRow(
                                    mount.readOnly ? "Mount (RO)" : "Mount",
                                    "\(mount.source) → \(mount.destination)"
                                )
                            }
                        }
                    }
                } else if isLoading {
                    ProgressView("Loading details...")
                        .font(.caption)
                } else if let error = loadError {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Failed to load details: \(error)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // Resources section
                if container.memory != nil || container.cpus != nil {
                    inspectSection("Resources") {
                        if let mem = container.memory {
                            inspectRow("Memory", Formatters.bytes(mem))
                        }
                        if let cpus = container.cpus {
                            inspectRow("CPUs", "\(cpus)")
                        }
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task {
            isLoading = true
            loadError = nil
            do {
                detail = try await deps.containerService.inspect(containerID: container.id)
            } catch {
                loadError = error.localizedDescription
                AppEventLog.shared.warning("Failed to inspect container '\(container.name)': \(error.localizedDescription)", source: "Inspect")
            }
            isLoading = false
        }
    }

    @ViewBuilder
    private func inspectSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func inspectRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}
