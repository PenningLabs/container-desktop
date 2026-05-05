import SwiftUI

/// Sheet for editing an existing container's configuration.
///
/// Since Apple containers can't be modified in-place, editing works by:
/// 1. Capturing the current config
/// 2. Letting the user change settings
/// 3. Stopping and removing the old container
/// 4. Creating a new container with the same name and updated settings
///
/// The UX feels like editing, even though it's a recreate under the hood.
struct ContainerEditSheet: View {
    let container: ContainerModel
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(DNSViewModel.self) private var dnsVM
    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss

    // Editable fields pre-populated from the container
    @State private var memoryGB: Double
    @State private var cpuCount: Int
    @State private var dnsDomain: String
    @State private var environmentText: String
    @State private var command: String
    @State private var architecture: Architecture
    @State private var portMappings: [PortMapping]
    @State private var socketMappings: [SocketMapping]
    @State private var mounts: [MountSpec]

    // Advanced options
    @State private var networkName: String
    @State private var macAddress: String = ""
    @State private var sshForwarding: Bool = false
    @State private var initProcess: Bool = false
    @State private var virtualization: Bool = false
    @State private var availableNetworks: [String] = []
    @State private var autoRemove: Bool = false
    @State private var envFilePath: String = ""
    @State private var workingDir: String = ""
    @State private var entrypoint: String = ""
    @State private var runAsUser: String = ""
    @State private var containerHostname: String = ""

    // State
    @State private var isApplying: Bool = false
    @State private var applyError: AppError?
    @State private var inspectedDetail: ContainerDetail?

