import SwiftUI
import SwiftData

struct ChatView: View {
    @Bindable var conversation: Conversation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.mlxClient) private var clientHolder
    @EnvironmentObject private var settings: AppSettings

    @State private var viewModel: ChatViewModel?
    @State private var modelsVM: ModelsViewModel?
    @State private var draft: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                conversation: conversation,
                modelsVM: modelsVM
            )
            Divider()

            if let banner = viewModel?.errorBanner {
                ErrorBanner(
                    message: banner,
                    onDismiss: { viewModel?.dismissError() },
                    onRetry: {
                        viewModel?.dismissError()
                        Task { await viewModel?.regenerateLast(in: conversation) }
                    }
                )
            }

            TranscriptView(messages: conversation.sortedMessages,
                           isStreaming: viewModel?.isStreaming ?? false)

            Divider()
            ComposerView(
                text: $draft,
                isStreaming: viewModel?.isStreaming ?? false,
                canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && !(conversation.modelId ?? "").isEmpty,
                onSend: send,
                onStop: stop
            )
        }
        .task(id: conversation.id) {
            // Build view models once per conversation.
            if viewModel == nil {
                viewModel = ChatViewModel(
                    client: clientHolder.client,
                    modelContext: modelContext
                )
            }
            if modelsVM == nil {
                modelsVM = ModelsViewModel(client: clientHolder.client)
                await modelsVM?.refresh()
            }
            // If the conversation has no model yet, try to pick one.
            if conversation.modelId == nil,
               let first = modelsVM?.models.first {
                conversation.modelId = first
                try? modelContext.save()
            }
        }
    }

    private func send() {
        let text = draft
        draft = ""
        Task { await viewModel?.send(text, in: conversation) }
    }

    private func stop() {
        viewModel?.stop()
    }
}

// MARK: - Error banner

private struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void
    let onRetry: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
            Text(message)
                .font(.callout)
                .foregroundStyle(.primary)
                .textSelection(.enabled)
            Spacer()
            Button("Retry", action: onRetry)
                .buttonStyle(.borderless)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .overlay(Rectangle().fill(Color.red.opacity(0.25)).frame(height: 1),
                 alignment: .bottom)
    }
}
