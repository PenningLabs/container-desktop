import SwiftUI

/// Dashboard view showing a system-wide overview: resource usage,
/// container status breakdown, and quick actions.
struct DashboardView: View {
    @Binding var navigateTo: SidebarSection?
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(ImageBrowserViewModel.self) private var imageVM
    @Environment(SystemViewModel.self) private var systemVM
    @Environment(DependencyContainer.self) private var deps
    @State private var diskUsage: DiskUsage?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                dashboardHeader
                systemStatusSection
                diskUsageSection
                containerBreakdown
                recentContainersSection
                quickActions
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await containerVM.loadContainers()
            await imageVM.loadImages()
            await systemVM.refreshStatus()
            diskUsage = try? await deps.systemService.diskUsage()
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var dashboardHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.title3)
                    .fontWeight(.medium)

                if systemVM.isSystemRunning {
                    Text("System is running")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Text("System is stopped")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Spacer()

            Button {
                Task {
                    await containerVM.loadContainers()
                    await imageVM.loadImages()
                    await systemVM.refreshStatus()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh all")
        }
    }

    // MARK: - System status cards

    @ViewBuilder
    private var systemStatusSection: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
            MetricCard(
                label: "Containers",
                value: "\(containerVM.containers.count)"
            )
            MetricCard(
                label: "Running",
                value: "\(containerVM.runningCount)",
                accent: .green
            )
            MetricCard(
                label: "Images",
                value: "\(imageVM.images.count)"
            )
            MetricCard(
                label: "Disk (images)",
                value: Formatters.bytes(imageVM.totalImageSize)
            )
        }
    }

    // MARK: - Disk usage

    @ViewBuilder
    private var diskUsageSection: some View {
        if let du = diskUsage {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Disk usage")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Text("Total: \(Formatters.bytes(du.total))")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.secondary)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    DiskUsageCard(
                        label: "Images",
                        icon: "square.stack.3d.up.fill",
                        count: du.images.count,
                        size: du.images.size,
                        reclaimable: du.images.reclaimable,
                        color: .blue
                    )
                    DiskUsageCard(
                        label: "Containers",
                        icon: "shippingbox.fill",
                        count: du.containers.count,
                        size: du.containers.size,
                        reclaimable: du.containers.reclaimable,
                        color: .green
                    )
                    DiskUsageCard(
                        label: "Volumes",
                        icon: "externaldrive.fill",
                        count: du.volumes.count,
                        size: du.volumes.size,
                        reclaimable: du.volumes.reclaimable,
                        color: .orange
                    )
                    DiskUsageCard(
                        label: "Builder",
                        icon: "hammer.fill",
                        count: du.builder.count,
                        size: du.builder.size,
                        reclaimable: du.builder.reclaimable,
                        color: .purple
                    )
                }
            }
        }
    }

    // MARK: - Container status breakdown

    @ViewBuilder
    private var containerBreakdown: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Container status")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if containerVM.containers.isEmpty {
                Text("No containers yet")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                // Status bar visualization
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        let running = containerVM.runningCount
                        let stopped = containerVM.stoppedCount
                        let total = max(containerVM.containers.count, 1)

                        if running > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.green)
                                .frame(width: geo.size.width * CGFloat(running) / CGFloat(total))
                        }
                        if stopped > 0 {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.secondary.opacity(0.3))
                                .frame(width: geo.size.width * CGFloat(stopped) / CGFloat(total))
                        }
                    }
                }
                .frame(height: 8)
                .clipShape(RoundedRectangle(cornerRadius: 4))

                HStack(spacing: 16) {
                    Label("\(containerVM.runningCount) running", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                    Label("\(containerVM.stoppedCount) stopped", systemImage: "circle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Recent containers

    @ViewBuilder
    private var recentContainersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Running containers")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                Spacer()
                if containerVM.runningCount > 5 {
                    Button {
                        navigateTo = .containers
                    } label: {
                        Text("View all \(containerVM.runningCount)")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                }
            }

            let running = containerVM.containers.filter { $0.status == .running }

            if running.isEmpty {
                Text("No running containers")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                ForEach(running.prefix(5)) { container in
                    DashboardContainerRow(container: container)
                }
            }
        }
    }

    // MARK: - Quick actions

    @ViewBuilder
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quick actions")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 12) {
                ActionButton(
                    title: "New container",
                    icon: "plus.square",
                    action: {
                        containerVM.showCreateSheet = true
                    }
                )

                ActionButton(
                    title: "Pull image",
                    icon: "arrow.down.circle",
                    action: {
                        imageVM.showPullSheet = true
                    }
                )

                if systemVM.isSystemRunning {
                    ActionButton(
                        title: "Stop system",
                        icon: "stop.circle",
                        action: { Task { await systemVM.stopSystem() } }
                    )
                } else {
                    ActionButton(
                        title: "Start system",
                        icon: "play.circle",
                        action: { Task { await systemVM.startSystem() } }
                    )
                }
            }

            // Navigation shortcuts
            HStack(spacing: 12) {
                ActionButton(
                    title: "Containers",
                    icon: "shippingbox",
                    action: { navigateTo = .containers }
                )
                ActionButton(
                    title: "Images",
                    icon: "square.stack.3d.up",
                    action: { navigateTo = .images }
                )
                ActionButton(
                    title: "Networks",
                    icon: "network",
                    action: { navigateTo = .network }
                )
            }
        }
    }
}

// MARK: - Dashboard container row

struct DashboardContainerRow: View {
    let container: ContainerModel

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(container.name)
                    .font(.callout)
                    .fontWeight(.medium)
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if let ip = container.ipAddress {
                Text(ip)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            ArchBadge(architecture: container.architecture)
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

// MARK: - Action button

struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                Text(title)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
        }
        .buttonStyle(.bordered)
    }
}

// MARK: - Disk usage card

struct DiskUsageCard: View {
    let label: String
    let icon: String
    let count: Int
    let size: UInt64
    let reclaimable: UInt64
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(label)
                    .font(.caption)
                    .fontWeight(.medium)
            }

            Text(Formatters.bytes(size))
                .font(.system(.title3, design: .monospaced))
                .fontWeight(.medium)

            HStack(spacing: 8) {
                Text("\(count) items")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if reclaimable > 0 {
                    Text("\(Formatters.bytes(reclaimable)) reclaimable")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(color.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(color.opacity(0.15), lineWidth: 0.5)
        )
    }
}