    init(container: ContainerModel) {
        self.container = container

        // Pre-populate from container model
        let memGB = container.memory.map { Double($0) / (1024 * 1024 * 1024) } ?? 1.0
        _memoryGB = State(initialValue: memGB)
        _cpuCount = State(initialValue: container.cpus ?? 4)
        _dnsDomain = State(initialValue: container.dnsDomain ?? "")
        _architecture = State(initialValue: container.architecture)
        _environmentText = State(initialValue: "")
        _command = State(initialValue: "")
        _portMappings = State(initialValue: [])
        _socketMappings = State(initialValue: [])
        _mounts = State(initialValue: [])
        _networkName = State(initialValue: container.networkName == "default" ? "" : container.networkName)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Edit container")
                        .font(.title3)
                        .fontWeight(.medium)
                    Text("Editing '\(container.name)' — will recreate with updated settings")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Read-only identity
                    identitySection

                    // Editable network
                    networkSection

                    // Port forwarding
                    PortMappingEditor(
                        portMappings: $portMappings,
                        socketMappings: $socketMappings
                    )

                    // Volume mounts
                    MountEditor(mounts: $mounts)

                    // Advanced runtime options (SSH, init, virtualization)
                    AdvancedContainerOptions(
                        sshForwarding: $sshForwarding,
                        initProcess: $initProcess,
                        virtualization: $virtualization
                    )

                    // Editable resources
                    resourceSection

                    // Editable environment
                    environmentSection

                    // Warning
                    warningBanner
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                if isApplying {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Recreating container...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let error = applyError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }

                Spacer()

                Button("Apply Changes") {
                    Task { await applyChanges() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(isApplying)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 520, height: 720)
        .task {
            await loadInspectDetail()
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var identitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Container")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LabeledContent("Name") {
                Text(container.name)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Image") {
                Text(container.image)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            LabeledContent("Architecture") {
                Picker("", selection: $architecture) {
                    Text("ARM64 (native)").tag(Architecture.arm64)
                    Text("AMD64 (Rosetta)").tag(Architecture.amd64)
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
            }
        }
    }

    @ViewBuilder
    private var networkSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Network")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LabeledContent("Network") {
                HStack(spacing: 4) {
                    TextField("default", text: $networkName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 120)

                    if !availableNetworks.isEmpty {
                        Menu {
                            Button("default") { networkName = "" }
                            Divider()
                            ForEach(availableNetworks, id: \.self) { net in
                                Button(net) { networkName = net }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28)
                    }
                }
            }

            LabeledContent("DNS domain") {
                HStack(spacing: 4) {
                    TextField("e.g. dev", text: $dnsDomain)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)

                    if !dnsVM.domains.isEmpty {
                        Menu {
                            Button("None") { dnsDomain = "" }
                            Divider()
                            ForEach(dnsVM.domains, id: \.self) { domain in
                                Button(domain) { dnsDomain = domain }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28)
                    }

                    if !dnsDomain.isEmpty {
                        Text("\(container.name).\(dnsDomain)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }

            LabeledContent("MAC address") {
                HStack(spacing: 4) {
                    TextField("Auto-generated", text: $macAddress)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 160)

                    if !macAddress.isEmpty && !InputValidation.isValidMAC(macAddress) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .help("Format: XX:XX:XX:XX:XX:XX")
                    }
                }
            }

            if let ip = container.ipAddress {
                LabeledContent("Current IP") {
                    Text(ip)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text("IP address will be reassigned on recreate.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var resourceSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("Memory") {
                HStack(spacing: 8) {
                    Slider(value: $memoryGB, in: 0.5...64, step: 0.5)
                        .frame(width: 180)
                    Text("\(memoryGB, specifier: "%.1f") GB")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
            }

            LabeledContent("CPUs") {
                HStack(spacing: 8) {
                    Slider(value: .init(
                        get: { Double(cpuCount) },
                        set: { cpuCount = Int($0) }
                    ), in: 1...Double(ProcessInfo.processInfo.processorCount), step: 1)
                        .frame(width: 180)
                    Text("\(cpuCount)")
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }
            }
        }
    }

    @ViewBuilder
    private var environmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment & process")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            TextEditor(text: $environmentText)
                .font(.system(.caption, design: .monospaced))
                .frame(height: 80)
                .border(Color.secondary.opacity(0.2))
                .help("One KEY=VALUE per line. Pre-populated from current container.")

            LabeledContent("Env file") {
                HStack(spacing: 8) {
                    TextField("path/to/.env", text: $envFilePath)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))

                    Button("Browse...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowsMultipleSelection = false
                        if panel.runModal() == .OK, let url = panel.url {
                            envFilePath = url.path
                        }
                    }
                    .controlSize(.small)
                }
            }

            LabeledContent("Command") {
                TextField("Leave empty to keep original", text: $command)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            LabeledContent("Entrypoint") {
                TextField("Override image default", text: $entrypoint)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            LabeledContent("Working dir") {
                TextField("/app", text: $workingDir)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            LabeledContent("Run as user") {
                TextField("e.g. root, 1000, nobody", text: $runAsUser)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            LabeledContent("Hostname") {
                TextField("Container hostname", text: $containerHostname)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            Toggle("Auto-remove when stopped (--rm)", isOn: $autoRemove)
                .toggleStyle(.checkbox)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var warningBanner: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text("Container will be recreated")
                    .font(.caption)
                    .fontWeight(.medium)
                Text("The existing container will be stopped and removed, then a new one created with the same name and image but with your updated settings. Any data not on a volume will be lost.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Load existing config

    private func loadInspectDetail() async {
        do {
            let detail = try await deps.containerService.inspect(containerID: container.id)
            inspectedDetail = detail

            // Pre-populate environment from inspected config
            let envString = detail.config.environment
                .sorted(by: { $0.key < $1.key })
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "\n")
            environmentText = envString

            // Pre-populate command
            if !detail.config.cmd.isEmpty {
                command = detail.config.cmd.joined(separator: " ")
            }

            // Pre-populate port and socket mappings
            portMappings = detail.config.publishedPorts
            socketMappings = detail.config.publishedSockets

            // Pre-populate volume mounts
            mounts = detail.config.mounts

            // Pre-populate entrypoint, working dir, user from inspect
            if !detail.config.entrypoint.isEmpty {
                entrypoint = detail.config.entrypoint.joined(separator: " ")
            }
            if !detail.config.workingDir.isEmpty {
                workingDir = detail.config.workingDir
            }
            if !detail.config.user.isEmpty {
                runAsUser = detail.config.user
            }
        } catch {
            AppEventLog.shared.error(error, context: "Loading container config for edit", source: container.name)
        }

        // Pre-load available networks for the picker
        do {
            let networks = try await deps.networkService.listNetworks()
            availableNetworks = networks.filter { $0.name != "default" }.map(\.name)
        } catch {
            // Non-critical: picker will be empty
        }
    }

    // MARK: - Apply

    private func applyChanges() async {
        isApplying = true
        applyError = nil

        // 1. Build new options FIRST — before any destructive operations
        var options = ContainerCreateOptions.default
        options.architecture = architecture

        if !dnsDomain.isEmpty {
            options.dnsDomain = dnsDomain
        }

        options.memory = UInt64(memoryGB * 1024 * 1024 * 1024)
        options.cpus = cpuCount

        // Parse environment
        for line in environmentText.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { continue }
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                options.environment[String(parts[0])] = String(parts[1])
            }
        }

        // Parse command
        if !command.trimmingCharacters(in: .whitespaces).isEmpty {
            options.command = command.split(separator: " ").map(String.init)
        }

        // Port and socket mappings
        options.portMappings = portMappings
        options.socketMappings = socketMappings

        // Volume mounts
        options.mounts = mounts

        // Advanced options
        options.sshForwarding = sshForwarding
        options.initProcess = initProcess
        options.virtualization = virtualization
        if !networkName.isEmpty {
            options.network = networkName
        }
        if !macAddress.isEmpty && InputValidation.isValidMAC(macAddress) {
            options.macAddress = macAddress
        }

        // Process and runtime options
        options.autoRemove = autoRemove
        if !envFilePath.isEmpty {
            options.envFile = envFilePath
        }
        if !workingDir.isEmpty {
            options.workingDir = workingDir
        }
        if !entrypoint.isEmpty {
            options.entrypoint = entrypoint
        }
        if !runAsUser.isEmpty {
            options.user = runAsUser
        }
        if !containerHostname.isEmpty {
            options.hostname = containerHostname
        }

        // 2. Save original config for recovery if create fails
        let originalName = container.name
        let originalImage = container.image

        AppEventLog.shared.containerEvent(originalName, "Editing container — will stop, remove, and recreate")

        do {
            // 3. Stop if running
            if container.status == .running {
                AppEventLog.shared.containerEvent(originalName, "Stopping container for edit")
                try await deps.containerService.stopContainer(id: container.id, timeout: .seconds(10))
            }

            // 4. Remove
            AppEventLog.shared.containerEvent(originalName, "Removing old container")
            try await deps.containerService.removeContainer(id: container.id, force: true)

            // 5. Recreate with new settings
            AppEventLog.shared.containerEvent(originalName, "Creating container with updated settings")
            do {
                _ = try await deps.containerService.createContainer(
                    name: originalName,
                    image: originalImage,
                    options: options
                )
                AppEventLog.shared.containerEvent(originalName, "Container recreated successfully")
            } catch {
                // Create failed after delete — try to restore with default options
                AppEventLog.shared.warning(
                    "Failed to recreate with new settings: \(error.localizedDescription). Attempting recovery with original image...",
                    source: originalName
                )

                do {
                    var recoveryOptions = ContainerCreateOptions.default
                    recoveryOptions.architecture = container.architecture
                    _ = try await deps.containerService.createContainer(
                        name: originalName,
                        image: originalImage,
                        options: recoveryOptions
                    )
                    AppEventLog.shared.warning(
                        "Container restored with default settings. Your custom configuration was lost. Check the Event Log for details.",
                        source: originalName
                    )
                } catch {
                    AppEventLog.shared.error(
                        error,
                        context: "Recovery also failed. Container '\(originalName)' has been lost. Recreate it manually from image '\(originalImage)'.",
                        source: originalName
                    )
                }

                throw error // Re-throw the original error to show in the UI
            }

            await MainActor.run {
                isApplying = false
                dismiss()
            }
            await containerVM.loadContainers()

        } catch {
            AppEventLog.shared.error(error, context: "Failed to edit container", source: originalName)
            await MainActor.run {
                isApplying = false
                applyError = .actionFailed("edit container", error)
            }
            await containerVM.loadContainers()
        }
    }
}
