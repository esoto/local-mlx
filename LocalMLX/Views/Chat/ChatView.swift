import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct ChatView: View {
    @Bindable var conversation: Conversation

    @Environment(\.modelContext) private var modelContext
    @Environment(\.mlxClient) private var clientHolder
    @Environment(ModelsViewModel.self) private var modelsVM
    @EnvironmentObject private var settings: AppSettings

    @State private var viewModel: ChatViewModel?
    @State private var draft: String = ""
    @State private var draftAttachments: [ChatViewModel.PendingAttachment] = []
    @State private var editingMessage: Message?
    @State private var showingExporter = false
    @State private var exportDocument: MarkdownDocument?

    var body: some View {
        VStack(spacing: 0) {
            ChatHeaderView(
                conversation: conversation,
                modelsVM: modelsVM,
                onExport: prepareExport
            )
            Divider()

            if let banner = viewModel?.errorBanner {
                ErrorBanner(
                    message: banner,
                    onDismiss: { viewModel?.dismissError() },
                    onRetry: {
                        viewModel?.dismissError()
                        Task { await viewModel?.retryLast(in: conversation) }
                    }
                )
            }

            content

            Divider()
            if showsVisionMismatchWarning {
                visionMismatchWarning
            }
            ComposerView(
                text: $draft,
                attachments: $draftAttachments,
                isStreaming: viewModel?.isStreaming ?? false,
                canSend: canSendDraft,
                onSend: send,
                onStop: stop
            )
        }
        .task(id: conversation.id) {
            if viewModel == nil {
                viewModel = ChatViewModel(
                    client: clientHolder.client,
                    modelContext: modelContext
                )
            }
            // Clean up any assistant placeholders left stuck in the
            // pre-streaming state by a previous session (app quit
            // mid-stream, server disconnect, etc.). Idempotent — safe
            // to call every time the conversation mounts.
            viewModel?.reconcileInterruptedMessages(in: conversation)
            // If the conversation has no model yet, try to pick one from the
            // shared (already-polling) ModelsViewModel.
            if conversation.modelId == nil, let first = modelsVM.models.first {
                conversation.modelId = first
                try? modelContext.save()
            }
        }
        .sheet(item: $editingMessage) { message in
            EditMessageSheet(
                originalText: message.content,
                onCommit: { newText in
                    editingMessage = nil
                    Task {
                        await viewModel?.editAndResend(
                            userMessage: message,
                            newContent: newText,
                            in: conversation)
                    }
                },
                onCancel: { editingMessage = nil }
            )
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: exportDocument?.suggestedFilename ?? "chat.md"
        ) { _ in }
    }

    // MARK: - Content area

    @ViewBuilder
    private var content: some View {
        if conversation.messages.isEmpty {
            EmptyChatView(
                modelId: conversation.modelId,
                onExampleTap: { draft = $0 }
            )
        } else {
            TranscriptView(
                messages: conversation.sortedMessages,
                isStreaming: viewModel?.isStreaming ?? false,
                onRegenerate: { msg in
                    Task { await viewModel?.regenerate(assistantMessage: msg, in: conversation) }
                },
                onEdit: { msg in
                    editingMessage = msg
                },
                onDelete: { msg in
                    viewModel?.delete(message: msg, in: conversation)
                },
                onFork: { msg in
                    if let fork = viewModel?.branch(atMessage: msg, from: conversation) {
                        NotificationCenter.default.post(
                            name: .conversationActivated,
                            object: fork.id)
                    }
                }
            )
        }
    }

    // MARK: - Actions

    private var canSendDraft: Bool {
        let hasText = !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAttachments = !draftAttachments.isEmpty
        let hasModel = !(conversation.modelId ?? "").isEmpty
        return (hasText || hasAttachments) && hasModel
    }

    /// `true` when the composer has image attachments pending AND the
    /// conversation's configured model is known in the catalog as a
    /// text-only entry. Custom paths (unknown to the catalog) don't
    /// trigger the warning — we can't tell what they support, and the
    /// server-error translator catches the rejection at send time
    /// anyway.
    private var showsVisionMismatchWarning: Bool {
        guard !draftAttachments.isEmpty else { return false }
        guard let modelId = conversation.modelId,
              let entry = MLXModelCatalog.find(modelId)
        else { return false }
        return !entry.isVision
    }

    @ViewBuilder
    private var visionMismatchWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("This model is text-only. The server will reject image attachments — pick a vision-capable model in Settings (marked with 👁), or remove the attachments before sending.")
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
        }
        .padding(10)
        .background(Color.orange.opacity(0.12))
        .overlay(
            Rectangle().fill(Color.orange.opacity(0.35)).frame(height: 1),
            alignment: .bottom)
    }

    private func send() {
        let text = draft
        let attachments = draftAttachments
        draft = ""
        draftAttachments = []
        Task {
            await viewModel?.send(text, attachments: attachments, in: conversation)
        }
    }

    private func stop() {
        viewModel?.stop()
    }

    private func prepareExport() {
        let markdown = ChatExporter.markdown(from: conversation)
        exportDocument = MarkdownDocument(
            text: markdown,
            suggestedFilename: ChatExporter.suggestedFilename(for: conversation)
        )
        showingExporter = true
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

// MARK: - Edit-and-resend sheet

private struct EditMessageSheet: View {
    let originalText: String
    let onCommit: (String) -> Void
    let onCancel: () -> Void

    @State private var text: String

    init(originalText: String,
         onCommit: @escaping (String) -> Void,
         onCancel: @escaping () -> Void) {
        self.originalText = originalText
        self.onCommit = onCommit
        self.onCancel = onCancel
        self._text = State(initialValue: originalText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit message and resend")
                .font(.headline)
            TextEditor(text: $text)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
            HStack {
                Spacer()
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Resend") { onCommit(text) }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
        // Sheets on macOS need an explicit frame — without one the outer
        // VStack can collapse around an empty-looking content area.
        .frame(minWidth: 520, idealWidth: 560, minHeight: 240, idealHeight: 280)
    }
}

// MARK: - FileDocument for export

struct MarkdownDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }

    let text: String
    let suggestedFilename: String

    init(text: String, suggestedFilename: String) {
        self.text = text
        self.suggestedFilename = suggestedFilename
    }

    init(configuration: ReadConfiguration) throws {
        throw CocoaError(.fileReadUnsupportedScheme)
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: Data(text.utf8))
    }
}
