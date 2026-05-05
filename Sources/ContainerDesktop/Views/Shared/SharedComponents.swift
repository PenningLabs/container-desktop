import SwiftUI

// MARK: - Status badge

/// Colored pill showing container status.
struct StatusBadge: View {
    let status: ContainerStatus

    var body: some View {
        Text(status.displayName)
            .font(.caption2)
            .fontWeight(.medium)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .foregroundStyle(foregroundColor)
            .background(backgroundColor)
            .clipShape(Capsule())
            .accessibilityLabel("Status: \(status.displayName)")
    }

    private var foregroundColor: Color {
        switch status {
        case .running:  return .green
        case .stopped:  return .secondary
        case .creating: return .blue
        case .stopping: return .orange
        case .unknown:  return .secondary
        }
    }

    private var backgroundColor: Color {
        foregroundColor.opacity(0.12)
    }
}

// MARK: - Architecture badge

/// Small badge showing container/image architecture.
struct ArchBadge: View {
    let architecture: Architecture

    var body: some View {
        Text(shortLabel)
            .font(.system(.caption2, design: .monospaced))
            .fontWeight(.medium)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundColor(architecture == .amd64 ? Color.orange : Color.secondary)
            .background(architecture == .amd64 ? Color.orange.opacity(0.1) : Color.secondary.opacity(0.08))
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .accessibilityLabel("Architecture: \(architecture.displayName)")
    }

    private var shortLabel: String {
        switch architecture {
        case .arm64: return "arm64"
        case .amd64: return "amd64"
        case .multi: return "multi"
        case .unknown: return "?"
        }
    }
}

// MARK: - Empty state view

struct EmptyStateView: View {
    let icon: String
    let message: String
    var detail: String?
    var action: (() -> Void)?
    var actionLabel: String?

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundStyle(.tertiary)

            Text(message)
                .font(.headline)
                .foregroundStyle(.secondary)

            if let detail {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
            }

            if let action, let label = actionLabel {
                Button(label, action: action)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Error banner

/// Inline error banner that can be placed at the top of a view.
struct ErrorBanner: View {
    let error: AppError
    var onDismiss: (() -> Void)?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.caption)

            Text(error.localizedDescription)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(2)

            Spacer()

            if let onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption2)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .padding(.horizontal, 12)
    }
}

// MARK: - Loading overlay

struct LoadingOverlay: View {
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial)
    }
}
