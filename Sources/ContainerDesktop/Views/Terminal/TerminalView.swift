import AppKit
import SwiftUI
import SwiftTerm

/// Full interactive terminal for executing commands inside a running container.
/// Uses SwiftTerm (xterm/VT100 emulator) connected via PTY to
/// `container exec -it <name> /bin/sh`, giving you tab completion,
/// arrow keys, vi, top, colors — everything a real terminal does.
struct TerminalView: View {
    let containerName: String
    @Environment(DependencyContainer.self) private var deps

    var body: some View {
        VStack(spacing: 0) {
            terminalHeader
            Divider()
            ContainerTerminalRepresentable(
                containerName: containerName,
                cliPath: deps.cliBinaryPath
            )
        }
    }

    @ViewBuilder
    private var terminalHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "terminal.fill")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Terminal — \(containerName)")
                .font(.caption)
                .fontWeight(.medium)

            Spacer()

            Text("Interactive shell via container exec")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

// MARK: - NSViewRepresentable wrapper for SwiftTerm

/// Wraps SwiftTerm's `LocalProcessTerminalView` (an AppKit NSView) for use
/// in SwiftUI. Spawns `container exec -it <name> /bin/sh` with a real PTY,
/// giving full interactive terminal capabilities.
struct ContainerTerminalRepresentable: NSViewRepresentable {
    let containerName: String
    let cliPath: String

    func makeNSView(context: Context) -> LocalProcessTerminalView {
        let terminalView = LocalProcessTerminalView(frame: .zero)

        // Configure appearance
        terminalView.configureNativeColors()
        let fontSize: CGFloat = 13
        terminalView.font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)

        // Build environment with TERM set for proper escape sequence handling.
        // SwiftTerm emulates xterm-256color, so the container shell needs to know.
        var env: [String] = []
        // Carry forward essential host environment
        for key in ["PATH", "HOME", "USER", "LANG", "LC_ALL"] {
            if let val = ProcessInfo.processInfo.environment[key] {
                env.append("\(key)=\(val)")
            }
        }
        env.append("TERM=xterm-256color")

        // Try bash first (has readline/arrow key support), fall back to sh.
        // Set TERM inside the container so the shell handles escape sequences properly.
        // We export TERM in the shell command itself since container exec may not support -e.
        let shellCommand = "export TERM=xterm-256color; if command -v bash >/dev/null 2>&1; then exec bash; else exec sh; fi"
        let args = [
            "exec", "-t", "-i",
            containerName, "sh", "-c", shellCommand
        ]

        terminalView.startProcess(
            executable: cliPath,
            args: args,
            environment: env,
            execName: nil
        )

        return terminalView
    }

    func updateNSView(_ nsView: LocalProcessTerminalView, context: Context) {
        // Nothing to update — the terminal manages its own state
    }
}

// MARK: - Old command-based terminal (kept as fallback)

/// Simple command-by-command terminal for when SwiftTerm isn't available
/// or for containers that don't support interactive shells.
struct SimpleTerminalView: View {
    let containerName: String
    @Environment(DependencyContainer.self) private var deps
    @State private var commandHistory: [TerminalEntry] = []
    @State private var currentCommand: String = ""
    @State private var isExecuting: Bool = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            // Output area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(commandHistory) { entry in
                            TerminalEntryView(entry: entry)
                                .id(entry.id)
                        }
                    }
                    .padding(.vertical, 8)
                }
                .onChange(of: commandHistory.count) { _, _ in
                    if let last = commandHistory.last {
                        proxy.scrollTo(last.id, anchor: .bottom)
                    }
                }
            }

            Divider()

            // Input
            HStack(spacing: 8) {
                Text("\(containerName) $")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.green)

                TextField("Enter command...", text: $currentCommand)
                    .font(.system(size: 12, design: .monospaced))
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .onSubmit { executeCommand() }
                    .disabled(isExecuting)

                if isExecuting {
                    ProgressView().scaleEffect(0.6).frame(width: 16, height: 16)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
        .onAppear { inputFocused = true }
    }

    private func executeCommand() {
        let cmd = currentCommand.trimmingCharacters(in: .whitespaces)
        guard !cmd.isEmpty else { return }

        commandHistory.append(TerminalEntry(text: cmd, isCommand: true, isError: false, isSystem: false))
        currentCommand = ""
        isExecuting = true

        Task {
            do {
                let execArgs = ["exec", containerName, "sh", "-c", cmd]
                let result = try await deps.cliBridge.run(execArgs, timeout: .seconds(30))
                await MainActor.run {
                    for line in result.stdout.components(separatedBy: .newlines) where !line.isEmpty {
                        commandHistory.append(TerminalEntry(text: line, isCommand: false, isError: false, isSystem: false))
                    }
                    for line in result.stderr.components(separatedBy: .newlines) where !line.isEmpty {
                        commandHistory.append(TerminalEntry(text: line, isCommand: false, isError: true, isSystem: false))
                    }
                    isExecuting = false
                }
            } catch {
                await MainActor.run {
                    commandHistory.append(TerminalEntry(text: "Error: \(error.localizedDescription)", isCommand: false, isError: true, isSystem: false))
                    isExecuting = false
                }
            }
        }
    }
}

// MARK: - Supporting types

struct TerminalEntry: Identifiable {
    let id = UUID()
    let text: String
    let isCommand: Bool
    let isError: Bool
    let isSystem: Bool
}

struct TerminalEntryView: View {
    let entry: TerminalEntry

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if entry.isCommand {
                Text("$")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.green)
                    .frame(width: 14, alignment: .trailing)
            } else {
                Color.clear.frame(width: 14)
            }
            Text(entry.text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(entry.isError ? .red : (entry.isSystem ? .secondary : .primary))
                .textSelection(.enabled)
        }
        .padding(.horizontal, 12)
    }
}
