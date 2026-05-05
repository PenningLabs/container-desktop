import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(SystemViewModel.self) private var systemVM
    @Environment(DependencyContainer.self) private var deps

    @AppStorage("autoRefreshInterval") private var autoRefreshInterval: Double = 5.0
    @AppStorage("maxLogEntries") private var maxLogEntries: Int = 10_000
    @AppStorage("defaultMemoryGB") private var defaultMemoryGB: Double = 1.0
    @AppStorage("defaultCPUs") private var defaultCPUs: Int = 4
    @AppStorage("defaultArch") private var defaultArch: String = "arm64"

    var body: some View {
        TabView {
            generalTab
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            cliTab
                .tabItem {
                    Label("CLI", systemImage: "terminal.fill")
                }

            defaultsTab
                .tabItem {
                    Label("Defaults", systemImage: "slider.horizontal.3")
                }

            propertiesTab
                .tabItem {
                    Label("Properties", systemImage: "list.bullet.rectangle")
                }
        }
        .frame(width: 520, height: 380)
    }

    // MARK: - General tab

    @ViewBuilder
    private var generalTab: some View {
        Form {
            Section("Refresh") {
                HStack {
                    Text("Auto-refresh interval")
                    Spacer()
                    Picker("", selection: $autoRefreshInterval) {
                        Text("2s").tag(2.0)
                        Text("5s").tag(5.0)
                        Text("10s").tag(10.0)
                        Text("30s").tag(30.0)
                    }
                    .frame(width: 100)
                }
            }

            Section("Logs") {
                HStack {
                    Text("Maximum log entries")
                    Spacer()
                    Picker("", selection: $maxLogEntries) {
                        Text("1,000").tag(1_000)
                        Text("5,000").tag(5_000)
                        Text("10,000").tag(10_000)
                        Text("50,000").tag(50_000)
                    }
                    .frame(width: 120)
                }
            }

            // Menu bar extra is currently disabled.
            // Section("Interface") {
            //     Toggle("Show menu bar icon", isOn: $showMenuBarExtra)
            // }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    // MARK: - CLI tab

    @ViewBuilder
    private var cliTab: some View {
        Form {
            Section("Container CLI") {
                HStack {
                    Text("Detected path")
                    Spacer()
                    if systemVM.cliPath != nil {
                        Text(systemVM.cliPath!)
                            .font(.system(.body, design: .monospaced))
                    } else {
                        Text("Not found")
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.red)
                    }
                }

                HStack {
                    Text("Version")
                    Spacer()
                    Text(systemVM.cliVersion ?? "Unknown")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Section("Links") {
                Link("Download container CLI",
                     destination: URL(string: "https://github.com/apple/container/releases")!)
                Link("Homebrew: brew install --cask container",
                     destination: URL(string: "https://github.com/apple/container#install-or-upgrade")!)
            }

            Section("Support") {
                Link(destination: URL(string: "https://github.com/sponsors/PenningLabs")!) {
                    HStack {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.pink)
                        Text("Sponsor Container Desktop on GitHub")
                    }
                }
                Link("Report an issue",
                     destination: URL(string: "https://github.com/PenningLabs/container-desktop/issues")!)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    // MARK: - Defaults tab

    @ViewBuilder
    private var defaultsTab: some View {
        Form {
            Section("Default container settings") {
                HStack {
                    Text("Memory")
                    Spacer()
                    Slider(value: $defaultMemoryGB, in: 0.5...64, step: 0.5)
                        .frame(width: 160)
                    Text("\(defaultMemoryGB, specifier: "%.1f") GB")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }

                HStack {
                    Text("CPUs")
                    Spacer()
                    Slider(value: .init(
                        get: { Double(defaultCPUs) },
                        set: { defaultCPUs = Int($0) }
                    ), in: 1...Double(ProcessInfo.processInfo.processorCount), step: 1)
                        .frame(width: 160)
                    Text("\(defaultCPUs)")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60, alignment: .trailing)
                }

                Picker("Architecture", selection: $defaultArch) {
                    Text("ARM64 (native)").tag("arm64")
                    Text("AMD64 (Rosetta)").tag("amd64")
                }
            }

            Section {
                Text("These defaults are used when creating new containers. They can be overridden in the creation dialog.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .formStyle(.grouped)
        .padding(12)
    }

    // MARK: - System Properties tab

    @State private var systemProperties: [SystemProperty] = []
    @State private var isLoadingProperties: Bool = false
    @State private var editingPropertyID: String? = nil
    @State private var editingPropertyValue: String = ""

    @ViewBuilder
    private var propertiesTab: some View {
        propertiesContent
    }

    @ViewBuilder
    private var propertiesContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Container system properties")
                    .font(.headline)
                Spacer()
                Button("Refresh") {
                    Task { await loadProperties() }
                }
                .controlSize(.small)
            }
            .padding(.bottom, 4)

            if isLoadingProperties {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if systemProperties.isEmpty {
                Text("No properties found. Make sure the container system is running.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(systemProperties) { prop in
                            HStack(alignment: .top, spacing: 8) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(prop.id)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                    if !prop.description.isEmpty {
                                        Text(prop.description)
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                            .lineLimit(2)
                                    }
                                }
                                .frame(width: 180, alignment: .leading)

                                if editingPropertyID == prop.id {
                                    HStack(spacing: 4) {
                                        TextField("Value", text: $editingPropertyValue)
                                            .textFieldStyle(.roundedBorder)
                                            .font(.system(.caption, design: .monospaced))
                                            .onSubmit {
                                                Task { await saveProperty(prop.id) }
                                            }
                                        Button("Save") {
                                            Task { await saveProperty(prop.id) }
                                        }
                                        .controlSize(.mini)
                                        Button("Cancel") {
                                            editingPropertyID = nil
                                        }
                                        .controlSize(.mini)
                                    }
                                } else {
                                    HStack(spacing: 4) {
                                        Text(prop.displayValue)
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundStyle(prop.value == nil ? .tertiary : .primary)
                                            .lineLimit(1)

                                        Spacer()

                                        Button {
                                            editingPropertyID = prop.id
                                            editingPropertyValue = prop.value ?? ""
                                        } label: {
                                            Image(systemName: "pencil")
                                                .font(.caption2)
                                        }
                                        .buttonStyle(.borderless)
                                    }
                                }
                            }
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                        }
                    }
                }
            }
        }
        .padding(20)
        .task {
            await loadProperties()
        }
    }

    private func loadProperties() async {
        isLoadingProperties = true
        defer { isLoadingProperties = false }
        do {
            systemProperties = try await deps.propertyService.listProperties()
        } catch {
            systemProperties = []
            AppEventLog.shared.warning("Failed to load system properties: \(error.localizedDescription)", source: "Settings")
        }
    }

    private func saveProperty(_ id: String) async {
        do {
            try await deps.propertyService.setProperty(id, value: editingPropertyValue)
            editingPropertyID = nil
            await loadProperties()
        } catch {
            AppEventLog.shared.error(error, context: "Failed to set property '\(id)'", source: "System")
        }
    }
}
