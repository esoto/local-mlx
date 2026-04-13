import SwiftUI

struct MessageBubble: View {
    let message: Message
    var onRegenerate: (() -> Void)?
    var onEdit: (() -> Void)?
    var onDelete: (() -> Void)?
    var onFork: (() -> Void)?

    @State private var isHovered = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            icon
            VStack(alignment: .leading, spacing: 4) {
                roleLabel
                if !message.attachments.isEmpty {
                    attachmentRow
                }
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
        // Right-click also exposes every action — hover-only controls
        // are hard to discover, especially on a trackpad.
        .contextMenu { actionMenuItems }
    }

    @ViewBuilder
    private var actionMenuItems: some View {
        Button {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(message.content, forType: .string)
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        if let onEdit, isUser {
            Button(action: onEdit) {
                Label("Edit and resend", systemImage: "pencil")
            }
        }
        if let onRegenerate, !isUser {
            Button(action: onRegenerate) {
                Label("Regenerate", systemImage: "arrow.clockwise")
            }
        }
        if let onFork {
            Button(action: onFork) {
                Label("Fork from here", systemImage: "arrow.triangle.branch")
            }
        }
        if let onDelete {
            Divider()
            Button(role: .destructive, action: onDelete) {
                Label("Delete message", systemImage: "trash")
            }
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
                waitingIndicator
            } else {
                MarkdownText(content: message.content)
            }
        }
    }

    /// Shown while an assistant message has no content and no error.
    /// Uses `TimelineView` so the elapsed seconds update once per second
    /// — doubly useful as a diagnostic: if the number stops advancing
    /// the main thread is blocked, if it keeps advancing the server is
    /// just slow (common on vision models during their first prompt
    /// processing).
    @ViewBuilder
    private var waitingIndicator: some View {
        TimelineView(.periodic(from: message.createdAt, by: 1)) { context in
            let elapsed = max(0, context.date.timeIntervalSince(message.createdAt))
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                ProgressView().controlSize(.small)
                Text(Self.waitingText(elapsed: elapsed))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.vertical, 2)
        }
    }

    /// Progressive hint based on how long we've been waiting for the
    /// first token. Kept `static` and pure so it's unit-testable
    /// without spinning up a SwiftUI view hierarchy.
    static func waitingText(elapsed: TimeInterval) -> String {
        let secs = Int(elapsed)
        switch elapsed {
        case ..<3:
            return "Waiting for response…"
        case ..<15:
            return "Waiting for first token — \(secs)s"
        case ..<45:
            return "Still waiting — \(secs)s. Vision models can take 10–30s to process an image before the first token arrives."
        case ..<120:
            return "Still waiting — \(secs)s. The model may still be loading into memory, or prompt processing is slow. Click Stop to cancel."
        default:
            return "No response after \(secs)s. The server is likely stuck or a huge model is still loading. Click Stop and check the Terminal window for errors."
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

            if let onFork {
                Button(action: onFork) {
                    Image(systemName: "arrow.triangle.branch")
                        .font(.caption2)
                        .frame(width: 16, height: 16)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Fork chat from this message")
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

    // MARK: - Attachments

    @ViewBuilder
    private var attachmentRow: some View {
        let sorted = message.attachments.sorted { $0.createdAt < $1.createdAt }
        HStack(spacing: 6) {
            ForEach(sorted) { attachment in
                InlineAttachmentThumbnail(attachment: attachment)
            }
        }
        .padding(.vertical, 2)
    }
}

private struct InlineAttachmentThumbnail: View {
    let attachment: MessageAttachment
    @State private var hovered = false

    var body: some View {
        Group {
            if let image = NSImage(data: attachment.data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 128, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
                    )
                    .overlay(alignment: .topTrailing) {
                        if hovered {
                            Button {
                                openInPreview(attachment: attachment)
                            } label: {
                                Image(systemName: "arrow.up.left.and.arrow.down.right")
                                    .padding(4)
                                    .background(.black.opacity(0.6), in: Circle())
                                    .foregroundStyle(.white)
                            }
                            .buttonStyle(.plain)
                            .padding(4)
                            .help("Open full size in Preview")
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 128, height: 96)
                    .overlay(Image(systemName: "photo"))
            }
        }
        .onHover { hovered = $0 }
    }

    /// Write the image bytes to a temp file and hand them to the OS so
    /// Preview (or whatever the user has associated with images) opens
    /// them. Safe from the sandbox because we're only asking
    /// LaunchServices to open a file inside our container.
    private func openInPreview(attachment: MessageAttachment) {
        let ext = mimeToExtension(attachment.mimeType)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalMLX-\(attachment.id.uuidString).\(ext)")
        do {
            try attachment.data.write(to: url, options: .atomic)
            NSWorkspace.shared.open(url)
        } catch {
            NSLog("LocalMLX: could not open attachment: \(error)")
        }
    }

    private func mimeToExtension(_ mime: String) -> String {
        switch mime {
        case "image/jpeg": return "jpg"
        case "image/png":  return "png"
        case "image/gif":  return "gif"
        case "image/webp": return "webp"
        case "image/heic": return "heic"
        default: return "png"
        }
    }
}
