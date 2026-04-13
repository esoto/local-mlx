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
    private let wallClock: () -> Date   // separate clock for tok/s measurement
    private let log = Logger(subsystem: "dev.localmlx", category: "chat")

    /// Minimum interval between writes to `assistantMsg.content`. Coalesces
    /// fast-arriving tokens so MarkdownUI doesn't re-parse on every single
    /// delta. ~30 fps.
    private let flushInterval: TimeInterval = 0.033

    // In-flight streaming task, if any.
    private var streamingTask: Task<Void, Never>?

    init(client: any MLXClientProtocol,
         modelContext: ModelContext,
         now: @escaping () -> Date = { .now },
         wallClock: @escaping () -> Date = { .now }) {
        self.client = client
        self.modelContext = modelContext
        self.now = now
        self.wallClock = wallClock
    }

    // MARK: - Public API

    /// Send a user message to the given conversation and stream the assistant
    /// reply.
    func send(_ text: String, in conversation: Conversation) async {
        streamingTask?.cancel()

        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        errorBanner = nil

        // Monotonic timestamp: under a frozen test clock two successive
        // sends would otherwise tie on createdAt, and Swift's sort isn't
        // stable so sortedMessages would interleave the histories.
        let sendTime = nextTimestamp(after: conversation.sortedMessages.last?.createdAt)
        let userMsg = Message(
            role: .user,
            content: trimmed,
            createdAt: sendTime,
            conversation: conversation)
        modelContext.insert(userMsg)

        await generate(triggerText: trimmed, in: conversation, placeholderAfter: sendTime)
    }

    /// Regenerate the reply for a specific assistant message. The assistant
    /// message (and anything after it) is deleted, then generation restarts
    /// using the preceding user message.
    func regenerate(assistantMessage: Message, in conversation: Conversation) async {
        streamingTask?.cancel()
        errorBanner = nil

        let sorted = conversation.sortedMessages
        guard let idx = sorted.firstIndex(where: { $0 === assistantMessage }),
              idx > 0 else { return }
        let userMsg = sorted[idx - 1]
        guard userMsg.role == .user else { return }

        // Delete the assistant reply and anything after it.
        for m in sorted.suffix(from: idx) {
            modelContext.delete(m)
        }
        try? modelContext.save()

        let base = userMsg.createdAt
        await generate(triggerText: userMsg.content,
                       in: conversation,
                       placeholderAfter: base)
    }

    /// Edit a user message's content and regenerate everything that follows.
    func editAndResend(userMessage: Message,
                       newContent: String,
                       in conversation: Conversation) async {
        streamingTask?.cancel()
        errorBanner = nil

        let trimmed = newContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              userMessage.role == .user else { return }

        userMessage.content = trimmed

        let sorted = conversation.sortedMessages
        if let idx = sorted.firstIndex(where: { $0 === userMessage }) {
            for m in sorted.suffix(from: idx + 1) {
                modelContext.delete(m)
            }
            try? modelContext.save()
        }

        await generate(triggerText: trimmed,
                       in: conversation,
                       placeholderAfter: userMessage.createdAt)
    }

    /// Retry the last user message from the error banner. Deletes any
    /// dangling assistant reply and re-generates.
    func retryLast(in conversation: Conversation) async {
        streamingTask?.cancel()
        errorBanner = nil

        let sorted = conversation.sortedMessages
        guard let lastUser = sorted.last(where: { $0.role == .user }) else { return }

        if let idx = sorted.firstIndex(where: { $0 === lastUser }) {
            for m in sorted.suffix(from: idx + 1) {
                modelContext.delete(m)
            }
            try? modelContext.save()
        }

        await generate(triggerText: lastUser.content,
                       in: conversation,
                       placeholderAfter: lastUser.createdAt)
    }

    /// Delete a specific message (user or assistant).
    func delete(message: Message, in conversation: Conversation) {
        modelContext.delete(message)
        conversation.updatedAt = now()
        try? modelContext.save()
    }

    /// Fork the conversation at a specific message. Returns a new
    /// `Conversation` inserted into the same `ModelContext` containing
    /// independent copies of `message` and every message that follows it
    /// in the source conversation. The history BEFORE `message` is
    /// dropped — the pivot becomes the first message of the fork, so
    /// continuing the fork extends that slice of the transcript.
    /// Returns nil if the pivot message does not belong to `source`.
    ///
    /// The fork preserves the original `createdAt` timestamps on the
    /// copied messages so the transcript reads as a natural continuation.
    @discardableResult
    func branch(atMessage message: Message,
                from source: Conversation) -> Conversation? {
        let sorted = source.sortedMessages
        guard let pivotIdx = sorted.firstIndex(where: { $0 === message }) else {
            return nil
        }
        let kept = sorted.suffix(from: pivotIdx)

        let fork = Conversation(
            title: Self.forkTitle(from: source.title),
            createdAt: now(),
            systemPrompt: source.systemPrompt,
            modelId: source.modelId,
            temperature: source.temperature,
            topP: source.topP,
            maxTokens: source.maxTokens,
            presencePenalty: source.presencePenalty,
            frequencyPenalty: source.frequencyPenalty,
            repetitionPenalty: source.repetitionPenalty,
            seed: source.seed
        )
        modelContext.insert(fork)

        for original in kept {
            let copy = Message(
                role: original.role,
                content: original.content,
                createdAt: original.createdAt,
                conversation: fork,
                tokensPerSecond: original.tokensPerSecond,
                promptTokens: original.promptTokens,
                completionTokens: original.completionTokens,
                interruptionReason: original.interruptionReason
            )
            modelContext.insert(copy)
        }

        try? modelContext.save()
        return fork
    }

    /// Produce a title for a forked conversation. Appends " (fork)" unless
    /// the source already ends in one, in which case it increments the
    /// suffix to " (fork 2)", " (fork 3)", etc. so repeatedly forking the
    /// same branch doesn't produce "… (fork) (fork) (fork)".
    private static func forkTitle(from source: String) -> String {
        if source.hasSuffix(" (fork)") {
            return source.replacingOccurrences(of: " (fork)", with: " (fork 2)")
        }
        // Detect " (fork N)" suffix.
        if let match = source.range(of: #" \(fork (\d+)\)$"#, options: .regularExpression) {
            let numberSubstring = source[match]
                .trimmingCharacters(in: CharacterSet(charactersIn: " (fork)"))
            if let n = Int(numberSubstring) {
                let base = String(source[..<match.lowerBound])
                return "\(base) (fork \(n + 1))"
            }
        }
        return "\(source) (fork)"
    }

    /// Cancel the current streaming task. Partial content is preserved and
    /// no error banner is set.
    func stop() {
        streamingTask?.cancel()
    }

    /// Dismiss the error banner.
    func dismissError() { errorBanner = nil }

    // MARK: - Core generation loop

    private func generate(triggerText: String,
                          in conversation: Conversation,
                          placeholderAfter anchor: Date) async {

        // Insert an empty assistant placeholder whose `createdAt` strictly
        // follows the preceding user message so `sortedMessages` orders it
        // last. The offset is what makes ordering deterministic under a
        // frozen test clock.
        let assistantMsg = Message(
            role: .assistant,
            content: "",
            createdAt: anchor.addingTimeInterval(0.001),
            conversation: conversation)
        modelContext.insert(assistantMsg)

        // Build the OpenAI request from the full (persisted) conversation.
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
            maxTokens: conversation.maxTokens,
            presencePenalty: nonZeroOrNil(conversation.presencePenalty),
            frequencyPenalty: nonZeroOrNil(conversation.frequencyPenalty),
            repetitionPenalty: nonOneOrNil(conversation.repetitionPenalty),
            seed: conversation.seed,
            streamOptions: .init(includeUsage: true)
        )

        isStreaming = true

        let task = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.isStreaming = false }

            // Streaming state
            var pendingText = ""
            var lastFlush = self.wallClock()
            var firstDeltaAt: Date?
            var deltaCount = 0
            var capturedUsage: UsageStats?
            var interruption: String?

            do {
                let stream = try await self.client.streamChat(request)
                for try await event in stream {
                    switch event {
                    case .delta(let delta):
                        if firstDeltaAt == nil { firstDeltaAt = self.wallClock() }
                        deltaCount += 1
                        pendingText += delta
                        let tick = self.wallClock()
                        if tick.timeIntervalSince(lastFlush) >= self.flushInterval {
                            assistantMsg.content += pendingText
                            pendingText = ""
                            lastFlush = tick
                        }
                    case .usage(let usage):
                        capturedUsage = usage
                    }
                }
            } catch MLXClientError.canceled {
                self.log.info("stream canceled by user")
            } catch let error as MLXClientError {
                interruption = error.errorDescription
                self.errorBanner = error.errorDescription
                self.log.error("stream error: \(error.localizedDescription, privacy: .public)")
            } catch is CancellationError {
                self.log.info("task canceled")
            } catch {
                interruption = error.localizedDescription
                self.errorBanner = error.localizedDescription
                self.log.error("unexpected stream error: \(error.localizedDescription, privacy: .public)")
            }

            // Final flush of anything still buffered.
            if !pendingText.isEmpty {
                assistantMsg.content += pendingText
                pendingText = ""
            }

            // Write usage and tok/s.
            if let usage = capturedUsage {
                assistantMsg.promptTokens = usage.promptTokens
                assistantMsg.completionTokens = usage.completionTokens
            }
            if let startedAt = firstDeltaAt {
                let elapsed = self.wallClock().timeIntervalSince(startedAt)
                if elapsed > 0.01 {
                    let tokens = Double(capturedUsage?.completionTokens ?? deltaCount)
                    assistantMsg.tokensPerSecond = tokens / elapsed
                }
            }
            if let interruption {
                assistantMsg.interruptionReason = interruption
            }

            // Finalize bookkeeping.
            conversation.updatedAt = self.now()
            Self.applyAutoTitle(to: conversation, firstUserMessage: triggerText)

            do {
                try self.modelContext.save()
            } catch {
                self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
            }
        }

        self.streamingTask = task
        await task.value
    }

    // MARK: - Helpers

    /// Clamp `now()` to strictly after the last known message timestamp so
    /// successive messages are always ordered — even when tests freeze
    /// `now` on a constant.
    private func nextTimestamp(after prior: Date?) -> Date {
        let t = now()
        guard let prior else { return t }
        let minimum = prior.addingTimeInterval(0.002)  // >asst placeholder offset
        return t > minimum ? t : minimum
    }

    /// For defaults like temperature=0.7, top_p=1.0 we always send the value.
    /// For presence/frequency penalties (default 0) we want to OMIT when 0 so
    /// mlx-lm uses its own defaults and the request stays small.
    private func nonZeroOrNil(_ value: Double) -> Double? {
        value == 0 ? nil : value
    }

    /// Repetition penalty default is 1.0 (multiplicative identity).
    private func nonOneOrNil(_ value: Double) -> Double? {
        value == 1.0 ? nil : value
    }

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
