import Foundation
import SwiftData
import OSLog

/// One instance per open chat. Owns the in-flight streaming task and the
/// error banner. `ChatView` observes this via `@Bindable`.
@Observable
@MainActor
final class ChatViewModel {

    // Observable state
    var isStreaming: Bool = false
    var errorBanner: String?

    // Injected
    private let client: any MLXClientProtocol
    private let modelContext: ModelContext
    private let now: () -> Date
    private let log = Logger(subsystem: "dev.localmlx", category: "chat")

    // In-flight streaming task, if any.
    private var streamingTask: Task<Void, Never>?

    init(client: any MLXClientProtocol,
         modelContext: ModelContext,
         now: @escaping () -> Date = { .now }) {
        self.client = client
        self.modelContext = modelContext
        self.now = now
    }

    // MARK: - Public API

    /// Send a user message to the given conversation and stream the assistant
    /// reply. Returns when streaming terminates (either normally, via Stop, or
    /// via error). Safe to re-enter; cancels any prior stream.
    func send(_ text: String, in conversation: Conversation) async {
        // Cancel any previous in-flight stream before starting a new one.
        streamingTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorBanner = nil

        // Insert the user message and an empty assistant placeholder into the
        // context up-front. The placeholder is what SwiftUI observes as the
        // stream writes into `content`.
        let sendTime = now()
        let userMsg = Message(
            role: .user,
            content: trimmed,
            createdAt: sendTime,
            conversation: conversation)
        modelContext.insert(userMsg)

        // Tiny offset so sortedMessages keeps a deterministic order even when
        // the injected clock is frozen (e.g., in tests).
        let assistantMsg = Message(
            role: .assistant,
            content: "",
            createdAt: sendTime.addingTimeInterval(0.001),
            conversation: conversation)
        modelContext.insert(assistantMsg)

        // Build the OpenAI-compatible request from the full conversation so
        // the assistant has context from prior turns.
        let history = conversation.sortedMessages
            .filter { !($0.role == .assistant && $0.content.isEmpty) }
            .map { (role: $0.role.rawValue, content: $0.content) }

        let request = ChatRequest(
            model: conversation.modelId ?? "",
            messages: ChatRequest.buildMessages(
                systemPrompt: conversation.systemPrompt,
                history: history),
            stream: true,
            temperature: conversation.temperature,
            topP: conversation.topP,
            maxTokens: conversation.maxTokens
        )

        isStreaming = true

        // Run the streaming consumer as a @MainActor child so writes into
        // SwiftData properties are serialized with the UI.
        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isStreaming = false }

            do {
                let stream = try await self.client.streamChat(request)
                for try await delta in stream {
                    assistantMsg.content += delta
                }
            } catch MLXClientError.canceled {
                // User hit Stop — keep partial content, no banner.
                self.log.info("stream canceled by user")
            } catch let error as MLXClientError {
                self.errorBanner = error.errorDescription
                self.log.error("stream error: \(error.localizedDescription, privacy: .public)")
            } catch is CancellationError {
                self.log.info("task canceled")
            } catch {
                self.errorBanner = error.localizedDescription
                self.log.error("unexpected stream error: \(error.localizedDescription, privacy: .public)")
            }

            // Finalize conversation bookkeeping.
            conversation.updatedAt = self.now()
            Self.applyAutoTitle(to: conversation, firstUserMessage: trimmed)

            do {
                try self.modelContext.save()
            } catch {
                self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        self.streamingTask = task
        await task.value
    }

    /// Cancel the current streaming task, if any. Partial content on the
    /// assistant message is preserved. No error banner is set — Stop is a
    /// user action, not a failure.
    func stop() {
        streamingTask?.cancel()
    }

    /// Regenerate the last assistant reply by dropping it and re-sending the
    /// last user message. Used by the error-banner Retry affordance.
    func regenerateLast(in conversation: Conversation) async {
        let sorted = conversation.sortedMessages
        guard let lastUser = sorted.last(where: { $0.role == .user }) else { return }

        // Drop any assistant messages after the last user message.
        let tailAssistants = sorted
            .drop(while: { $0 !== lastUser })
            .dropFirst()
            .filter { $0.role == .assistant }
        for m in tailAssistants {
            modelContext.delete(m)
        }

        let text = lastUser.content
        modelContext.delete(lastUser)
        try? modelContext.save()

        await send(text, in: conversation)
    }

    /// Dismiss the error banner.
    func dismissError() { errorBanner = nil }

    // MARK: - Auto-title

    /// The title of a fresh "New Chat" is replaced by a truncated form of the
    /// first user message the first time a user actually sends. After that,
    /// or if the user already renamed it, we leave the title alone.
    static func applyAutoTitle(to conversation: Conversation, firstUserMessage text: String) {
        guard conversation.title == "New Chat" else { return }
        let limit = 40
        if text.count <= limit {
            conversation.title = text
        } else {
            let idx = text.index(text.startIndex, offsetBy: limit)
            conversation.title = String(text[..<idx]) + "…"
        }
    }
}
