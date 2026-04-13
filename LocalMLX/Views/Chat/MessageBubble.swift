import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                roleLabel
                body(for: message)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
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
        case .assistant:
            if message.content.isEmpty {
                ProgressView()
                    .controlSize(.small)
                    .padding(.vertical, 2)
            } else {
                MarkdownText(content: message.content)
            }
        }
    }

    private var isUser: Bool { message.role == .user }
}
