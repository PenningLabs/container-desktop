import AppKit
import SwiftUI

/// Navigation sections for the sidebar.
enum SidebarSection: String, CaseIterable, Identifiable {
    case dashboard  = "Dashboard"
    case containers = "Containers"
    case images     = "Images"
    case volumes    = "Volumes"
    case network    = "Networks"
    case dns        = "DNS"
    case builder    = "Builder"
    case eventLog   = "Event Log"
    case system     = "System"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .dashboard:  return "gauge.with.dots.needle.33percent"
        case .containers: return "shippingbox.fill"
        case .images:     return "square.stack.3d.up.fill"
        case .volumes:    return "externaldrive.fill"
        case .network:    return "network"
        case .dns:        return "globe"
        case .builder:    return "hammer.fill"
        case .eventLog:   return "doc.text"
        case .system:     return "gear"
        }
    }
}

// MARK: - App delegate (forces proper activation for SPM executables)

class AppDelegate: NSObject, NSApplicationDelegate {
    /// Set by the App struct so the delegate can clean up on termination.
    var deps: DependencyContainer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NSApp.windows.first?.makeKeyAndOrderFront(nil)
        }

        // Log app startup
        AppEventLog.shared.info("Container Desktop launched", source: "App")

        // Check notification permission
        NotificationManager.shared.checkPermissionStatus()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        NSApp.windows.first?.makeKeyAndOrderFront(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        deps?.cleanup()
    }
}

// MARK: - App entry point (called from ContainerDesktopApp target)

public struct ContainerDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var deps = DependencyContainer()

    public init() {}

    public var body: some Scene {
        // Main window
        WindowGroup {
            ContentView()
                .environment(deps.containerListVM)
                .environment(deps.imageBrowserVM)
                .environment(deps.systemVM)
                .environment(deps.logStreamVM)
                .environment(deps.volumeVM)
                .environment(deps.dnsVM)
                .environment(deps)
                .frame(minWidth: 800, minHeight: 500)
                .task {
                    // Give the AppDelegate access for cleanup on termination
                    appDelegate.deps = deps

                    // Initial setup on launch
                    await deps.systemVM.detectCLI()
                    await deps.systemVM.refreshStatus()
                    deps.systemVM.startPeriodicRefresh()
                    // Pre-load data for sidebar badge counts
                    await deps.volumeVM.loadVolumes()
                    await deps.dnsVM.loadDomains()
                    await deps.loadNetworkCount()
                }
        }
        .defaultSize(width: 1100, height: 720)
        .commands {
            ContainerCommands(deps: deps)
        }

        // Menu bar extra — quick access without switching windows
        // Disabled for now; uncomment to restore the menu bar icon.
        // MenuBarExtra("Container Desktop", systemImage: "shippingbox.fill") {
        //     MenuBarView()
        //         .environment(deps.containerListVM)
        //         .environment(deps.systemVM)
        // }

        // Settings window
        Settings {
            SettingsView()
                .environment(deps.systemVM)
                .environment(deps)
        }
    }
}

// MARK: - Main content view

struct ContentView: View {
    // MUST be optional for List(selection:) to work on macOS
    @State private var selectedSection: SidebarSection? = .dashboard
    @Environment(SystemViewModel.self) private var systemVM
    @Environment(ContainerListViewModel.self) private var containerVM
    @Environment(ImageBrowserViewModel.self) private var imageVM

