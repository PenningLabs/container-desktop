import Foundation
import Testing
@testable import ContainerDesktop

// MARK: - Input Validation Tests

@Suite("InputValidation")
struct InputValidationTests {

    // MARK: - Container names

    @Test("Valid container names")
    func validContainerNames() {
        #expect(InputValidation.isValidContainerName("nginx"))
        #expect(InputValidation.isValidContainerName("my-container"))
        #expect(InputValidation.isValidContainerName("web_server"))
        #expect(InputValidation.isValidContainerName("app.v2"))
        #expect(InputValidation.isValidContainerName("a"))
        #expect(InputValidation.isValidContainerName("Container123"))
    }

    @Test("Invalid container names")
    func invalidContainerNames() {
        #expect(!InputValidation.isValidContainerName(""))
        #expect(!InputValidation.isValidContainerName("  "))
        #expect(!InputValidation.isValidContainerName("name with spaces"))
        #expect(!InputValidation.isValidContainerName("name;injection"))
        #expect(!InputValidation.isValidContainerName("name|pipe"))
        #expect(!InputValidation.isValidContainerName("name$var"))
        #expect(!InputValidation.isValidContainerName("name`cmd`"))
        #expect(!InputValidation.isValidContainerName(String(repeating: "a", count: 129)))
    }

    @Test("Sanitize container name")
    func sanitizeContainerName() {
        #expect(InputValidation.sanitizeContainerName("my container!") == "mycontainer")
        #expect(InputValidation.sanitizeContainerName("  web-server  ") == "web-server")
        #expect(InputValidation.sanitizeContainerName("test;rm -rf /") == "testrm-rf")
    }

    // MARK: - DNS domains

    @Test("Valid DNS domains")
    func validDNSDomains() {
        #expect(InputValidation.isValidDNSDomain("dev"))
        #expect(InputValidation.isValidDNSDomain("test"))
        #expect(InputValidation.isValidDNSDomain("my-app"))
        #expect(InputValidation.isValidDNSDomain("prod123"))
        // DNS is case-insensitive (RFC 1035) — validator normalizes to lowercase
        #expect(InputValidation.isValidDNSDomain("UPPERCASE"))
        #expect(InputValidation.isValidDNSDomain("MyDomain"))
    }

    @Test("Invalid DNS domains")
    func invalidDNSDomains() {
        #expect(!InputValidation.isValidDNSDomain(""))
        #expect(!InputValidation.isValidDNSDomain("has spaces"))
        #expect(!InputValidation.isValidDNSDomain("has.dots"))
        #expect(!InputValidation.isValidDNSDomain("-starts-with-hyphen"))
        #expect(!InputValidation.isValidDNSDomain("ends-with-hyphen-"))
        #expect(!InputValidation.isValidDNSDomain("has_underscore"))
        #expect(!InputValidation.isValidDNSDomain("'; rm -rf /; echo '"))
        #expect(!InputValidation.isValidDNSDomain(String(repeating: "a", count: 64)))
    }

    // MARK: - Network names

    @Test("Valid network names")
    func validNetworkNames() {
        #expect(InputValidation.isValidNetworkName("default"))
        #expect(InputValidation.isValidNetworkName("my-network"))
        #expect(InputValidation.isValidNetworkName("staging_net"))
    }

    @Test("Invalid network names")
    func invalidNetworkNames() {
        #expect(!InputValidation.isValidNetworkName(""))
        #expect(!InputValidation.isValidNetworkName("has spaces"))
        #expect(!InputValidation.isValidNetworkName("has.dots"))
        #expect(!InputValidation.isValidNetworkName("injection;cmd"))
    }

    // MARK: - Volume names

    @Test("Valid volume names")
    func validVolumeNames() {
        #expect(InputValidation.isValidVolumeName("data"))
        #expect(InputValidation.isValidVolumeName("my-volume"))
        #expect(InputValidation.isValidVolumeName("db_data.v2"))
    }

    @Test("Invalid volume names")
    func invalidVolumeNames() {
        #expect(!InputValidation.isValidVolumeName(""))
        #expect(!InputValidation.isValidVolumeName("path/traversal"))
        #expect(!InputValidation.isValidVolumeName("injection;cmd"))
    }

    // MARK: - Image references

    @Test("Valid image references")
    func validImageRefs() {
        #expect(InputValidation.isValidImageReference("nginx"))
        #expect(InputValidation.isValidImageReference("nginx:latest"))
        #expect(InputValidation.isValidImageReference("ghcr.io/user/app:v1.2"))
        #expect(InputValidation.isValidImageReference("docker.io/library/alpine:3.19"))
        #expect(InputValidation.isValidImageReference("registry.example.com:5000/my-image@sha256:abcdef"))
    }

