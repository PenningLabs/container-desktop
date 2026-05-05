import SwiftUI

struct SidebarView: View {
    @Binding var selection: SidebarSection?
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(ImageBrowserViewModel.self) private var imageVM
    @Environment(VolumeViewModel.self) private var volumeVM
    @Environment(DNSViewModel.self) private var dnsVM
    @Environment(DependencyContainer.self) private var deps
    @Environment(SystemViewModel.self) private var systemVM

    var body: some View {
        VStack(spacing: 0) {
            List(SidebarSection.allCases, id: \.self, selection: $selection) { section in
                Label {
                    Text(section.rawValue)
                } icon: {
                    Image(systemName: section.iconName)
                }
                .tag(section)
                .badge(badgeCount(for: section))
            }
            .listStyle(.sidebar)

            systemStatusFooter
        }
    }

    @ViewBuilder
    private var systemStatusFooter: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(systemVM.isSystemRunning ? Color.green : Color.red)
                .frame(width: 8, height: 8)

            Text(systemVM.isSystemRunning ? "System running" : "System stopped")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            if let version = systemVM.cliVersion {
                Text("v\(version)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private func badgeCount(for section: SidebarSection) -> Int {
        switch section {
        case .dashboard:
            return 0
        case .containers:
            return containerVM.containers.count
        case .images:
            return imageVM.images.count
        case .volumes:
            return volumeVM.volumes.count
        case .network:
            return deps.networkCount
        case .dns:
            return dnsVM.domains.count
        case .builder:
            return 0
        case .eventLog:
            return AppEventLog.shared.unreadCount
        case .system:
            return 0
        }
    }
}
