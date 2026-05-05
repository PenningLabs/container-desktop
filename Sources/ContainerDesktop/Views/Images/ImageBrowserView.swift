import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Image browser view

struct ImageBrowserView: View {
    @Environment(ImageBrowserViewModel.self) private var viewModel
    @State private var sortOrder = [KeyPathComparator(\ImageModel.repository)]
    

    var body: some View {
        @Bindable var vm = viewModel

        VStack(spacing: 0) {
            imageToolbar

            if viewModel.isLoading && viewModel.images.isEmpty {
                ProgressView("Loading images...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.filteredImages.isEmpty {
                imageEmptyState
            } else {
                VSplitView {
                    imageTable
                        .frame(minHeight: 150, idealHeight: 500)

                    // Detail panel (always present to preserve divider position)
                    VStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.4))
                            .frame(height: 2)

                        if let selected = viewModel.selectedImage {
                            ImageDetailView(image: selected)
                                .id(selected.id)
                        } else {
                            EmptyStateView(
                                icon: "square.stack.3d.up",
                                message: "No image selected",
                                detail: "Select an image above to view details."
                            )
                        }
                    }
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                    .frame(minHeight: 150, idealHeight: 170)
                }
            }
        }
        .task {
            await viewModel.loadImages()
        }
        .alert("Error", isPresented: .constant(viewModel.error != nil)) {
            Button("OK") { viewModel.error = nil }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
        .confirmationDialog(
            "Prune unused images?",
            isPresented: .init(
                get: { viewModel.showPruneConfirmation },
                set: { viewModel.showPruneConfirmation = $0 }
            )
        ) {
            Button("Prune dangling images") {
                Task { await viewModel.pruneImages(all: false) }
            }
            Button("Prune all unused images", role: .destructive) {
                Task { await viewModel.pruneImages(all: true) }
            }
        } message: {
            Text("Dangling removes images with no tags. All unused also removes images not referenced by any container.")
        }
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var imageToolbar: some View {
        @Bindable var vm = viewModel
        HStack(spacing: 12) {
            Text("Images")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            if viewModel.isPushing {
                HStack(spacing: 6) {
                    ProgressView().scaleEffect(0.6)
                    Text("Pushing \(viewModel.pushReference)...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Text("\(viewModel.images.count) images · \(Formatters.bytes(viewModel.totalImageSize))")
                .font(.caption)
                .foregroundStyle(.secondary)

            TextField("Filter...", text: $vm.filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 160)

            Button {
                Task { await viewModel.loadImages() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh")

            Button {
                viewModel.showPruneConfirmation = true
            } label: {
                Image(systemName: "trash.circle")
            }
            .help("Prune unused images")

            Button {
                viewModel.showRegistrySheet = true
            } label: {
                Label("Registry", systemImage: "person.badge.key")
            }
            .help("Registry login/logout")

            Button {
                viewModel.showPullSheet = true
            } label: {
                Label("Pull", systemImage: "arrow.down.circle")
            }
            .help("Pull image from registry")

            Button {
                loadImageFromFile()
            } label: {
                Label("Load", systemImage: "square.and.arrow.down")
            }
            .help("Load image from OCI tar archive")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private func loadImageFromFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select an OCI tar archive to import"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.loadImage(from: url.path) }
    }

    private func saveImageToFile(_ image: ImageModel) {
        let panel = NSSavePanel()
        let safeName = image.repository.replacingOccurrences(of: "/", with: "-")
        panel.nameFieldStringValue = "\(safeName)-\(image.tag).tar"
        panel.allowedContentTypes = [UTType(filenameExtension: "tar") ?? .data]
        panel.canCreateDirectories = true
        panel.message = "Save \(image.reference) as OCI tar archive"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task { await viewModel.saveImage(image.reference, to: url.path) }
    }

    // MARK: - Table

    @ViewBuilder
    private var imageTable: some View {
        @Bindable var vm = viewModel
        let sorted = viewModel.filteredImages.sorted(using: sortOrder)
        Table(sorted, selection: $vm.selectedImageID, sortOrder: $sortOrder) {
            TableColumn("Repository", value: \.repository) { image in
                HStack(spacing: 8) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(image.repository)
                            .fontWeight(.medium)
                        Text(image.digest.prefix(20) + "...")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            .width(min: 150, ideal: 250)

            TableColumn("Tag", value: \.tag) { image in
                Text(image.tag)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.tertiary.opacity(0.2))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .font(.system(.caption, design: .monospaced))
            }
            .width(min: 60, ideal: 100)

            TableColumn("Size", value: \.size) { image in
                Text(image.displaySize)
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .width(70)

            TableColumn("Arch", value: \.architecture) { image in
                ArchBadge(architecture: image.architecture)
            }
            .width(60)

            TableColumn("OS", value: \.os) { image in
                Text(image.os)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .width(50)

            TableColumn("Actions") { image in
                Button(role: .destructive) {
                    Task { await viewModel.removeImage(image.id) }
                } label: {
                    Image(systemName: "trash")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Remove image")
            }
            .width(50)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first, let image = viewModel.images.first(where: { $0.id == id }) {
                Button("Copy Reference") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(image.reference, forType: .string)
                }
                Divider()
                Button("Tag...") {
                    viewModel.tagSourceImage = image
                    viewModel.showTagSheet = true
                }
                Button("Push to Registry") {
                    Task { await viewModel.pushImage(image.reference) }
                }
                .disabled(viewModel.isPushing)
                Button("Save to File...") {
                    saveImageToFile(image)
                }
                Divider()
                Button("Remove", role: .destructive) {
                    Task { await viewModel.removeImage(id) }
                }
            }
        }
    }

    // MARK: - Empty state

    @ViewBuilder
    private var imageEmptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "square.stack.3d.up")
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)

            if viewModel.filterText.isEmpty {
                Text("No images")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("Pull an image from a container registry to get started.")
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                Button("Pull Image") {
                    viewModel.showPullSheet = true
                }
                .buttonStyle(.borderedProminent)
            } else {
                Text("No matching images")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Image pull sheet

struct ImagePullSheet: View {
    @Environment(ImageBrowserViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var reference: String = ""
    @State private var selectedPlatform: PlatformOption = .default

    enum PlatformOption: String, CaseIterable {
        case `default` = "Default (arm64)"
        case arm64     = "Linux arm64"
        case amd64     = "Linux amd64 (Rosetta)"

        var spec: PlatformSpec? {
            switch self {
            case .default: return nil
            case .arm64:   return .linuxArm64
            case .amd64:   return .linuxAmd64
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Pull image")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Cancel") {
                    viewModel.cancelPull()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                LabeledContent("Image reference") {
                    TextField("e.g. nginx:latest, ubuntu:22.04", text: $reference)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            if !reference.isEmpty {
                                startPull()
                            }
                        }
                }

                LabeledContent("Platform") {
                    Picker("", selection: $selectedPlatform) {
                        ForEach(PlatformOption.allCases, id: \.self) { opt in
                            Text(opt.rawValue).tag(opt)
                        }
                    }
                    .frame(width: 220)
                }

                // Progress area
                if viewModel.isPulling {
                    VStack(alignment: .leading, spacing: 8) {
                        Divider()
                        Text("Pulling layers...")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        ForEach(Array(viewModel.pullProgressEntries.enumerated()), id: \.offset) { _, progress in
                            PullProgressRow(progress: progress)
                        }

                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }

                if let error = viewModel.pullError {
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Quick suggestions
                if !viewModel.isPulling {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Popular images")
                            .font(.caption)
                            .foregroundStyle(.tertiary)

                        FlowLayout(spacing: 6) {
                            ForEach(popularImages, id: \.self) { img in
                                Button(img) { reference = img }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                    }
                }
            }
            .padding(20)

            Spacer()
            Divider()

            // Footer
            HStack {
                if viewModel.isPulling {
                    Button("Cancel Pull") { viewModel.cancelPull() }
                }
                Spacer()
                Button("Pull") { startPull() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(reference.trimmingCharacters(in: .whitespaces).isEmpty || viewModel.isPulling)
                    .buttonStyle(.borderedProminent)
            }
            .padding(20)
        }
        .frame(width: 480, height: 460)
    }

    private func startPull() {
        viewModel.pullReference = reference
        viewModel.pullPlatform = selectedPlatform.spec
        Task { await viewModel.pullImage() }
    }

    private var popularImages: [String] {
        ["nginx:latest", "alpine:latest", "ubuntu:24.04", "postgres:16", "redis:7-alpine", "node:22-slim"]
    }
}

// MARK: - Pull progress row

struct PullProgressRow: View {
    let progress: PullProgress

    var body: some View {
        HStack(spacing: 8) {
            Text(progress.layer.prefix(12))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)

            if progress.total > 0 {
                ProgressView(value: Double(progress.current), total: Double(progress.total))
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .scaleEffect(0.5)
            }

            Text(progress.status.rawValue)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .trailing)
        }
    }
}

// MARK: - Simple flow layout for tag buttons

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = layoutSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(
                x: bounds.minX + position.x,
                y: bounds.minY + position.y
            ), proposal: .unspecified)
        }
    }

    private func layoutSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var lineHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth && currentX > 0 {
                currentX = 0
                currentY += lineHeight + spacing
                lineHeight = 0
            }
            positions.append(CGPoint(x: currentX, y: currentY))
            lineHeight = max(lineHeight, size.height)
            currentX += size.width + spacing
            maxX = max(maxX, currentX)
        }

        return (CGSize(width: maxX, height: currentY + lineHeight), positions)
    }
}

// MARK: - Registry Login Sheet

struct RegistryLoginSheet: View {
    @Environment(ImageBrowserViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    @State private var server: String = "docker.io"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var isLoggingIn: Bool = false
    @State private var loginError: String?
    @State private var loginSuccess: String?
    @State private var loggedInRegistries: [RegistryLogin] = []
    @State private var isLoadingRegistries: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Registry Login")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            // Logged-in registries
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Logged in to")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Spacer()
                    Button {
                        Task { await refreshRegistries() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.caption2)
                    }
                    .buttonStyle(.borderless)
                    .help("Refresh list")
                }

                if isLoadingRegistries && loggedInRegistries.isEmpty {
                    HStack {
                        ProgressView().scaleEffect(0.7)
                        Text("Checking...").font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                } else if loggedInRegistries.isEmpty {
                    Text("No registries logged in.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(loggedInRegistries) { registry in
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.caption)
                                    .foregroundStyle(.green)

                                VStack(alignment: .leading, spacing: 1) {
                                    Text(registry.displayName)
                                        .font(.system(.caption, design: .monospaced))
                                        .fontWeight(.medium)
                                    HStack(spacing: 6) {
                                        Text(registry.username)
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                        if let time = registry.relativeLoginTime {
                                            Text("·")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                            Text(time)
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Spacer()

                                Button("Logout") {
                                    Task { await logoutRegistry(registry.hostname) }
                                }
                                .controlSize(.mini)
                                .disabled(isLoggingIn)
                            }
                        }
                    }
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.secondary.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            }

            Divider()

            // Login form
            VStack(alignment: .leading, spacing: 12) {
                Text("Log in to a registry")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)

                LabeledContent("Server") {
                    HStack(spacing: 4) {
                        TextField("docker.io", text: $server)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))

                        Menu {
                            Button("Docker Hub") { server = "docker.io" }
                            Button("GitHub (ghcr.io)") { server = "ghcr.io" }
                            Button("Quay.io") { server = "quay.io" }
                            Divider()
                            Button("Custom...") { server = "" }
                        } label: {
                            Image(systemName: "chevron.down")
                                .font(.caption)
                        }
                        .menuStyle(.borderlessButton)
                        .menuIndicator(.hidden)
                        .frame(width: 28)
                    }
                }

                LabeledContent("Username") {
                    TextField("username", text: $username)
                        .textFieldStyle(.roundedBorder)
                }

                LabeledContent("Password") {
                    SecureField("password or access token", text: $password)
                        .textFieldStyle(.roundedBorder)
                }

                HStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Text("Credentials are stored in your macOS Keychain by the container CLI.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            if let error = loginError {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.caption)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let success = loginSuccess {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.caption)
                    Text(success)
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack {
                Spacer()

                Button("Login") {
                    Task { await login() }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canLogin || isLoggingIn)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
        .task {
            await refreshRegistries()
        }
    }

    private var canLogin: Bool {
        !server.trimmingCharacters(in: .whitespaces).isEmpty &&
        !username.trimmingCharacters(in: .whitespaces).isEmpty &&
        !password.isEmpty
    }

    private func login() async {
        isLoggingIn = true
        loginError = nil
        loginSuccess = nil
        defer { isLoggingIn = false }

        let targetServer = server.trimmingCharacters(in: .whitespaces)
        let targetUsername = username.trimmingCharacters(in: .whitespaces)

        do {
            try await viewModel.registryLogin(
                server: targetServer,
                username: targetUsername,
                password: password
            )
            // Success: clear password but KEEP server/username and success banner visible
            loginSuccess = "Logged in to \(targetServer) as \(targetUsername)"
            password = ""
            await refreshRegistries()
        } catch {
            // Failure: clear only the error-related success state
            loginError = error.localizedDescription
        }
    }

    private func logoutRegistry(_ registry: String) async {
        isLoggingIn = true
        loginError = nil
        loginSuccess = nil
        defer { isLoggingIn = false }

        do {
            try await viewModel.registryLogout(server: registry)
            loginSuccess = "Logged out from \(registry)"
            await refreshRegistries()
        } catch {
            loginError = error.localizedDescription
        }
    }

    private func refreshRegistries() async {
        isLoadingRegistries = true
        defer { isLoadingRegistries = false }
        loggedInRegistries = await viewModel.listLoggedInRegistries()
    }
}

// MARK: - Image Tag Sheet

struct ImageTagSheet: View {
    @Environment(ImageBrowserViewModel.self) private var viewModel
    @Environment(\.dismiss) private var dismiss

    let sourceImage: ImageModel
    @State private var newTag: String = ""
    @State private var isTagging: Bool = false

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Tag Image")
                    .font(.title3)
                    .fontWeight(.medium)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Source") {
                    Text(sourceImage.reference)
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                LabeledContent("New tag") {
                    TextField("e.g. ghcr.io/user/app:v1.0", text: $newTag)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                }

                Text("The new tag creates an additional reference to the same image. The original reference remains unchanged.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            HStack {
                Spacer()
                Button("Tag") {
                    Task {
                        isTagging = true
                        await viewModel.tagImage(source: sourceImage.reference, target: newTag.trimmingCharacters(in: .whitespaces))
                        isTagging = false
                        dismiss()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty || isTagging)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 460)
    }
}