    @Test("Invalid image references")
    func invalidImageRefs() {
        #expect(!InputValidation.isValidImageReference(""))
        #expect(!InputValidation.isValidImageReference("image;injection"))
        #expect(!InputValidation.isValidImageReference("image|pipe"))
        #expect(!InputValidation.isValidImageReference("image$(cmd)"))
        #expect(!InputValidation.isValidImageReference("image`cmd`"))
        // Argument injection protection — reject leading dash
        #expect(!InputValidation.isValidImageReference("--flag"))
        #expect(!InputValidation.isValidImageReference("-v"))
        #expect(!InputValidation.isValidImageReference("-vfoo"))
    }

    // MARK: - Positional argument safety

    @Test("Safe positional arguments")
    func safePositionalArgs() {
        #expect(InputValidation.isSafePositionalArgument("container-name"))
        #expect(InputValidation.isSafePositionalArgument("/tmp/file.tar"))
        #expect(InputValidation.isSafePositionalArgument("docker.io/library/nginx:latest"))
        #expect(InputValidation.isSafePositionalArgument("sha256:abcdef"))
    }

    @Test("Unsafe positional arguments (argument injection)")
    func unsafePositionalArgs() {
        #expect(!InputValidation.isSafePositionalArgument(""))
        #expect(!InputValidation.isSafePositionalArgument("   "))
        #expect(!InputValidation.isSafePositionalArgument("-v"))
        #expect(!InputValidation.isSafePositionalArgument("--force"))
        #expect(!InputValidation.isSafePositionalArgument("-rf"))
        #expect(!InputValidation.isSafePositionalArgument("--output"))
    }

    // MARK: - Volume size

    @Test("Valid volume sizes")
    func validVolumeSizes() {
        #expect(InputValidation.isValidVolumeSize("512"))
        #expect(InputValidation.isValidVolumeSize("512M"))
        #expect(InputValidation.isValidVolumeSize("2G"))
        #expect(InputValidation.isValidVolumeSize("1T"))
        #expect(InputValidation.isValidVolumeSize("100K"))
        #expect(InputValidation.isValidVolumeSize("1P"))
        #expect(InputValidation.isValidVolumeSize("1073741824"))
        // Lowercase suffixes
        #expect(InputValidation.isValidVolumeSize("512m"))
        #expect(InputValidation.isValidVolumeSize("2g"))
        #expect(InputValidation.isValidVolumeSize("1t"))
    }

    @Test("Invalid volume sizes")
    func invalidVolumeSizes() {
        #expect(!InputValidation.isValidVolumeSize(""))
        #expect(!InputValidation.isValidVolumeSize("   "))
        #expect(!InputValidation.isValidVolumeSize("abc"))
        #expect(!InputValidation.isValidVolumeSize("G"))
        #expect(!InputValidation.isValidVolumeSize("2.5G"))
        #expect(!InputValidation.isValidVolumeSize("-1G"))
        #expect(!InputValidation.isValidVolumeSize("--size"))
        #expect(!InputValidation.isValidVolumeSize("2GB"))
        #expect(!InputValidation.isValidVolumeSize("2 G"))
        #expect(!InputValidation.isValidVolumeSize("512MiB"))
    }

    // MARK: - Ports

    @Test("Valid ports")
    func validPorts() {
        #expect(InputValidation.isValidPort("1"))
        #expect(InputValidation.isValidPort("80"))
        #expect(InputValidation.isValidPort("443"))
        #expect(InputValidation.isValidPort("8080"))
        #expect(InputValidation.isValidPort("65535"))
    }

    @Test("Invalid ports")
    func invalidPorts() {
        #expect(!InputValidation.isValidPort(""))
        #expect(!InputValidation.isValidPort("0"))
        #expect(!InputValidation.isValidPort("-1"))
        #expect(!InputValidation.isValidPort("99999"))
        #expect(!InputValidation.isValidPort("abc"))
    }

    // MARK: - CIDR subnets

    @Test("Valid CIDR subnets")
    func validCIDR() {
        #expect(InputValidation.isValidCIDR("192.168.1.0/24"))
        #expect(InputValidation.isValidCIDR("10.0.0.0/8"))
        #expect(InputValidation.isValidCIDR("fd00::/64"))
    }

    @Test("Invalid CIDR subnets")
    func invalidCIDR() {
        #expect(!InputValidation.isValidCIDR(""))
        #expect(!InputValidation.isValidCIDR("not-a-subnet"))
        #expect(!InputValidation.isValidCIDR("192.168.1.0"))  // No prefix
    }

