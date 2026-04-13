import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onRegenerate: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                roleLabel
                body(for: message)
                footer
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .overlay(alignment: .topTrailing) {
            if isHovered { hoverActions }
        }
    }

    // MARK: - Pieces

    @ViewBuilder private var icon: some View {
        Circle()
            .fill(isUser ? Color.accentColor : Color.gray.opacity(0.4))
            .frame(width: 24, height: 24)
            .overlay(
                Image(systemName: isUser ? "person.fill" : "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            )
    }

    private var roleLabel: some View {
        Text(isUser ? "You" : "Assistant")
            .font(.caption).bold()
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func body(for message: Message) -> some View {
        switch message.role {
        case .user, .system:
            Text(message.content)
                .textSelection(.enabled)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
        case .assistant:
            if message.content.isEmpty && message.interruptionReason == nil {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 2)
            } else {
                MarkdownText(content: message.content)
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        HStack(spacing: 8) {
            if let interruption = message.interruptionReason {
                Label("stream interrupted: \(interruption)", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .lineLimit(2)
            }
            if let tps = message.tokensPerSecond {
                Text("\(tps, specifier: "%.1f") tok/s")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            if let completion = message.completionTokens {
                Text("\(completion) tokens")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
        }
    }

    @ViewBuilder
    private var hoverActions: some View {
        HStack(spacing: 4) {
            CopyButton(textProvider: { message.content }, compact: true)

            if let onEdit, isUser {
                Button(action: onEdit) {
                    Image(systemName: "pencil")
                        .font(.caption2)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Edit and resend")
            }

            if let onRegenerate, !isUser {
                Button(action: onRegenerate) {
                    Image(systemName: "arrow.clockwise")
                        .font(.caption2)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Regenerate")
            }

            if let onDelete {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.caption2)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Delete message")
            }
        }
        .padding(4)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
        )
    }

    private var isUser: Bool { message.role == .user }
}
