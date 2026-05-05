import AppKit
import SwiftUI

/// Reusable editor for managing volume bind mounts.
/// Used in both ContainerCreateSheet and ContainerEditSheet.
struct MountEditor: View {
    @Binding var mounts: [MountSpec]

    @State private var showAddMount: Bool = false

    // New mount form state
    @State private var newSource: String = ""
    @State private var newDestination: String = ""
    @State private var newReadOnly: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Volume mounts")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Existing mounts
            if !mounts.isEmpty {
                VStack(spacing: 4) {
                    ForEach(Array(mounts.enumerated()), id: \.offset) { index, mount in
                        HStack(spacing: 8) {
                            Image(systemName: "externaldrive.fill")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(mount.source)
                                    .font(.system(.caption, design: .monospaced))
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 8))
                                        .foregroundStyle(.tertiary)
                                    Text(mount.destination)
                                        .font(.system(.caption2, design: .monospaced))
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

                            Button {
                                mounts.remove(at: index)
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color.secondary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }

            // Add mount form
            if showAddMount {
                addMountForm
            }

            // Add button
            Button {
                showAddMount.toggle()
            } label: {
                Label("Add mount", systemImage: "plus.circle")
                    .font(.caption)
            }
            .buttonStyle(.borderless)

            if mounts.isEmpty && !showAddMount {
                Text("Mount host directories or volumes into the container. Useful for sharing code, config files, or persistent data.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Add mount form

    @ViewBuilder
    private var addMountForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Host path")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    HStack(spacing: 4) {
                        TextField("/Users/you/project", text: $newSource)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.caption, design: .monospaced))

                        Button("Browse...") {
                            browseForSource()
                        }
                        .controlSize(.small)
                    }
                }
            }

            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Container path")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("/app", text: $newDestination)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(" ")
                        .font(.caption2)
                    Toggle("Read-only", isOn: $newReadOnly)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                }
            }

            HStack(spacing: 8) {
                Button("Add") {
                    addMount()
                }
                .controlSize(.small)
                .disabled(!isMountValid)

                Button("Cancel") {
                    showAddMount = false
                    clearForm()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private var isMountValid: Bool {
        !newSource.trimmingCharacters(in: .whitespaces).isEmpty &&
        !newDestination.trimmingCharacters(in: .whitespaces).isEmpty &&
        newDestination.hasPrefix("/")
    }

    private func addMount() {
        let mount = MountSpec(
            source: newSource.trimmingCharacters(in: .whitespaces),
            destination: newDestination.trimmingCharacters(in: .whitespaces),
            readOnly: newReadOnly
        )
        mounts.append(mount)
        clearForm()
        showAddMount = false
    }

    private func clearForm() {
        newSource = ""
        newDestination = ""
        newReadOnly = false
    }

    private func browseForSource() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select a file or directory to mount into the container"

        if panel.runModal() == .OK, let url = panel.url {
            newSource = url.path
        }
    }
}
