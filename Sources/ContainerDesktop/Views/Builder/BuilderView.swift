import AppKit
import SwiftUI

/// View for building container images from Dockerfiles.
/// Uses `container build` CLI command with streaming output.
struct BuilderView: View {
    @Environment(DependencyContainer.self) private var deps

    @State private var dockerfilePath: String = ""
    @State private var contextOverride: String = ""
    @State private var tag: String = ""
    @State private var targetStage: String = ""
    @State private var buildArm64: Bool = true
    @State private var buildAmd64: Bool = false
    @State private var noCache: Bool = false
    @State private var showContextOverride: Bool = false
    @State private var buildArgs: String = ""
    @State private var buildLog: [LogEntry] = []
    @State private var isBuilding: Bool = false
    @State private var buildTask: Task<Void, Never>?
    @State private var buildError: AppError?

    /// The build context directory — either the user's override or the Dockerfile's parent.
    private var effectiveContext: String {
        if !contextOverride.trimmingCharacters(in: .whitespaces).isEmpty {
            return contextOverride.trimmingCharacters(in: .whitespaces)
        }
        guard !dockerfilePath.isEmpty else { return "" }
        return (dockerfilePath as NSString).deletingLastPathComponent
    }

    /// The -f flag value: full path to the Dockerfile, or nil if it's a standard name in the context dir.
    private var dockerfileFlag: String? {
        guard !dockerfilePath.isEmpty else { return nil }
        let filename = (dockerfilePath as NSString).lastPathComponent
        // Standard names in the context directory don't need -f
        if filename == "Dockerfile" || filename == "Containerfile" {
            return nil
        }
        // Always pass the full absolute path — the CLI resolves -f from its
        // own working directory, not from the context directory
        return dockerfilePath
    }

