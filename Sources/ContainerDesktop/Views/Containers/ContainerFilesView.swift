import SwiftUI

/// Panel for copying files to/from a running container using `container cp`.
struct ContainerFilesView: View {

    let containerName: String
    let deps: DependencyContainer

    @State private var containerPath: String = "/tmp/"
    @State private var isUploading = false
    @State private var isDownloading = false
    @State private var statusMessage: String?
    @State private var isError = false
    @State private var recentCopies: [CopyRecord] = []

    struct CopyRecord: Identifiable {
        let id = UUID()
        let direction: String  // "→" or "←"
        let hostPath: String
        let containerPath: String
        let timestamp: Date
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Destination path field
            HStack(spacing: 8) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text("Container path:")
                    .font(.callout)
                TextField("/path/in/container", text: $containerPath)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: 300)
            }
            .padding(.top, 8)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    uploadToContainer()
                } label: {
                    Label("Copy to Container", systemImage: "arrow.right.doc.on.clipboard")
                }
                .disabled(isUploading || isDownloading || containerPath.isEmpty)
                .help("Select a file or folder on your Mac to copy into the container")

                Button {
                    downloadFromContainer()
                } label: {
                    Label("Copy from Container", systemImage: "arrow.down.doc")
                }
                .disabled(isUploading || isDownloading || containerPath.isEmpty)
                .help("Copy a file or folder from the container to your Mac")

                if isUploading || isDownloading {
                    ProgressView()
                        .controlSize(.small)
                    Text(isUploading ? "Copying to container..." : "Copying from container...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            // Status message
            if let statusMessage = statusMessage {
                HStack(spacing: 6) {
                    Image(systemName: isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(isError ? .red : .green)
                    Text(statusMessage)
                        .font(.callout)
                        .foregroundStyle(isError ? .red : .primary)
                }
            }

            Divider()

            // Recent copies
            VStack(alignment: .leading, spacing: 8) {
                Text("Recent copies")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                if recentCopies.isEmpty {
                    Text("No files copied yet in this session")
                        .font(.callout)
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 8)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(recentCopies) { record in
                                HStack(spacing: 8) {
                                    Image(systemName: record.direction == "→" ? "arrow.right.circle.fill" : "arrow.left.circle.fill")
                                        .foregroundStyle(record.direction == "→" ? .blue : .green)
                                        .font(.caption)
                                    Text("\(shortenPath(record.hostPath)) \(record.direction) \(record.containerPath)")
                                        .font(.system(.caption, design: .monospaced))
                                        .lineLimit(1)
                                    Spacer()
                                    Text(record.timestamp, style: .time)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                }
            }

            Spacer()
        }
        .padding()
    }

    // MARK: - Actions

    private func uploadToContainer() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Select file or folder to copy into \(containerName)"
        panel.prompt = "Copy to Container"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isUploading = true
        statusMessage = nil
        isError = false

        Task {
            do {
                try await deps.containerService.copyToContainer(
                    id: containerName,
                    hostPath: url.path,
                    containerPath: containerPath
                )
                statusMessage = "Copied \(url.lastPathComponent) → \(containerName):\(containerPath)"
                isError = false
                recentCopies.insert(CopyRecord(
                    direction: "→",
                    hostPath: url.path,
                    containerPath: containerPath,
                    timestamp: Date()
                ), at: 0)
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isUploading = false
        }
    }

    private func downloadFromContainer() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.title = "Choose destination for files from \(containerName)"
        panel.prompt = "Save Here"

        guard panel.runModal() == .OK, let url = panel.url else { return }

        isDownloading = true
        statusMessage = nil
        isError = false

        Task {
            do {
                try await deps.containerService.copyFromContainer(
                    id: containerName,
                    containerPath: containerPath,
                    hostPath: url.path
                )
                statusMessage = "Copied \(containerName):\(containerPath) → \(url.path)"
                isError = false
                recentCopies.insert(CopyRecord(
                    direction: "←",
                    hostPath: url.path,
                    containerPath: containerPath,
                    timestamp: Date()
                ), at: 0)
            } catch {
                statusMessage = error.localizedDescription
                isError = true
            }
            isDownloading = false
        }
    }

    private func shortenPath(_ path: String) -> String {
        let components = path.components(separatedBy: "/")
        if components.count > 3 {
            return ".../" + components.suffix(2).joined(separator: "/")
        }
        return path
    }
}
