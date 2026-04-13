import SwiftUI

/// Shown when a conversation has no messages yet. Gives users something to
/// click besides the blank composer — a handful of example prompts and the
/// current model name.
struct EmptyChatView: View {
    let modelId: String?
    let onExampleTap: (String) -> Void

    private let examples: [(String, String)] = [
        ("text.append", "Summarize this article in three bullet points: …"),
        ("chevron.left.forwardslash.chevron.right", "Write a Python function that reverses a linked list."),
        ("questionmark.circle", "Explain quantum entanglement to a high schooler."),
        ("lightbulb", "Give me three weekend project ideas for a Raspberry Pi."),
    ]

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            VStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 44))
                    .foregroundStyle(.tertiary)
                Text(modelId?.isEmpty == false ? (modelId ?? "") : "No model selected")
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("Start a conversation or try one of these prompts.")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            }

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                ForEach(Array(examples.enumerated()), id: \.offset) { _, example in
                    Button {
                        onExampleTap(example.1)
                    } label: {
                        ExampleCard(icon: example.0, text: example.1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 560)

            Spacer()
        }
        .padding(24)
    }
}

private struct ExampleCard: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.tint)
                .font(.body)
            Text(text)
                .font(.callout)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .foregroundStyle(.primary)
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }
}
