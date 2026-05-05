import SwiftUI

/// Sheet presented when creating a new container.
/// Collects name, image, resource limits, and optional configuration.
struct ContainerCreateSheet: View {
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(ImageBrowserViewModel.self) private var imageVM
    @Environment(DNSViewModel.self) private var dnsVM
    @Environment(DependencyContainer.self) private var deps
    @Environment(\.dismiss) private var dismiss

    // Read user-configured defaults from Settings
    @AppStorage("defaultMemoryGB") private var defaultMemoryGB: Double = 1.0
    @AppStorage("defaultCPUs") private var defaultCPUs: Int = 4
    @AppStorage("defaultArch") private var defaultArch: String = "arm64"

    @State private var name: String = ""
    @State private var image: String = ""
    @State private var architecture: Architecture = .arm64
    @State private var dnsDomain: String = ""
    @State private var memoryGB: Double = 1
    @State private var cpuCount: Int = 4
    @State private var environmentText: String = ""
    @State private var command: String = ""
    @State private var portMappings: [PortMapping] = []
    @State private var socketMappings: [SocketMapping] = []
    @State private var mounts: [MountSpec] = []
    @State private var sshForwarding: Bool = false
    @State private var initProcess: Bool = false
    @State private var networkName: String = ""
    @State private var macAddress: String = ""
    @State private var virtualization: Bool = false
    @State private var availableNetworks: [String] = []
    @State private var autoRemove: Bool = false
    @State private var envFilePath: String = ""
    @State private var workingDir: String = ""
    @State private var entrypoint: String = ""
    @State private var runAsUser: String = ""
    @State private var hostname: String = ""
    @State private var isCreating: Bool = false
    @State private var showImagePicker: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("New container")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    requiredSection
                    networkSection
                    PortMappingEditor(
                        portMappings: $portMappings,
                        socketMappings: $socketMappings
                    )
                    MountEditor(mounts: $mounts)
                    resourceSection
                    advancedSection
                }
                .padding(20)
            }

            Divider()

            // Footer
            HStack {
                if isCreating {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Creating...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let error = validationError {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button("Create") {
                    Task { await create() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid || isCreating)
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 520, height: 640)
        .onAppear {
            // Apply user-configured defaults from Settings
            architecture = Architecture(rawValue: defaultArch) ?? .arm64
            memoryGB = defaultMemoryGB
            cpuCount = defaultCPUs
        }
        .task {
            // Pre-load images for the picker
            if imageVM.images.isEmpty {
                await imageVM.loadImages()
            }
            // Pre-load DNS domains for the picker
            if dnsVM.domains.isEmpty {
                await dnsVM.loadDomains()
            }
            // Pre-load networks for the picker
            do {
                let networks = try await deps.networkService.listNetworks()
                availableNetworks = networks.filter { $0.name != "default" }.map(\.name)
            } catch {
                // Non-critical: picker will be empty but user can proceed with default network
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var requiredSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Basic")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LabeledContent("Name") {
                TextField("my-container", text: $name)
                    .textFieldStyle(.roundedBorder)
            }

            LabeledContent("Image") {
                HStack(spacing: 8) {
                    TextField("nginx:latest", text: $image)
                        .textFieldStyle(.roundedBorder)

                    if !imageVM.images.isEmpty {
                        Menu {
                            ForEach(imageVM.images) { img in
                                Button(img.reference) {
                                    image = img.reference
                                }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28)
                        .help("Select from local images")
                    }
                }
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
                        .help("Select from registered DNS domains")
                    }

                    if !dnsDomain.isEmpty && !name.isEmpty {
                        Text("\(name).\(dnsDomain)")
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

            Text("Each container gets a dedicated IP on the selected network. DNS domain enables hostname access (e.g. container-name.domain).")
                .font(.caption2)
                .foregroundStyle(.tertiary)
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
    private var advancedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Environment & command")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            LabeledContent("Environment") {
                TextEditor(text: $environmentText)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 60)
                    .border(Color.secondary.opacity(0.2))
                    .help("One KEY=VALUE per line")
            }

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
                TextField("e.g. /bin/sh", text: $command)
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
                TextField("Container hostname", text: $hostname)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))
            }

            Toggle("Auto-remove when stopped (--rm)", isOn: $autoRemove)
                .toggleStyle(.checkbox)
                .font(.callout)
        }

        AdvancedContainerOptions(
            sshForwarding: $sshForwarding,
            initProcess: $initProcess,
            virtualization: $virtualization
        )
    }

    // MARK: - Validation & creation

    private var isValid: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedImage = image.trimmingCharacters(in: .whitespaces)
        return InputValidation.isValidContainerName(trimmedName)
            && InputValidation.isValidImageReference(trimmedImage)
    }

    /// Validation error message for the user, or nil if everything is valid.
    private var validationError: String? {
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedImage = image.trimmingCharacters(in: .whitespaces)
        if trimmedName.isEmpty { return nil } // Don't show error for empty (button is just disabled)
        if !InputValidation.isValidContainerName(trimmedName) {
            return "Container name must be alphanumeric with hyphens, underscores, or dots."
        }
        if !trimmedImage.isEmpty && !InputValidation.isValidImageReference(trimmedImage) {
            return "Image reference contains invalid characters."
        }
        if !macAddress.isEmpty && !InputValidation.isValidMAC(macAddress) {
            return "MAC address must be in format XX:XX:XX:XX:XX:XX."
        }
        return nil
    }

    private func create() async {
        isCreating = true
        defer { isCreating = false }

        // Final validation before executing
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        let trimmedImage = image.trimmingCharacters(in: .whitespaces)
        guard InputValidation.isValidContainerName(trimmedName),
              InputValidation.isValidImageReference(trimmedImage) else {
            AppEventLog.shared.warning("Container creation blocked: invalid name or image reference", source: "Validation")
            return
        }

        var options = ContainerCreateOptions.default
        options.architecture = architecture

        if !dnsDomain.isEmpty {
            options.dnsDomain = dnsDomain
        }

        options.memory = UInt64(memoryGB * 1024 * 1024 * 1024)
        options.cpus = cpuCount

        // Parse environment variables — skip invalid lines
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
        if !hostname.isEmpty {
            options.hostname = hostname
        }

        await containerVM.createContainer(
            name: trimmedName,
            image: trimmedImage,
            options: options
        )
    }
}
