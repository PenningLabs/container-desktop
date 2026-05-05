import AppKit
import SwiftUI

/// Menu bar extra content — quick container management without switching windows.
struct MenuBarView: View {
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(SystemViewModel.self) private var systemVM

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // System status header
            HStack(spacing: 8) {
                Circle()
                    .fill(systemVM.isSystemRunning ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(systemVM.isSystemRunning ? "System running" : "System stopped")
                    .font(.caption)

                Spacer()

                if let version = systemVM.cliVersion {
                    Text("v\(version)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            if systemVM.isSystemRunning {
                // Running containers
                if containerVM.containers.filter({ $0.status == .running }).isEmpty {
                    Text("No running containers")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                } else {
                    ForEach(containerVM.containers.filter({ $0.status == .running })) { container in
                        menuContainerRow(container)
                    }
                }

                // Stopped containers (collapsed)
                let stopped = containerVM.containers.filter { $0.status == .stopped }
                if !stopped.isEmpty {
                    Divider()
                    Text("\(stopped.count) stopped")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                }

                Divider()

                // System actions
                Button {
                    Task { await systemVM.stopSystem() }
                } label: {
                    Label("Stop System", systemImage: "stop.fill")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            } else {
                // System not running
                Button {
                    Task { await systemVM.startSystem() }
                } label: {
                    Label("Start System", systemImage: "play.fill")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            }

            Divider()

            Button("Show Window") {
                NSApp.activate(ignoringOtherApps: true)
                if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
                    window.makeKeyAndOrderFront(nil)
                }
            }
            .keyboardShortcut("0", modifiers: [.command])

            Button("Quit Container Desktop") {
                NSApplication.shared.terminate(nil)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
        }
        .frame(width: 260)
        .task {
            await containerVM.loadContainers()
        }
    }

    @ViewBuilder
    private func menuContainerRow(_ container: ContainerModel) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(.green)
                .frame(width: 6, height: 6)

            VStack(alignment: .leading, spacing: 1) {
                Text(container.name)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(container.image)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let ip = container.ipAddress {
                Text(ip)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Button {
                Task { await containerVM.stopContainer(container.id) }
            } label: {
                Image(systemName: "stop.fill")
                    .font(.caption2)
            }
            .buttonStyle(.borderless)
            .help("Stop")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
    }
}
