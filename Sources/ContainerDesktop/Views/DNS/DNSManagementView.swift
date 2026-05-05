import SwiftUI

/// DNS domain model for table display.
struct DNSDomainInfo: Identifiable, Sendable {
    var id: String { name }
    let name: String
    var containerCount: Int = 0

    /// The resolver file path on macOS
    var resolverPath: String {
        "/etc/resolver/containerization.\(name)"
    }

    /// Example hostname for a container named "web"
    var exampleHostname: String {
        "web.\(name)"
    }
}

/// DNS Domains page — sortable table with detail panel showing
/// containers using the selected domain and usage examples.
struct DNSManagementView: View {
    @Environment(DNSViewModel.self) private var viewModel
    @Environment(ContainerListViewModel.self) private var containerVM

    @State private var selectedDomainID: String?
    @State private var sortOrder = [KeyPathComparator(\DNSDomainInfo.name)]
    @State private var newDomainName: String = ""

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            dnsToolbar

            VSplitView {
                // Top: domain table
                VStack(spacing: 0) {
                    if viewModel.isLoading && viewModel.domains.isEmpty {
                        ProgressView("Loading DNS domains...")
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if domainInfos.isEmpty {
                        EmptyStateView(
                            icon: "globe",
                            message: "No DNS domains configured",
                            detail: "Create a domain to enable hostname-based container access. Click + to get started."
                        )
                    } else {
                        domainTable
                    }
                }
                .frame(minHeight: 150, idealHeight: 500)

                // Bottom: detail panel (always present to preserve divider position)
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.4))
                        .frame(height: 2)

                    if let selected = selectedDomain {
                        DNSDomainDetailPanel(
                            domain: selected,
                            containers: containersUsingDomain(selected.name),
                            onDelete: { viewModel.confirmDelete(selected.name) }
                        )
                        .id(selected.id)
                    } else {
                        EmptyStateView(
                            icon: "globe",
                            message: "No domain selected",
                            detail: "Select a domain above to view details."
                        )
                    }
                }
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .frame(minHeight: 150, idealHeight: 170)
            }
        }
        .task {
            await viewModel.loadDomains()
        }
        .sheet(isPresented: $vm.showCreateSheet) {
            createDomainSheet
        }
        .confirmationDialog(
            "Delete DNS domain?",
            isPresented: $vm.showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    await viewModel.executeDelete()
                    selectedDomainID = nil
                }
            }
        } message: {
            if let domain = viewModel.domainToDelete {
                Text("Remove DNS domain '\(domain)'? Containers using this domain will no longer be accessible by hostname.")
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

    // MARK: - Data

    private var domainInfos: [DNSDomainInfo] {
        viewModel.domains.map { name in
            DNSDomainInfo(
                name: name,
                containerCount: containersUsingDomain(name).count
            )
        }
    }

    private var selectedDomain: DNSDomainInfo? {
        domainInfos.first { $0.id == selectedDomainID }
    }

    private func containersUsingDomain(_ domain: String) -> [ContainerModel] {
        containerVM.containers.filter { $0.dnsDomain == domain }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var dnsToolbar: some View {
        HStack(spacing: 12) {
            Text("DNS Domains")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            Text("\(viewModel.domains.count) domains")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.loadDomains() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                viewModel.showCreateSheet = true
            } label: {
                Image(systemName: "plus")
            }
            .help("Create DNS domain")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Table

    @ViewBuilder
    private var domainTable: some View {
        let sorted = domainInfos.sorted(using: sortOrder)
        Table(sorted, selection: $selectedDomainID, sortOrder: $sortOrder) {
            TableColumn("Domain", value: \.name) { domain in
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    Text(".\(domain.name)")
                        .font(.system(.body, design: .monospaced))
                        .fontWeight(.medium)
                }
            }
            .width(min: 100, ideal: 180)

            TableColumn("Hostname pattern") { domain in
                Text("*.\(domain.name)")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            .width(min: 100, ideal: 150)

            TableColumn("Containers", value: \.containerCount) { domain in
                Text("\(domain.containerCount)")
                    .font(.caption)
                    .foregroundStyle(domain.containerCount > 0 ? .primary : .tertiary)
            }
            .width(80)

            TableColumn("Resolver") { domain in
                Text(domain.resolverPath)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            .width(min: 180, ideal: 250)

            TableColumn("Actions") { domain in
                Button(role: .destructive) {
                    viewModel.confirmDelete(domain.name)
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Delete domain")
            }
            .width(50)
        }
    }

    // MARK: - Create sheet

    @ViewBuilder
    private var createDomainSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Create DNS domain")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Cancel") { viewModel.showCreateSheet = false }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Domain name") {
                    TextField("e.g. dev, test, local", text: $newDomainName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit {
                            if isValidDomain {
                                Task { await viewModel.createDomain(newDomainName) }
                            }
                        }
                }

                if !newDomainName.isEmpty {
                    Text("Containers will be accessible at **container-name.\(newDomainName.lowercased())**")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                    Text("Creating a DNS domain requires administrator privileges. You'll be prompted for your password.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            HStack {
                Spacer()
                Button("Create") {
                    Task {
                        await viewModel.createDomain(newDomainName)
                        newDomainName = ""
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValidDomain)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var isValidDomain: Bool {
        InputValidation.isValidDNSDomain(newDomainName)
    }
}

// MARK: - DNS domain detail panel

struct DNSDomainDetailPanel: View {
    let domain: DNSDomainInfo
    let containers: [ContainerModel]
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "globe")
                        .foregroundStyle(.blue)
                    Text(".\(domain.name)")
                        .font(.system(.headline, design: .monospaced))
                }

                Spacer()

                Button(role: .destructive, action: onDelete) {
                    Label("Delete", systemImage: "trash")
                        .font(.caption)
                }
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.bar)

            Divider()

            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    domainInfoSection
                    containersSection
                    usageSection
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    @ViewBuilder
    private var domainInfoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Domain details")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            HStack(spacing: 32) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Domain")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(domain.name)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Hostname pattern")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("<container>.\(domain.name)")
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Resolver file")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(domain.resolverPath)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("DNS server")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("127.0.0.1:2053")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var containersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Containers using this domain (\(containers.count))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            if containers.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "shippingbox")
                        .font(.title3)
                        .foregroundStyle(.tertiary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("No containers using this domain")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("Create a container with --dns-domain \(domain.name) to assign it.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                ForEach(containers) { container in
                    HStack(spacing: 12) {
                        Circle()
                            .fill(container.status == .running ? Color.green : Color.secondary.opacity(0.4))
                            .frame(width: 8, height: 8)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(container.name).\(domain.name)")
                                .font(.system(.callout, design: .monospaced))
                                .fontWeight(.medium)
                                .textSelection(.enabled)
                            Text(container.image)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }

                        Spacer()

                        if let ip = container.ipAddress {
                            Text(ip)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        StatusBadge(status: container.status)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var usageSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Usage")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 6) {
                usageRow("Create a container with this domain:",
                         "container run -d --name web --dns-domain \(domain.name) nginx")
                usageRow("Access from your Mac:",
                         "curl http://web.\(domain.name)")
                usageRow("In the app:",
                         "Set DNS Domain to '\(domain.name)' in the Create Container sheet")
                usageRow("Test DNS resolution:",
                         "dig @127.0.0.1 -p 2053 web.\(domain.name)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func usageRow(_ label: String, _ command: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(command)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .padding(6)
                .background(Color.secondary.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
    }
}