    // MARK: - MAC addresses

    @Test("Valid MAC addresses")
    func validMAC() {
        #expect(InputValidation.isValidMAC("02:42:ac:11:00:02"))
        #expect(InputValidation.isValidMAC("AA:BB:CC:DD:EE:FF"))
    }

    @Test("Invalid MAC addresses")
    func invalidMAC() {
        #expect(!InputValidation.isValidMAC(""))
        #expect(!InputValidation.isValidMAC("not-a-mac"))
        #expect(!InputValidation.isValidMAC("02:42:ac:11:00"))  // Too short
        #expect(!InputValidation.isValidMAC("02:42:ac:11:00:02:FF"))  // Too long
    }

    // MARK: - Shell safety

    @Test("Shell safe strips dangerous characters")
    func shellSafe() {
        #expect(InputValidation.shellSafe("normal-text") == "normal-text")
        #expect(InputValidation.shellSafe("'; rm -rf /") == " rm -rf /")
        #expect(InputValidation.shellSafe("test$(cmd)") == "testcmd")
        #expect(InputValidation.shellSafe("test`cmd`") == "testcmd")
        #expect(InputValidation.shellSafe("a&b|c;d") == "abcd")
    }

    @Test("Shell escape single quotes")
    func shellEscape() {
        #expect(InputValidation.shellEscapeSingleQuote("hello") == "hello")
        #expect(InputValidation.shellEscapeSingleQuote("it's") == "it'\\''s")
        #expect(InputValidation.shellEscapeSingleQuote("a'b'c") == "a'\\''b'\\''c")
    }

    // MARK: - Environment variables

    @Test("Valid env vars")
    func validEnvVars() {
        #expect(InputValidation.isValidEnvVar("KEY=value"))
        #expect(InputValidation.isValidEnvVar("MY_VAR=hello world"))
        #expect(InputValidation.isValidEnvVar("PATH=/usr/bin:/bin"))
        #expect(InputValidation.isValidEnvVar("EMPTY="))
    }

    @Test("Invalid env vars")
    func invalidEnvVars() {
        #expect(!InputValidation.isValidEnvVar(""))
        #expect(!InputValidation.isValidEnvVar("no-equals-sign"))
        #expect(!InputValidation.isValidEnvVar("=no-key"))
        #expect(!InputValidation.isValidEnvVar("bad-key=value"))
    }

    // MARK: - Path validation

    @Test("Valid paths")
    func validPaths() {
        #expect(InputValidation.isValidPath("/usr/local/bin"))
        #expect(InputValidation.isValidPath("./relative"))
        #expect(InputValidation.isValidPath("/home/user/data"))
    }

    @Test("Invalid paths")
    func invalidPaths() {
        #expect(!InputValidation.isValidPath(""))
        #expect(!InputValidation.isValidPath("path\0with\0nulls"))
        #expect(!InputValidation.isValidPath(String(repeating: "a", count: 4097)))
    }
}

// MARK: - CLI Bridge Redaction Tests

@Suite("CLIBridge.redactSensitiveArgs")
struct RedactionTests {

    @Test("Redacts -e flag values")
    func redactEnvFlag() {
        let args = ["run", "-d", "-e", "SECRET_KEY=mysecret123", "--name", "web", "nginx"]
        let result = CLIBridge.redactSensitiveArgs(args)
        #expect(result == "run -d -e *** --name web nginx")
    }

    @Test("Redacts --env flag values")
    func redactEnvLongFlag() {
        let args = ["run", "--env", "DB_PASSWORD=hunter2", "nginx"]
        let result = CLIBridge.redactSensitiveArgs(args)
        #expect(result == "run --env *** nginx")
    }

    @Test("Redacts multiple env vars")
    func redactMultipleEnvVars() {
        let args = ["run", "-e", "A=1", "-e", "B=secret", "--name", "app", "nginx"]
        let result = CLIBridge.redactSensitiveArgs(args)
        #expect(result == "run -e *** -e *** --name app nginx")
    }

    @Test("Leaves non-env args untouched")
    func noRedactionNeeded() {
        let args = ["image", "list", "--format", "json"]
        let result = CLIBridge.redactSensitiveArgs(args)
        #expect(result == "image list --format json")
    }

    @Test("Handles -e without value")
    func redactBareEnvFlag() {
        let args = ["run", "-e", "NOEQUALS", "nginx"]
        let result = CLIBridge.redactSensitiveArgs(args)
        #expect(result == "run -e *** nginx")
    }

