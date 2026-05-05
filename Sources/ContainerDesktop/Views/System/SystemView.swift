import SwiftUI

struct SystemView: View {
    @Environment(SystemViewModel.self) private var viewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                systemHeader
                statusCards
                cliInfoSection
                actionsSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await viewModel.refreshStatus()
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }

    // MARK: - Header

    @ViewBuilder
    private var systemHeader: some View {
        HStack(spacing: 12) {
            Text("System")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.isSystemRunning ? Color.green : Color.red)
                    .frame(width: 10, height: 10)

                Text(viewModel.isSystemRunning ? "Running" : "Stopped")
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundColor(viewModel.isSystemRunning ? Color.green : Color.red)
            }

            Button {
                Task { await viewModel.refreshStatus() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh status")
        }
    }

    // MARK: - Status cards

    @ViewBuilder
    private var statusCards: some View {
        LazyVGrid(columns: [
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
            GridItem(.flexible()),
        ], spacing: 12) {
            MetricCard(
                label: "Containers",
                value: "\(viewModel.systemStatus.containerCount)"
            )
            MetricCard(
                label: "Running",
                value: "\(viewModel.systemStatus.runningCount)",
                accent: .green
            )
            MetricCard(
                label: "Images",
                value: "\(viewModel.systemStatus.imageCount)"
            )
            MetricCard(
                label: "Kernel",
                value: viewModel.systemStatus.kernelVersion ?? "—"
            )
        }
    }

    // MARK: - CLI info

    @ViewBuilder
    private var cliInfoSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("CLI information")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            GroupBox {
                VStack(alignment: .leading, spacing: 8) {
                    infoRow("Path", viewModel.cliPath ?? "Not found")
                    Divider()
                    infoRow("Version", viewModel.cliVersion ?? "Unknown")
                    if let version = viewModel.systemStatus.version {
                        Divider()
                        infoRow("System version", version)
                    }
                }
                .padding(4)
            }
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
                if viewModel.isSystemRunning {
                    Button {
                        Task { await viewModel.stopSystem() }
                    } label: {
                        Label("Stop System", systemImage: "stop.fill")
                    }
                    .disabled(viewModel.isStoppingSystem)
                } else {
                    Button {
                        Task { await viewModel.startSystem() }
                    } label: {
                        Label("Start System", systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(viewModel.isStartingSystem)
                }

                if viewModel.isStartingSystem || viewModel.isStoppingSystem {
                    ProgressView()
                        .scaleEffect(0.7)
                }
            }

            Text("The container system service must be running before you can manage containers and images.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            Spacer()
        }
    }
}

// MARK: - Metric card

struct MetricCard: View {
    let label: String
    let value: String
    var accent: Color?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2)
                .fontWeight(.medium)
                .foregroundStyle(accent ?? .primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
