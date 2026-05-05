import AppKit
import SwiftUI

/// Networks page — sortable table of networks with a detail panel below
/// showing containers attached to the selected network.
struct NetworkMapView: View {
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(DependencyContainer.self) private var deps
    @State private var networks: [NetworkInfo] = []
    @State private var selectedNetworkID: String?
    @State private var sortOrder = [KeyPathComparator(\NetworkInfo.name)]
    @State private var showCreateNetwork: Bool = false
    @State private var newNetworkName: String = ""
    @State private var newNetworkSubnet: String = ""
    @State private var newNetworkSubnetV6: String = ""

    var body: some View {
        VStack(spacing: 0) {
            networkToolbar

            VSplitView {
                // Top: network table
                VStack(spacing: 0) {
                    if networks.isEmpty {
                        EmptyStateView(
                            icon: "network",
                            message: "No networks found",
                            detail: "Networks are created when the container system starts. Click + to create a custom network."
                        )
                    } else {
                        networkTable
                    }
                }
                .frame(minHeight: 150, idealHeight: 500)

                // Bottom: detail panel (always present to preserve divider position)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(height: 2)

                    if let selected = selectedNetwork {
                        NetworkDetailPanel(
                            network: selected,
                            containers: containersOnNetwork(selected.name),
                            onDelete: {
                                Task {
                                    await deleteNetwork(selected.name)
                                    selectedNetworkID = nil
                                }
                            }
                        )
                        .id(selected.id)
                    } else {
                        EmptyStateView(
                            icon: "network",
                            message: "No network selected",
                            detail: "Select a network above to view details."
                        )
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .frame(minHeight: 150, idealHeight: 170)
            }
        }
        .task {
            await containerVM.loadContainers()
            await loadNetworks()
        }
        .sheet(isPresented: $showCreateNetwork) {
            createNetworkSheet
        }
    }

    private var selectedNetwork: NetworkInfo? {
        networks.first { $0.id == selectedNetworkID }
    }

    private func containersOnNetwork(_ networkName: String) -> [ContainerModel] {
        containerVM.containers.filter { $0.networkName == networkName }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var networkToolbar: some View {
        HStack(spacing: 12) {
            Text("Networks")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 6) {
                Text("\(networks.count) networks")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("·")
                    .foregroundStyle(.secondary)
                Text("\(containerVM.containers.filter { $0.ipAddress != nil }.count) connected")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            Button {
                Task {
                    await containerVM.loadContainers()
                    await loadNetworks()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                showCreateNetwork = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Create network")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Network table

    @ViewBuilder
    private var networkTable: some View {
        let sorted = networks.sorted(using: sortOrder)
        Table(sorted, selection: $selectedNetworkID, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { network in
                HStack(spacing: 8) {
                    Circle()
                        .fill(network.isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 8, height: 8)
                    Text(network.name)
                        .fontWeight(.medium)
                }
            }
            .width(min: 100, ideal: 150)

            TableColumn("State", value: \.state) { network in
                Text(network.state.capitalized)
                    .font(.caption)
                    .foregroundStyle(network.isRunning ? .green : .secondary)
            }
            .width(70)

            TableColumn("Mode", value: \.mode) { network in
                if !network.mode.isEmpty {
                    Text(network.mode.uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(60)

            TableColumn("IPv4 Subnet", value: \.subnet) { network in
                Text(network.subnet.isEmpty ? "—" : network.subnet)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 120, ideal: 150)

            TableColumn("Gateway", value: \.gateway) { network in
                Text(network.gateway.isEmpty ? "—" : network.gateway)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 130)

            TableColumn("Containers") { network in
                let count = containersOnNetwork(network.name).count
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(count > 0 ? .primary : .tertiary)
            }
            .width(80)

            TableColumn("Actions") { network in
                if network.name != "default" {
                    Button(role: .destructive) {
                        Task { await deleteNetwork(network.name) }
                    } label: {
                        Image(systemName: "trash")
                            .font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help("Delete network")
                }
            }
            .width(50)
        }
    }

    // MARK: - Create network sheet

    @ViewBuilder
    private var createNetworkSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Create network")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Cancel") { showCreateNetwork = false }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Name") {
                    TextField("e.g. my-network", text: $newNetworkName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                LabeledContent("IPv4 subnet") {
                    TextField("Auto (e.g. 192.168.100.0/24)", text: $newNetworkSubnet)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }

                LabeledContent("IPv6 subnet") {
                    TextField("Auto (e.g. fd00:1234::/64)", text: $newNetworkSubnetV6)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }

                Text("Networks are isolated — containers on different networks cannot communicate. Leave subnets empty for automatic allocation.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Create") {
                    Task {
                        let trimmedName = newNetworkName.trimmingCharacters(in: .whitespaces)
                        do {
                            try await deps.networkService.createNetwork(
                                name: trimmedName,
                                subnet: newNetworkSubnet.isEmpty ? nil : newNetworkSubnet,
                                subnetV6: newNetworkSubnetV6.isEmpty ? nil : newNetworkSubnetV6
                            )
                            newNetworkName = ""
                            newNetworkSubnet = ""
                            newNetworkSubnetV6 = ""
                            showCreateNetwork = false
                            await loadNetworks()
                        } catch {
                            AppEventLog.shared.error(error, context: "Failed to create network '\(trimmedName)'", source: "Network")
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!InputValidation.isValidNetworkName(newNetworkName)
                    || (!newNetworkSubnet.isEmpty && !InputValidation.isValidCIDR(newNetworkSubnet))
                    || (!newNetworkSubnetV6.isEmpty && !InputValidation.isValidCIDR(newNetworkSubnetV6)))
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 420)
    }

    // MARK: - Helpers

    private func loadNetworks() async {
        do {
            networks = try await deps.networkService.listNetworks()
            deps.networkCount = networks.count
        } catch {
            AppEventLog.shared.warning(
                "Could not list networks: \(error.localizedDescription). Network management requires macOS 26 or later.",
                source: "Network"
            )
            networks = []
        }
    }

    private func deleteNetwork(_ name: String) async {
        do {
            try await deps.networkService.deleteNetwork(name: name)
            await loadNetworks()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to delete network '\(name)'", source: "Network")
        }
    }
}

// MARK: - Network detail panel

struct NetworkDetailPanel: View {
    let network: NetworkInfo
    let containers: [ContainerModel]
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header bar
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Circle()
                        .fill(network.isRunning ? Color.green : Color.secondary.opacity(0.4))
                        .frame(width: 10, height: 10)
                    Text(network.name)
                        .font(.headline)
                }

                if !network.mode.isEmpty {
                    Text(network.mode.uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }

                Spacer()

                if network.name != "default" {
                    Button(role: .destructive, action: onDelete) {
                        Label("Delete", systemImage: "trash")
                            .font(.caption)
                    }
                    .controlSize(.small)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    networkInfoSection
                    containersSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var networkInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Network details")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 32) {
                if !network.subnet.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IPv4 Subnet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(network.subnet)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !network.gateway.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gateway")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(network.gateway)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                if !network.ipv6Subnet.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IPv6 Subnet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text(network.ipv6Subnet)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("State")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(network.state.capitalized)
                        .font(.callout)
                        .foregroundStyle(network.isRunning ? .green : .secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Containers on this network (\(containers.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if containers.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No containers on this network")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Create a container with --network \(network.name) to attach it.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                LazyVGrid(columns: [
                    GridItem(.flexible(), spacing: 12),
                    GridItem(.flexible(), spacing: 12),
                ], spacing: 12) {
                    ForEach(containers) { container in
                        NetworkNodeCard(container: container)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Network node card

struct NetworkNodeCard: View {
    let container: ContainerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(container.status == .running ? Color.green : Color.secondary.opacity(0.4))
                    .frame(width: 10, height: 10)
                Text(container.name)
                    .font(.callout)
                    .fontWeight(.medium)
                    .lineLimit(1)
                Spacer()
                ArchBadge(architecture: container.architecture)
            }

            if let ip = container.ipAddress {
                HStack(spacing: 6) {
                    Image(systemName: "network")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(ip)
                        .font(.system(.title3, design: .monospaced))
                        .fontWeight(.medium)
                        .textSelection(.enabled)
                }
            } else {
                Text("No IP assigned")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            if let dns = container.dnsDomain {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(container.name).\(dns)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }

            Divider()

            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Text(container.image)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
        .padding(14)
        .background(container.status == .running ? Color.green.opacity(0.04) : Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(
                    container.status == .running ? Color.green.opacity(0.3) : Color.secondary.opacity(0.15),
                    lineWidth: 0.5
                )
        )
    }
}
