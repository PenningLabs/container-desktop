import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// View that displays application-level events: CLI errors, notification
/// failures, container start failures, and system issues. This is where
/// users find out WHY something failed, even if the container never started
/// and has no logs.
struct AppEventLogView: View {
    @State private var filterLevel: AppEventLevel? = nil
    @State private var filterText: String = ""

    private var eventLog: AppEventLog { AppEventLog.shared }

    var body: some View {
        VStack(spacing: 0) {
            eventToolbar

            Divider()

            if filteredEvents.isEmpty {
                EmptyStateView(
                    icon: "doc.text.magnifyingglass",
                    message: "No events",
                    detail: "Application events, errors, and warnings will appear here."
                )
            } else {
                eventList
            }
        }
        .onAppear {
            eventLog.markAllRead()
        }
    }

    private var filteredEvents: [AppEvent] {
        var result = eventLog.events
        if let level = filterLevel {
            result = result.filter { $0.level == level }
        }
        if !filterText.isEmpty {
            result = result.filter {
                $0.message.localizedCaseInsensitiveContains(filterText) ||
                $0.source.localizedCaseInsensitiveContains(filterText)
            }
        }
        return result.reversed() // Newest first
    }

    // MARK: - Toolbar

    @ViewBuilder
    private var eventToolbar: some View {
        HStack(spacing: 12) {
            Text("Event log")
                .font(.title3)
                .fontWeight(.medium)

            Spacer()

            // Level filter pills
            HStack(spacing: 4) {
                FilterPill(label: "All", isActive: filterLevel == nil) {
                    filterLevel = nil
                }
                FilterPill(label: "Errors", isActive: filterLevel == .error, color: .red) {
                    filterLevel = .error
                }
                FilterPill(label: "Warnings", isActive: filterLevel == .warning, color: .orange) {
                    filterLevel = .warning
                }
            }

            TextField("Filter...", text: $filterText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)

            Text("\(filteredEvents.count) events")
                .font(.caption)
                .foregroundStyle(.secondary)

            Menu {
                Button("Copy all") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(eventLog.exportAsText(), forType: .string)
                }
                Button("Save to file...") {
                    saveToFile()
                }
                Divider()
                Button("Clear all events") {
                    eventLog.clear()
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: - Event list

    @ViewBuilder
    private var eventList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 1) {
                ForEach(filteredEvents) { event in
                    EventRow(event: event)
                }
            }
        }
    }

    private func saveToFile() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "container-desktop-events.log"
        panel.allowedContentTypes = [.plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try eventLog.exportAsText().write(to: url, atomically: true, encoding: .utf8)
        } catch {
            AppEventLog.shared.error(error, context: "Save event log to \(url.lastPathComponent)", source: "Event Log")
        }
    }
}

// MARK: - Event row

struct EventRow: View {
    let event: AppEvent

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: event.level.iconName)
                .font(.caption)
                .foregroundStyle(levelColor)
                .frame(width: 16)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(event.source)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)

                    Text(Formatters.relativeTime(event.timestamp))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Text(event.message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .lineLimit(4)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(event.level == .error ? Color.red.opacity(0.03) : .clear)
    }

    private var levelColor: Color {
        switch event.level {
        case .info:    return .blue
        case .warning: return .orange
        case .error:   return .red
        }
    }
}

// MARK: - Filter pill

struct FilterPill: View {
    let label: String
    let isActive: Bool
    var color: Color = .accentColor
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.caption2)
                .fontWeight(isActive ? .semibold : .regular)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(isActive ? color.opacity(0.15) : Color.secondary.opacity(0.06))
                .foregroundStyle(isActive ? color : .secondary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}
