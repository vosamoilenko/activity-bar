import SwiftUI
import Core

/// Empty state view shown when there are no activities to display
struct EmptyStateView: View {
    let title: String
    let subtitle: String

    init(
        title: String = "No activities yet",
        subtitle: String = "Connect an account to see your activity here."
    ) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(subtitle)")
    }
}

/// Loading state view shown while data is being fetched
struct LoadingStateView: View {
    let text: String

    init(text: String = "Loading activities…") {
        self.text = text
    }

    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
                .controlSize(.regular)
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(text)
    }
}

/// Error state view shown when data fetch fails, with retry button
struct ErrorStateView: View {
    let message: String
    let onRetry: () -> Void

    @State private var showCopied = false

    init(
        message: String = "Failed to load activities",
        onRetry: @escaping () -> Void
    ) {
        self.message = message
        self.onRetry = onRetry
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Button("Retry") {
                    onRetry()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.accentColor.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                )

                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message, forType: .string)
                    showCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        showCopied = false
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                        Text(showCopied ? "Copied" : "Copy")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.1))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            }
        }
        .frame(maxWidth: .infinity, minHeight: 120)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error: \(message)")
    }
}

/// Small inline error text with copy button
struct CopyableErrorText: View {
    let message: String
    let icon: String
    let color: Color

    @State private var showCopied = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text(message)
                .foregroundStyle(color)
                .lineLimit(2)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(showCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(showCopied ? "Copied!" : "Copy error")
        }
        .font(.caption)
    }
}

/// Inline error banner with copy and dismiss buttons
struct ErrorBannerView: View {
    let message: String
    let onDismiss: (() -> Void)?

    @State private var showCopied = false

    init(message: String, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.onDismiss = onDismiss
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Spacer()

            // Copy button
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(message, forType: .string)
                showCopied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    showCopied = false
                }
            } label: {
                Image(systemName: showCopied ? "checkmark" : "doc.on.doc")
                    .foregroundStyle(showCopied ? .green : .secondary)
            }
            .buttonStyle(.plain)
            .help(showCopied ? "Copied!" : "Copy error message")

            // Dismiss button (optional)
            if let onDismiss = onDismiss {
                Button {
                    onDismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Dismiss")
            }
        }
        .padding(8)
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(6)
    }
}

// MARK: - Preview Helpers

#Preview("Empty State") {
    EmptyStateView()
        .padding()
}

#Preview("Empty State - Custom") {
    EmptyStateView(
        title: "No activities today",
        subtitle: "Try selecting a different date."
    )
    .padding()
}

#Preview("Loading State") {
    LoadingStateView()
        .padding()
}

#Preview("Loading State - Custom") {
    LoadingStateView(text: "Fetching your activities…")
        .padding()
}

#Preview("Error State") {
    ErrorStateView(
        message: "Network connection failed",
        onRetry: { print("Retry tapped") }
    )
    .padding()
}