    var body: some View {
        VStack(spacing: 0) {
            buildToolbar

            Divider()

            HSplitView {
                // Left: build configuration
                buildConfigPanel
                    .frame(minWidth: 280, idealWidth: 320, maxWidth: 400)

                // Right: build log
                buildLogPanel
            }
        }
        .alert("Build Error", isPresented: .constant(buildError != nil)) {
            Button("OK") { buildError = nil }
        } message: {
            if let error = buildError {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var buildToolbar: some View {
        HStack(spacing: 12) {
            Text("Build")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            if isBuilding {
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.6)
                    Text("Building...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Button("Cancel") {
                    cancelBuild()
                }
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Config panel

    @ViewBuilder
    private var buildConfigPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Dockerfile picker
                VStack(alignment: .leading, spacing: 8) {
                    Text("Dockerfile")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    HStack(spacing: 8) {
                        TextField("Select a Dockerfile...", text: $dockerfilePath)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Button("Browse...") {
                            browseForDockerfile()
                        }
                        .controlSize(.small)
                    }

                    if !dockerfilePath.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "folder")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("Context: \(effectiveContext)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    } else {
                        Text("Select a Dockerfile, Containerfile, or custom build file (e.g. Dockerfile.enterprise)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Context override (hidden by default)
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("Custom build context", isOn: $showContextOverride)
                        .font(.caption)
                        .onChange(of: showContextOverride) { _, newValue in
                            if !newValue { contextOverride = "" }
                        }

                    if showContextOverride {
                        HStack(spacing: 8) {
                            TextField("Override build context directory", text: $contextOverride)
                                .textFieldStyle(.roundedBorder)
                                .font(.system(.caption, design: .monospaced))

                            Button("Browse...") {
                                browseForContext()
                            }
                            .controlSize(.small)
                        }

                        Text("Use when the build context is a different directory than the Dockerfile's parent.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }

                // Tag
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image tag")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    TextField("my-app:latest", text: $tag)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                // Architecture
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target architectures")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Toggle("ARM64 (native)", isOn: $buildArm64)
                        .toggleStyle(.checkbox)
                    Toggle("AMD64 (Rosetta)", isOn: $buildAmd64)
                        .toggleStyle(.checkbox)
                }

                // Target stage
                VStack(alignment: .leading, spacing: 8) {
                    Text("Target stage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    TextField("e.g. production (optional)", text: $targetStage)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))

                    Text("For multi-stage Dockerfiles — build only up to this stage.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Options
                VStack(alignment: .leading, spacing: 8) {
                    Text("Options")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Toggle("No cache (rebuild all layers)", isOn: $noCache)
                        .toggleStyle(.checkbox)
                }

                // Build args
                VStack(alignment: .leading, spacing: 8) {
                    Text("Build arguments")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    TextEditor(text: $buildArgs)
                        .font(.system(.caption, design: .monospaced))
                        .frame(height: 60)
                        .border(Color.secondary.opacity(0.2))

                    Text("One KEY=VALUE per line")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                // Build button
                Button {
                    startBuild()
                } label: {
                    Label("Start Build", systemImage: "hammer.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canBuild || isBuilding)
                .controlSize(.large)
            }
            .padding(16)
        }
    }

    // MARK: - Build log panel

    @ViewBuilder
    private var buildLogPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Build output")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(buildLog.count) lines")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Button("Clear") {
                    buildLog.removeAll()
                }
                .font(.caption)
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(.bar)

            Divider()

            if buildLog.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "hammer")
                        .font(.title)
                        .foregroundStyle(.tertiary)
                    Text("Build output will appear here")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(buildLog) { entry in
                                ANSIColoredText(entry: entry, showTimestamp: false, fontSize: 11)
                                    .id(entry.id)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .onChange(of: buildLog.count) { _, _ in
                        if let last = buildLog.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Actions

    private var canBuild: Bool {
        !effectiveContext.isEmpty &&
        !tag.trimmingCharacters(in: .whitespaces).isEmpty &&
        (buildArm64 || buildAmd64)
    }

    private func browseForDockerfile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select a Dockerfile, Containerfile, or custom build file"
        panel.treatsFilePackagesAsDirectories = true

        if panel.runModal() == .OK, let url = panel.url {
            dockerfilePath = url.path
        }
    }

    private func browseForContext() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select the build context directory"

        if panel.runModal() == .OK, let url = panel.url {
            contextOverride = url.path
        }
    }

    private func startBuild() {
        buildLog.removeAll()
        isBuilding = true
        buildError = nil

        var architectures: [Architecture] = []
        if buildArm64 { architectures.append(.arm64) }
        if buildAmd64 { architectures.append(.amd64) }

        // Parse build args
        var buildArgDict: [String: String] = [:]
        for line in buildArgs.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let parts = trimmed.split(separator: "=", maxSplits: 1)
            if parts.count == 2 {
                buildArgDict[String(parts[0])] = String(parts[1])
            }
        }

        // Use dockerfileFlag — returns full path for non-standard names, nil for Dockerfile/Containerfile
        let stream = deps.builderService.build(
            contextPath: effectiveContext,
            tag: tag,
            architectures: architectures,
            buildArgs: buildArgDict,
            dockerfile: dockerfileFlag,
            target: targetStage.isEmpty ? nil : targetStage,
            noCache: noCache
        )

        buildTask = Task {
            do {
                for try await entry in stream {
                    await MainActor.run {
                        buildLog.append(entry)
                    }
                }
                await MainActor.run {
                    isBuilding = false
                    buildLog.append(LogEntry(
                        timestamp: Date(),
                        source: .system,
                        message: "Build completed successfully."
                    ))
                }
            } catch {
                await MainActor.run {
                    isBuilding = false
                    buildError = .actionFailed("build", error)
                }
            }
        }
    }

    private func cancelBuild() {
        buildTask?.cancel()
        buildTask = nil
        isBuilding = false
        buildLog.append(LogEntry(
            timestamp: Date(),
            source: .system,
            message: "Build cancelled."
        ))
    }
}
