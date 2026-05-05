import Foundation

/// DNS domain management service.
/// Uses `container system dns` CLI commands.
///
/// Note: `dns create` and `dns delete` require root privileges.
/// We use AppleScript's `do shell script with administrator privileges`
/// to prompt the user for their password via the standard macOS dialog.
///
/// **Security**: Because the AppleScript path passes through a shell,
/// all arguments are validated against a strict allow-list and escaped
/// before interpolation.  See `InputValidation` for the rules.
final class CLIDNSService: Sendable {

    private let cli: CLIBridge
    private let cliPath: String

    init(cli: CLIBridge, cliPath: String) {
        self.cli = cli
        self.cliPath = cliPath
    }

    /// List all registered DNS domains.
    func listDomains() async throws -> [String] {
        // `container system dns list --format json` returns a simple array: ["test", "other"]
        let result = try await cli.run(["system", "dns", "list", "--format", "json"])
        if result.succeeded,
           let data = result.stdout.data(using: .utf8),
           let domains = try? JSONSerialization.jsonObject(with: data) as? [String] {
            return domains
        }

        // Fallback to plain text parsing if JSON format isn't supported
        let output = try await cli.runOrThrow(["system", "dns", "list"])
        return output
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.uppercased() != "DOMAIN" }
    }

    /// Create a new DNS domain. Requires admin privileges.
    func createDomain(_ domain: String) async throws {
        let trimmed = domain.trimmingCharacters(in: .whitespaces).lowercased()

        // Strict validation — domain names are alphanumeric + hyphens only
        guard InputValidation.isValidDNSDomain(trimmed) else {
            throw AppError.unknown(
                "Invalid domain name '\(trimmed)'. "
                + "Use only lowercase letters, numbers, and hyphens (e.g. 'dev', 'test', 'my-app')."
            )
        }

        try await runWithSudo(["system", "dns", "create", trimmed])
        AppEventLog.shared.info("DNS domain '\(trimmed)' created", source: "DNS")
    }

    /// Delete a DNS domain. Requires admin privileges.
    func deleteDomain(_ domain: String) async throws {
        let trimmed = domain.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // Validate even on delete — the domain name came from our listing
        // but defense-in-depth requires we check anyway
        guard InputValidation.isValidDNSDomain(trimmed) else {
            throw AppError.unknown("Invalid domain name for deletion: '\(trimmed)'")
        }

        try await runWithSudo(["system", "dns", "delete", trimmed])
        AppEventLog.shared.info("DNS domain '\(trimmed)' deleted", source: "DNS")
    }

    /// Run a container CLI command with sudo via AppleScript privilege escalation.
    /// This triggers the standard macOS password dialog.
    ///
    /// **Security**: Arguments are validated and escaped before interpolation
    /// into the shell command string.  The CLI path is also validated.
    private func runWithSudo(_ arguments: [String]) async throws {
        // 1. Validate the CLI path itself — must exist and be a known path
        guard InputValidation.isValidPath(cliPath) else {
            throw AppError.unknown("Invalid CLI path: \(cliPath)")
        }

        // 2. Validate each argument against the allow-list
        for arg in arguments {
            guard InputValidation.isSafeCLIArgument(arg) else {
                throw AppError.unknown("Invalid argument for sudo command: '\(arg)'")
            }
        }

        // 3. Build the command with proper escaping.
        //    Each component is:
        //    a) Stripped of any characters outside the shell-safe allow-list
        //    b) Single-quote escaped (closing quote, backslash-quote, opening quote)
        //    c) Wrapped in single quotes
        let escapedComponents = ([cliPath] + arguments).map { component in
            let safe = InputValidation.shellSafe(component)
            let escaped = InputValidation.shellEscapeSingleQuote(safe)
            return "'\(escaped)'"
        }
        let fullCommand = escapedComponents.joined(separator: " ")

        // 4. Build the AppleScript.
        //    The command is inside double-quotes in the AppleScript, so we also
        //    need to escape any backslashes and double-quotes in the command.
        let appleScriptSafe = fullCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(appleScriptSafe)\" with administrator privileges"

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                var error: NSDictionary?
                let appleScript = NSAppleScript(source: script)
                _ = appleScript?.executeAndReturnError(&error)

                if let error = error {
                    let message = error[NSAppleScript.errorMessage] as? String ?? "Unknown error"
                    // User cancelled the password dialog
                    if let errorNum = error[NSAppleScript.errorNumber] as? Int, errorNum == -128 {
                        continuation.resume(throwing: AppError.unknown("Authentication cancelled"))
                    } else {
                        continuation.resume(throwing: AppError.unknown("Sudo command failed: \(message)"))
                    }
                } else {
                    continuation.resume(returning: ())
                }
            }
        }
    }
}
