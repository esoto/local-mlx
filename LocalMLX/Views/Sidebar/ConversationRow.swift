import SwiftUI

struct ConversationRow: View {
    @Bindable var conversation: Conversation
    @State private var isRenaming = false
    @State private var draftTitle = ""

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "bubble.left")
                .foregroundStyle(.secondary)

            if isRenaming {
                TextField("Title", text: $draftTitle, onCommit: commit)
                    .textFieldStyle(.roundedBorder)
                    .onExitCommand { cancel() }
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(conversation.title)
                        .lineLimit(1)
                    if let modelId = conversation.modelId, !modelId.isEmpty {
                        Text(modelId)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) { beginRenaming() }
        .contextMenu {
            Button("Rename") { beginRenaming() }
        }
    }

    private func beginRenaming() {
        draftTitle = conversation.title
        isRenaming = true
    }

    private func commit() {
        let trimmed = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            conversation.title = trimmed
        }
        isRenaming = false
    }

    private func cancel() { isRenaming = false }
}
