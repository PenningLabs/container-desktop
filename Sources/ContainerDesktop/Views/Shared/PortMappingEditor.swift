import SwiftUI

/// Reusable editor for managing port forwarding rules.
/// Used in both ContainerCreateSheet and ContainerEditSheet.
struct PortMappingEditor: View {
    @Binding var portMappings: [PortMapping]
    @Binding var socketMappings: [SocketMapping]

    @State private var showAddPort: Bool = false
    @State private var showAddSocket: Bool = false

    // New port form state
    @State private var newHostIP: String = ""
    @State private var newHostPort: String = ""
    @State private var newContainerPort: String = ""
    @State private var newProtocol: PortProtocol = .tcp

    // New socket form state
    @State private var newSocketHost: String = ""
    @State private var newSocketContainer: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Port forwarding")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // Existing port mappings
            if !portMappings.isEmpty {
                VStack(spacing: 4) {
                    ForEach(portMappings) { mapping in
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.right.arrow.left")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(mapping.displayString)
                                .font(.system(.caption, design: .monospaced))

                            Spacer()

                            Button {
                                portMappings.removeAll { $0.id == mapping.id }
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

            // Existing socket mappings
            if !socketMappings.isEmpty {
                VStack(spacing: 4) {
                    ForEach(socketMappings) { mapping in
                        HStack(spacing: 8) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            Text(mapping.displayString)
                                .font(.system(.caption, design: .monospaced))
                                .lineLimit(1)

                            Spacer()

                            Button {
                                socketMappings.removeAll { $0.id == mapping.id }
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

            // Add port inline form
            if showAddPort {
                addPortForm
            }

            // Add socket inline form
            if showAddSocket {
                addSocketForm
            }

            // Add buttons
            HStack(spacing: 8) {
                Button {
                    showAddPort.toggle()
                    showAddSocket = false
                } label: {
                    Label("Add port", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)

                Button {
                    showAddSocket.toggle()
                    showAddPort = false
                } label: {
                    Label("Add socket", systemImage: "plus.circle")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }

            if portMappings.isEmpty && socketMappings.isEmpty && !showAddPort && !showAddSocket {
                Text("No port forwarding configured. Each container has its own IP address, so ports are directly accessible without mapping.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Add port form

    @ViewBuilder
    private var addPortForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Host IP (optional)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("127.0.0.1", text: $newHostIP)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 110)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Host port")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("8080", text: $newHostPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70)
                }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Container port")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("80", text: $newContainerPort)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                        .frame(width: 70)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("Protocol")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Picker("", selection: $newProtocol) {
                        Text("TCP").tag(PortProtocol.tcp)
                        Text("UDP").tag(PortProtocol.udp)
                    }
                    .frame(width: 70)
                }
            }

            HStack(spacing: 8) {
                Button("Add") {
                    addPort()
                }
                .controlSize(.small)
                .disabled(!isPortValid)

                Button("Cancel") {
                    showAddPort = false
                    clearPortForm()
                }
                .controlSize(.small)

                if !isPortValid && (!newHostPort.isEmpty || !newContainerPort.isEmpty) {
                    Text("Enter valid port numbers (1-65535)")
                        .font(.caption2)
                        .foregroundStyle(.red)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Add socket form

    @ViewBuilder
    private var addSocketForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Host socket path")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("/tmp/mysql.sock", text: $newSocketHost)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }

                Image(systemName: "arrow.right")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 14)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Container socket path")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    TextField("/run/mysqld/mysqld.sock", text: $newSocketContainer)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.caption, design: .monospaced))
                }
            }

            HStack(spacing: 8) {
                Button("Add") {
                    addSocket()
                }
                .controlSize(.small)
                .disabled(newSocketHost.isEmpty || newSocketContainer.isEmpty)

                Button("Cancel") {
                    showAddSocket = false
                    clearSocketForm()
                }
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private var isPortValid: Bool {
        guard let hp = Int(newHostPort), let cp = Int(newContainerPort) else { return false }
        return hp > 0 && hp <= 65535 && cp > 0 && cp <= 65535
    }

    private func addPort() {
        guard let hp = Int(newHostPort), let cp = Int(newContainerPort) else { return }
        let mapping = PortMapping(
            hostIP: newHostIP.trimmingCharacters(in: .whitespaces),
            hostPort: hp,
            containerPort: cp,
            protocol_: newProtocol
        )
        portMappings.append(mapping)
        clearPortForm()
        showAddPort = false
    }

    private func addSocket() {
        let mapping = SocketMapping(
            hostPath: newSocketHost.trimmingCharacters(in: .whitespaces),
            containerPath: newSocketContainer.trimmingCharacters(in: .whitespaces)
        )
        socketMappings.append(mapping)
        clearSocketForm()
        showAddSocket = false
    }

    private func clearPortForm() {
        newHostIP = ""
        newHostPort = ""
        newContainerPort = ""
        newProtocol = .tcp
    }

    private func clearSocketForm() {
        newSocketHost = ""
        newSocketContainer = ""
    }
}
