import SwiftUI

/// Advanced container runtime options for create and edit sheets.
/// Covers SSH forwarding, init process, and nested virtualization.
/// Network-related options (network selection, MAC, DNS) are in the
/// Network section of each sheet.
struct AdvancedContainerOptions: View {
    @Binding var sshForwarding: Bool
    @Binding var initProcess: Bool
    @Binding var virtualization: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Advanced")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textCase(.uppercase)

            // SSH agent forwarding
            Toggle(isOn: $sshForwarding) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SSH agent forwarding")
                        .font(.callout)
                    Text("Mount host SSH authentication socket into the container. Enables git clone of private repos.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)

            // Init process
            Toggle(isOn: $initProcess) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Run init process (PID 1)")
                        .font(.callout)
                    Text("Lightweight init handles signal forwarding and zombie process cleanup.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)

            // Nested virtualization
            Toggle(isOn: $virtualization) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nested virtualization (KVM)")
                        .font(.callout)
                    Text("Enable KVM inside the container. Requires M3 or newer Apple silicon.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .toggleStyle(.checkbox)
        }
    }
}
