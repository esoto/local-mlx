import Foundation

/// Converts a `Conversation` into a Markdown document suitable for saving
/// or copying. Kept as a pure function so it's trivially unit-testable.
enum ChatExporter {

    /// Renders a conversation to Markdown. Header includes the title, model,
    /// and generation date. System prompt is rendered as a collapsible
    /// blockquote. Each message is a level-3 heading ("### You" / "### Assistant")
    /// followed by its content. Interruption and tok/s metadata are noted
    /// inline below assistant replies.
    static func markdown(from conversation: Conversation,
                         now: Date = .now) -> String {
        var lines: [String] = []

        lines.append("# \(conversation.title)")
        lines.append("")

        var metaParts: [String] = []
        if let model = conversation.modelId, !model.isEmpty {
            metaParts.append("**Model:** `\(model)`")
        }
        metaParts.append("**Exported:** \(isoFormatter.string(from: now))")
        lines.append(metaParts.joined(separator: "  \u{00B7}  "))
        lines.append("")

        let system = conversation.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !system.isEmpty {
            lines.append("> **System prompt:**")
            for sysLine in system.split(whereSeparator: \.isNewline) {
                lines.append("> \(sysLine)")
            }
            lines.append("")
        }

        for message in conversation.sortedMessages {
            switch message.role {
            case .system:
                continue  // already rendered above
            case .user:
                lines.append("### You")
            case .assistant:
                lines.append("### Assistant")
            }
            lines.append("")
            lines.append(message.content)
            lines.append("")

            if message.role == .assistant {
                var metaBits: [String] = []
                if let tps = message.tokensPerSecond {
                    metaBits.append(String(format: "%.1f tok/s", tps))
                }
                if let completion = message.completionTokens {
                    metaBits.append("\(completion) tokens")
                }
                if let interruption = message.interruptionReason {
                    metaBits.append("interrupted: \(interruption)")
                }
                if !metaBits.isEmpty {
                    lines.append("_\(metaBits.joined(separator: " \u{00B7} "))_")
                    lines.append("")
                }
            }
        }

        // Trim trailing blank lines.
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    /// Suggest a filename based on the chat title, sanitized for the filesystem.
    static func suggestedFilename(for conversation: Conversation) -> String {
        let allowed = CharacterSet.alphanumerics
            .union(CharacterSet(charactersIn: " -_"))
        let cleaned = conversation.title.unicodeScalars
            .map { allowed.contains($0) ? Character($0) : "-" }
        let trimmed = String(cleaned)
            .trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "  ", with: " ")
        let base = trimmed.isEmpty ? "chat" : trimmed
        return "\(base).md"
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}