    @Test("Redacts --password flag")
    func redactPassword() {
        let args = ["registry", "login", "docker.io", "--username", "user", "--password", "mysecret"]
        let result = CLIBridge.redactSensitiveArgs(args)
        #expect(result == "registry login docker.io --username user --password ***")
    }
}

// MARK: - Log Entry Serialization Tests

@Suite("LogEntry serialization")
struct LogEntryTests {

    @Test("Round-trip serialization")
    func roundTrip() {
        let entry = LogEntry(
            timestamp: Date(timeIntervalSinceReferenceDate: 700000000),
            source: .stdout,
            message: "Hello world"
        )
        let serialized = entry.serialized
        let deserialized = LogEntry.deserialize(serialized)

        #expect(deserialized != nil)
        #expect(deserialized?.message == "Hello world")
        #expect(deserialized?.source == .stdout)
        #expect(deserialized?.timestamp != nil)
    }

    @Test("Handles nil timestamp")
    func nilTimestamp() {
        let entry = LogEntry(timestamp: nil, source: .stderr, message: "error line")
        let serialized = entry.serialized
        let deserialized = LogEntry.deserialize(serialized)

        #expect(deserialized != nil)
        #expect(deserialized?.message == "error line")
        #expect(deserialized?.source == .stderr)
        #expect(deserialized?.timestamp == nil)
    }

    @Test("Escapes tabs and newlines in message")
    func escapesSpecialChars() {
        let entry = LogEntry(message: "line1\tcolumn2\nline2")
        let serialized = entry.serialized
        #expect(!serialized.contains("\t\t"))  // Should be escaped
        let deserialized = LogEntry.deserialize(serialized)
        #expect(deserialized?.message == "line1\tcolumn2\nline2")
    }

    @Test("Deserialize returns nil for malformed input")
    func malformedInput() {
        #expect(LogEntry.deserialize("") == nil)
        #expect(LogEntry.deserialize("no-tabs-here") == nil)
        #expect(LogEntry.deserialize("one\ttwo") == nil)  // Only 2 parts, need 3
    }
}

// MARK: - ANSI Parser Tests

@Suite("ANSIParser")
struct ANSIParserTests {

    @Test("Plain text with no ANSI codes")
    func plainText() {
        let segments = ANSIParser.parse("Hello world")
        #expect(segments.count == 1)
        #expect(segments[0].text == "Hello world")
        #expect(segments[0].color == nil)
    }

    @Test("Single color code")
    func singleColor() {
        let segments = ANSIParser.parse("\u{1B}[31mError\u{1B}[0m")
        #expect(segments.contains { $0.text == "Error" && $0.color == .red })
    }

    @Test("Bold text")
    func boldText() {
        let segments = ANSIParser.parse("\u{1B}[1mBold\u{1B}[0m")
        #expect(segments.contains { $0.text == "Bold" && $0.bold == true })
    }

    @Test("Mixed colors")
    func mixedColors() {
        let segments = ANSIParser.parse("\u{1B}[32mOK\u{1B}[0m \u{1B}[31mFAIL\u{1B}[0m")
        #expect(segments.contains { $0.text == "OK" && $0.color == .green })
        #expect(segments.contains { $0.text == "FAIL" && $0.color == .red })
    }

    @Test("Empty string")
    func emptyString() {
        let segments = ANSIParser.parse("")
        #expect(segments.isEmpty)
    }

    @Test("Unclosed ANSI sequence")
    func unclosedSequence() {
        // Should not crash on malformed ANSI
        let segments = ANSIParser.parse("before\u{1B}[31mred text")
        #expect(!segments.isEmpty)
    }
}

// MARK: - Image Reference Parser Tests

@Suite("CLIImageService.parseReference")
struct ImageReferenceParserTests {

    @Test("Simple image name")
    func simpleName() {
        let (repo, tag) = CLIImageService.parseReference("alpine")
        #expect(repo == "alpine")
        #expect(tag == "latest")
    }

    @Test("Name with tag")
    func nameWithTag() {
        let (repo, tag) = CLIImageService.parseReference("nginx:1.25")
        #expect(repo == "nginx")
        #expect(tag == "1.25")
    }

    @Test("Full registry reference")
    func fullReference() {
        let (repo, tag) = CLIImageService.parseReference("docker.io/library/nginx:latest")
        // Should strip docker.io/library/ prefix
        #expect(repo == "nginx")
        #expect(tag == "latest")
    }

    @Test("Third-party registry")
    func thirdPartyRegistry() {
        let (repo, tag) = CLIImageService.parseReference("ghcr.io/user/app:v1.2")
        #expect(repo == "ghcr.io/user/app")
        #expect(tag == "v1.2")
    }
}
