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
    @State private var editingMessage: Message?
    @State private var showingEditSheet = false
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
            if viewModel == nil {
                viewModel = ChatViewModel(
                    client: clientHolder.client,
                    modelContext: modelContext
                )
            }
            // If the conversation has no model yet, try to pick one from the
            // shared (already-polling) ModelsViewModel.
            if conversation.modelId == nil, let first = modelsVM.models.first {
                conversation.modelId = first
                try? modelContext.save()
            }
        }
        .sheet(isPresented: $showingEditSheet) {
            if let message = editingMessage {
                EditMessageSheet(
                    originalText: message.content,
                    onCommit: { newText in
                        let target = message
                        showingEditSheet = false
                        editingMessage = nil
                        Task {
                            await viewModel?.editAndResend(
                                userMessage: target,
                                newContent: newText,
                                in: conversation)
                        }
                    },
                    onCancel: {
                        showingEditSheet = false
                        editingMessage = nil
                    }
                )
            }
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
                    showingEditSheet = true
                },
                onDelete: { msg in
                    viewModel?.delete(message: msg, in: conversation)
                },
                onFork: { msg in
                    _ = viewModel?.branch(atMessage: msg, from: conversation)
                }
            )
        }
    }

    // MARK: - Actions

    private func send() {
        let text = draft
        draft = ""
        Task { await viewModel?.send(text, in: conversation) }
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
                .frame(minWidth: 420, minHeight: 120)
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
