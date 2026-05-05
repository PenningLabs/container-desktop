import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Detail view shown when an image is selected, displaying reference,
/// digest, size, architecture, and full config from inspect.
struct ImageDetailView: View {
    let image: ImageModel
    @Environment(ImageBrowserViewModel.self) private var imageVM
    @Environment(DependencyContainer.self) private var deps
    @State private var inspectDetail: ImageDetail?
    @State private var isLoadingInspect: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                imageHeader
                imageInfo
                configSection
                actionsSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await loadInspect()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var imageHeader: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(image.repository)
                    .font(.title3)
                    .fontWeight(.medium)

                HStack(spacing: 8) {
                    Text(image.tag)
                        .font(.system(.caption, design: .monospaced))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))

                    ArchBadge(architecture: image.architecture)

                    Text(image.displaySize)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(image.reference, forType: .string)
            } label: {
                Label("Copy reference", systemImage: "doc.on.doc")
            }
            .controlSize(.small)
        }
    }

    // MARK: - Info

    @ViewBuilder
    private var imageInfo: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Image details")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    detailRow("Reference", image.reference)
                    Divider()
                    detailRow("Digest", String(image.digest.prefix(48)) + (image.digest.count > 48 ? "..." : ""))
                    Divider()
                    detailRow("Size", image.displaySize)
                    Divider()
                    detailRow("Architecture", image.architecture.displayName)
                    Divider()
                    detailRow("OS", image.os)
                }
                .padding(4)
            }
        }
    }

    // MARK: - Config from inspect

    @ViewBuilder
    private var configSection: some View {
        if let detail = inspectDetail {
            VStack(alignment: .leading, spacing: 12) {
                Text("Configuration")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        if let entrypoint = detail.config.entrypoint, !entrypoint.isEmpty {
                            detailRow("Entrypoint", entrypoint.joined(separator: " "))
                        }
                        if let cmd = detail.config.cmd, !cmd.isEmpty {
                            Divider()
                            detailRow("Cmd", cmd.joined(separator: " "))
                        }
                        if let workDir = detail.config.workingDir {
                            Divider()
                            detailRow("Working dir", workDir)
                        }
                        if let user = detail.config.user, !user.isEmpty {
                            Divider()
                            detailRow("User", user)
                        }
                    }
                    .padding(4)
                }

                // Environment variables
                if !detail.config.environment.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Environment (\(detail.config.environment.count) vars)")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(
                                    detail.config.environment.sorted(by: { $0.key < $1.key }),
                                    id: \.key
                                ) { key, value in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(key)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                            .frame(minWidth: 100, alignment: .trailing)
                                        Text(value)
                                            .font(.system(.caption2, design: .monospaced))
                                            .textSelection(.enabled)
                                            .lineLimit(2)
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }
                }

                // Labels
                if !detail.config.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Labels (\(detail.config.labels.count))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        GroupBox {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(
                                    detail.config.labels.sorted(by: { $0.key < $1.key }),
                                    id: \.key
                                ) { key, value in
                                    HStack(alignment: .top, spacing: 8) {
                                        Text(key)
                                            .font(.system(.caption2, design: .monospaced))
                                            .foregroundStyle(.secondary)
                                        Text(value)
                                            .font(.system(.caption2, design: .monospaced))
                                            .textSelection(.enabled)
                                    }
                                }
                            }
                            .padding(4)
                        }
                    }
                }
            }
        } else if isLoadingInspect {
            ProgressView("Loading image details...")
                .font(.caption)
        }
    }

    // MARK: - Actions

    @ViewBuilder
    private var actionsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Actions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                Button {
                    Task { await imageVM.pushImage(image.reference) }
                } label: {
                    Label("Push to Registry", systemImage: "arrow.up.circle")
                }
                .controlSize(.small)

                Button {
                    imageVM.tagSourceImage = image
                    imageVM.showTagSheet = true
                } label: {
                    Label("Tag", systemImage: "tag")
                }
                .controlSize(.small)

                Button {
                    saveImageToFile()
                } label: {
                    Label("Save to File", systemImage: "square.and.arrow.up")
                }
                .controlSize(.small)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(image.reference, forType: .string)
                } label: {
                    Label("Copy Reference", systemImage: "doc.on.doc")
                }
                .controlSize(.small)

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("container run -d --name my-\(image.repository) \(image.reference)", forType: .string)
                } label: {
                    Label("Copy Run Command", systemImage: "terminal")
                }
                .controlSize(.small)

                Button(role: .destructive) {
                    Task { await imageVM.removeImage(image.id) }
                } label: {
                    Label("Remove", systemImage: "trash")
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func detailRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 100, alignment: .trailing)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private func loadInspect() async {
        isLoadingInspect = true
        defer { isLoadingInspect = false }
        do {
            inspectDetail = try await deps.imageService.inspect(imageID: image.reference)
        } catch {
            AppEventLog.shared.warning("Failed to inspect image '\(image.reference)': \(error.localizedDescription)", source: "Images")
        }
    }

    private func saveImageToFile() {
        let panel = NSSavePanel()
        let safeName = image.repository.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName)-\(image.tag).tar"
        panel.allowedContentTypes = [UTType(filenameExtension: "tar") ?? .data]
        panel.canCreateDirectories = true
        panel.message = "Save \(image.reference) as OCI tar archive"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await imageVM.saveImage(image.reference, to: url.path) }
    }
}