    var body: some View {
        @Bindable var cvm = containerVM
        @Bindable var ivm = imageVM

        Group {
            if systemVM.cliPath == nil {
                CLINotFoundView()
            } else {
                NavigationSplitView {
                    SidebarView(selection: $selectedSection)
                        .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
                } detail: {
                    switch selectedSection {
                    case .dashboard:
                        DashboardView(navigateTo: $selectedSection)
                    case .containers:
                        ContainerListView()
                    case .images:
                        ImageBrowserView()
                    case .volumes:
                        VolumeListView()
                    case .network:
                        NetworkMapView()
                    case .dns:
                        DNSManagementView()
                    case .builder:
                        BuilderView()
                    case .eventLog:
                        AppEventLogView()
                    case .system:
                        SystemView()
                    case nil:
                        DashboardView(navigateTo: $selectedSection)
                    }
                }
            }
        }
        // Sheets at the top level so they work from any section
        .sheet(isPresented: $cvm.showCreateSheet) {
            ContainerCreateSheet()
        }
        .sheet(isPresented: $ivm.showPullSheet) {
            ImagePullSheet()
        }
        .sheet(isPresented: $ivm.showRegistrySheet) {
            RegistryLoginSheet()
        }
        .sheet(isPresented: $ivm.showTagSheet) {
            if let image = imageVM.tagSourceImage {
                ImageTagSheet(sourceImage: image)
            }
        }
        .sheet(isPresented: $cvm.showEditSheet) {
            if let container = containerVM.containerToEdit {
                ContainerEditSheet(container: container)
            }
        }
    }
}

// MARK: - CLI not found view

struct CLINotFoundView: View {
    @Environment(DependencyContainer.self) private var deps

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Container CLI not found")
                .font(.title2)
                .fontWeight(.medium)

            Text("Install the container CLI from GitHub releases or via Homebrew:")
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 8) {
                Label("brew install --cask container", systemImage: "terminal.fill")
                    .font(.system(.body, design: .monospaced))
                    .padding(8)
                    .background(.tertiary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }

            Text("Or download from:")
                .foregroundStyle(.secondary)

            Link("github.com/apple/container/releases",
                 destination: URL(string: "https://github.com/apple/container/releases")!)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - App commands

struct ContainerCommands: Commands {
    let deps: DependencyContainer

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Container...") {
                deps.containerListVM.showCreateSheet = true
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("Pull Image...") {
                deps.imageBrowserVM.showPullSheet = true
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])

            Button("Registry Login...") {
                deps.imageBrowserVM.showRegistrySheet = true
            }
            .keyboardShortcut("l", modifiers: [.command, .shift])

            Divider()

            Button("Refresh All") {
                Task {
                    await deps.containerListVM.loadContainers()
                    await deps.imageBrowserVM.loadImages()
                    await deps.systemVM.refreshStatus()
                    await deps.volumeVM.loadVolumes()
                    await deps.dnsVM.loadDomains()
                }
            }
            .keyboardShortcut("r", modifiers: [.command])
        }

        CommandMenu("Containers") {
            Button("Stop All Running") {
                Task {
                    for container in deps.containerListVM.containers where container.status == .running {
                        await deps.containerListVM.stopContainer(container.id)
                    }
                }
            }
            .keyboardShortcut(".", modifiers: [.command, .shift])

            Button("Prune Stopped Containers") {
                Task {
                    do {
                        _ = try await deps.containerService.pruneContainers()
                        AppEventLog.shared.info("Pruned stopped containers", source: "Containers")
                    } catch {
                        AppEventLog.shared.error(error, context: "Prune stopped containers", source: "Containers")
                    }
                    await deps.containerListVM.loadContainers()
                }
            }

            Divider()

            Button("Start System") {
                Task { await deps.systemVM.startSystem() }
            }

            Button("Stop System") {
                Task { await deps.systemVM.stopSystem() }
            }
        }

        CommandGroup(replacing: .help) {
            Link("Container CLI Documentation",
                 destination: URL(string: "https://github.com/apple/container/blob/main/docs/command-reference.md")!)
            Link("Container Desktop on GitHub",
                 destination: URL(string: "https://github.com/PenningLabs/container-desktop")!)
            Divider()
            Link("Report an Issue",
                 destination: URL(string: "https://github.com/PenningLabs/container-desktop/issues")!)
        }

        // Remove the Edit menu — not useful for this app
        CommandGroup(replacing: .pasteboard) { }
        CommandGroup(replacing: .undoRedo) { }
    }
}
