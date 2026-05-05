import Foundation

/// Registry and image lifecycle operations.
final class CLIRegistryService: Sendable {

    private let cli: CLIBridge

    init(cli: CLIBridge) {
        self.cli = cli
    }

    // MARK: - Registry auth

    /// Login to a container registry.
    ///
    /// **Security**: The password is passed via stdin using `--password-stdin` rather than
    /// `--password <value>`. Command-line arguments are visible to any local process via
    /// `ps auxww`, which would leak credentials during the (brief) login window.
    /// Stdin avoids this because pipe contents are not exposed to other processes.
    func login(server: String, username: String, password: String) async throws {
        // Validate server and username to prevent argument injection.
        // Server is a registry hostname, username is free-form but can't start with dash.
        guard InputValidation.isSafePositionalArgument(server) else {
            throw AppError.unknown("Invalid registry server: '\(server)'")
        }
        guard InputValidation.isSafePositionalArgument(username) else {
            throw AppError.unknown("Invalid username")
        }

        let args = ["registry", "login", server, "--username", username, "--password-stdin"]

        guard let passwordData = password.data(using: .utf8) else {
            throw AppError.unknown("Invalid password encoding")
        }

        let result = try await cli.runWithStdin(args, stdinData: passwordData)
        guard result.succeeded else {
            throw AppError.cliExecutionFailed(
                command: "registry login \(server)",
                exitCode: result.exitCode,
                stderr: result.stderr
            )
        }
        AppEventLog.shared.info("Logged in to registry '\(server)'", source: "Registry")
    }

    /// Logout from a container registry.
    func logout(server: String) async throws {
        guard InputValidation.isSafePositionalArgument(server) else {
            throw AppError.unknown("Invalid registry server: '\(server)'")
        }
        _ = try await cli.runOrThrow(["registry", "logout", server])
        AppEventLog.shared.info("Logged out from registry '\(server)'", source: "Registry")
    }

    /// List registries that the user is currently logged into with full login info.
    func listLoggedInRegistries() async throws -> [RegistryLogin] {
        // `container registry list --format json` output:
        // [{"id":"registry-1.docker.io","name":"registry-1.docker.io",
        //   "modificationDate":798032893,"creationDate":798032893,
        //   "labels":{},"username":"myuser"}]
        //
        // Dates are macOS absolute time (seconds since 2001-01-01 reference).
        let result = try await cli.run(["registry", "list", "--format", "json"])
        guard result.succeeded else {
            return []
        }

        guard let data = result.stdout.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else {
            return []
        }

        return jsonArray.compactMap { json in
            guard let hostname = json["id"] as? String ?? json["name"] as? String else {
                return nil
            }

            let username = json["username"] as? String ?? ""

            var loggedInAt: Date? = nil
            if let ts = json["modificationDate"] as? Double ?? (json["modificationDate"] as? Int).map(Double.init) {
                loggedInAt = Date(timeIntervalSinceReferenceDate: ts)
            } else if let ts = json["creationDate"] as? Double ?? (json["creationDate"] as? Int).map(Double.init) {
                loggedInAt = Date(timeIntervalSinceReferenceDate: ts)
            }

            return RegistryLogin(
                hostname: hostname,
                username: username,
                loggedInAt: loggedInAt
            )
        }
    }

    // MARK: - Image operations

    /// Push an image to a registry.
    func pushImage(reference: String) async throws {
        guard InputValidation.isValidImageReference(reference) else {
            throw AppError.unknown("Invalid image reference: '\(reference)'")
        }
        _ = try await cli.runOrThrow(["image", "push", reference], timeout: .seconds(300))
        AppEventLog.shared.info("Pushed image '\(reference)'", source: "Images")
    }

    /// Tag an image with a new reference.
    func tagImage(source: String, target: String) async throws {
        guard InputValidation.isValidImageReference(source) else {
            throw AppError.unknown("Invalid source image reference: '\(source)'")
        }
        guard InputValidation.isValidImageReference(target) else {
            throw AppError.unknown("Invalid target image reference: '\(target)'")
        }
        _ = try await cli.runOrThrow(["image", "tag", source, target])
        AppEventLog.shared.info("Tagged '\(source)' as '\(target)'", source: "Images")
    }

    /// Export an image to an OCI tar archive.
    func saveImage(reference: String, outputPath: String) async throws {
        guard InputValidation.isValidImageReference(reference) else {
            throw AppError.unknown("Invalid image reference: '\(reference)'")
        }
        guard InputValidation.isSafePositionalArgument(outputPath) else {
            throw AppError.unknown("Invalid output path")
        }
        _ = try await cli.runOrThrow(
            ["image", "save", reference, "--output", outputPath],
            timeout: .seconds(300)
        )
        AppEventLog.shared.info("Saved image '\(reference)' to \(outputPath)", source: "Images")
    }

    /// Import an image from an OCI tar archive.
    func loadImage(inputPath: String) async throws {
        guard InputValidation.isSafePositionalArgument(inputPath) else {
            throw AppError.unknown("Invalid input path")
        }
        _ = try await cli.runOrThrow(
            ["image", "load", "--input", inputPath],
            timeout: .seconds(300)
        )
        AppEventLog.shared.info("Loaded image from \(inputPath)", source: "Images")
    }

    /// Export a container's filesystem to a tar archive.
    /// The container must be stopped before exporting.
    func exportContainer(name: String, outputPath: String) async throws {
        guard InputValidation.isValidContainerName(name) else {
            throw AppError.unknown("Invalid container name: '\(name)'")
        }
        guard InputValidation.isSafePositionalArgument(outputPath) else {
            throw AppError.unknown("Invalid output path")
        }
        _ = try await cli.runOrThrow(
            ["export", "-o", outputPath, name],
            timeout: .seconds(300)
        )
        AppEventLog.shared.info("Exported container '\(name)' to \(outputPath)", source: "Containers")
    }
}

/// Information about a registry the user is logged into.
struct RegistryLogin: Identifiable, Sendable, Hashable {
    let hostname: String
    let username: String
    let loggedInAt: Date?

    var id: String { hostname }

    /// Display name: map CLI's full hostname to the common shorthand users recognize.
    /// e.g., `registry-1.docker.io` → `docker.io`
    var displayName: String {
        switch hostname {
        case "registry-1.docker.io", "index.docker.io":
            return "docker.io"
        default:
            return hostname
        }
    }

    /// Relative time since login (e.g. "2 hours ago").
    var relativeLoginTime: String? {
        guard let date = loggedInAt else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
