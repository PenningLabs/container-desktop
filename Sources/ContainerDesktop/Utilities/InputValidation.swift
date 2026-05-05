import Foundation

// MARK: - Input validation

/// Centralised input validation and sanitisation for all user-provided values
/// that are passed to CLI commands or used in shell contexts.
///
/// **Security model**: The `container` CLI is invoked via `Process.arguments`
/// (array form — no shell interpolation), which is inherently safe from shell
/// injection.  The one exception is `CLIDNSService.runWithSudo()` which uses
/// AppleScript `do shell script` and therefore *does* pass through a shell.
/// All values destined for that path must be sanitised with `shellSafe()`.
enum InputValidation {

    // MARK: - Shell safety (for AppleScript sudo path)

    /// Characters allowed in values passed to the AppleScript sudo path.
    /// Anything outside this set is stripped.
    private static let shellSafeCharacters = CharacterSet.alphanumerics
        .union(CharacterSet(charactersIn: "-_./: "))

    /// Sanitise a string for safe inclusion in a shell command.
    /// Strips any character not in the allow-list.
    static func shellSafe(_ input: String) -> String {
        String(input.unicodeScalars.filter { shellSafeCharacters.contains($0) })
    }

    /// Escape a string for safe single-quoting in a shell.
    /// Replaces `'` with `'\''` (end quote, escaped quote, start quote).
    static func shellEscapeSingleQuote(_ input: String) -> String {
        input.replacingOccurrences(of: "'", with: "'\\''")
    }

    // MARK: - Container names

    /// Validate a container name.
    /// Rules: non-empty, alphanumeric + hyphens + underscores + dots, max 128 chars.
    static func isValidContainerName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    /// Sanitise a container name — strip invalid characters.
    static func sanitizeContainerName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return String(name.trimmingCharacters(in: .whitespaces)
            .unicodeScalars.filter { allowed.contains($0) })
    }

    // MARK: - DNS domain names

    /// Validate a DNS domain name.
    /// Rules: non-empty, lowercase alphanumeric + hyphens, no dots/spaces, max 63 chars.
    static func isValidDNSDomain(_ domain: String) -> Bool {
        let trimmed = domain.trimmingCharacters(in: .whitespaces).lowercased()
        guard !trimmed.isEmpty, trimmed.count <= 63 else { return false }
        let allowed = CharacterSet.lowercaseLetters
            .union(.decimalDigits)
            .union(CharacterSet(charactersIn: "-"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return false }
        // Must not start or end with hyphen
        guard !trimmed.hasPrefix("-"), !trimmed.hasSuffix("-") else { return false }
        return true
    }

    // MARK: - Network names

    /// Validate a network name.
    /// Rules: non-empty, alphanumeric + hyphens + underscores, max 128 chars.
    static func isValidNetworkName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Volume names

    /// Validate a volume name.
    /// Rules: non-empty, alphanumeric + hyphens + underscores + dots, max 128 chars.
    static func isValidVolumeName(_ name: String) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 128 else { return false }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        return trimmed.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    // MARK: - Image references

    /// Validate an image reference (e.g. "nginx:latest", "ghcr.io/user/app:v1").
    /// Permissive — allows registry paths, tags, digests.
    static func isValidImageReference(_ ref: String) -> Bool {
        let trimmed = ref.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.count <= 512 else { return false }
        // Reject leading dash — prevents argument injection (e.g. "-v /etc/passwd").
        // OCI references never start with a dash.
        guard !trimmed.hasPrefix("-") else { return false }
        // Must not contain shell-dangerous characters
        let forbidden = CharacterSet(charactersIn: ";&|`$(){}!#\\\"\n\r\t")
        return trimmed.unicodeScalars.allSatisfy { !forbidden.contains($0) }
    }

    /// Reject any string that starts with a dash — prevents CLI argument injection.
    /// Use this defensively before passing user-provided strings as positional
    /// arguments to any CLI command. The Apple `container` CLI, like most
    /// GNU-style CLIs, parses `-x` and `--foo` as flags regardless of position.
    static func isSafePositionalArgument(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !trimmed.hasPrefix("-")
    }

    // MARK: - Volume size

    /// Validate a volume size string (e.g. "512M", "2G", "1073741824").
    /// Accepts digits with an optional K, M, G, T, or P suffix (case-insensitive).
    static func isValidVolumeSize(_ size: String) -> Bool {
        let trimmed = size.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let pattern = #"^\d+[KMGTPkmgtp]?$"#
        return trimmed.range(of: pattern, options: .regularExpression, range: nil, locale: nil) != nil
    }

    // MARK: - Port numbers

    /// Validate a port number string.
    static func isValidPort(_ port: String) -> Bool {
        guard let num = UInt16(port), num >= 1 else { return false }
        return true
    }

    // MARK: - CIDR subnets

    /// Validate a CIDR subnet string (e.g. "192.168.100.0/24").
    static func isValidCIDR(_ cidr: String) -> Bool {
        let trimmed = cidr.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let parts = trimmed.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0, prefix <= 128 else { return false }
        // Validate IP part has only digits, dots, and colons (IPv6)
        let ipAllowed = CharacterSet.decimalDigits.union(CharacterSet(charactersIn: ".:abcdefABCDEF"))
        return parts[0].unicodeScalars.allSatisfy { ipAllowed.contains($0) }
    }

    // MARK: - MAC addresses

    /// Validate a MAC address string (e.g. "02:42:ac:11:00:02").
    static func isValidMAC(_ mac: String) -> Bool {
        let trimmed = mac.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let pattern = "^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$"
        return trimmed.range(of: pattern, options: .regularExpression) != nil
    }

    // MARK: - Environment variables

    /// Validate an environment variable line (KEY=VALUE).
    static func isValidEnvVar(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        guard trimmed.contains("=") else { return false }
        let key = trimmed.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
        // Key must be non-empty and contain only alphanumeric + underscore
        let keyAllowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_"))
        return !key.isEmpty && key.unicodeScalars.allSatisfy { keyAllowed.contains($0) }
    }

    // MARK: - File paths

    /// Validate a file/directory path.
    /// Rejects paths with null bytes or other dangerous characters.
    static func isValidPath(_ path: String) -> Bool {
        guard !path.isEmpty, path.count <= 4096 else { return false }
        // Reject null bytes and other control characters
        return !path.contains("\0") && !path.contains("\n") && !path.contains("\r")
    }

    // MARK: - General CLI argument safety

    /// Check if a string is safe to use as a CLI argument via Process.arguments.
    /// Process.arguments is array-based (no shell), so this is mainly about
    /// preventing excessively long or null-byte-containing strings.
    static func isSafeCLIArgument(_ arg: String) -> Bool {
        guard arg.count <= 4096 else { return false }
        return !arg.contains("\0")
    }
}
