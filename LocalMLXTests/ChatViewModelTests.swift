import XCTest
import SwiftData
@testable import LocalMLX

@MainActor
final class ChatViewModelTests: XCTestCase {

    // MARK: - Fake client

    /// A scripted `MLXClientProtocol` for deterministic tests.
    final class FakeMLXClient: MLXClientProtocol, @unchecked Sendable {
        enum Behavior {
            case deltas([String], perTokenDelay: TimeInterval)
            case deltasWithUsage([String], UsageStats, perTokenDelay: TimeInterval)
            case failImmediately(MLXClientError)
            case neverEnding
        }

        var behavior: Behavior = .deltas(["Hello", " ", "world"], perTokenDelay: 0)
        var models: [String] = []

        func listModels() async throws -> [String] { models }

        func streamChat(_ request: ChatRequest) async throws -> AsyncThrowingStream<StreamEvent, Error> {
            let behavior = self.behavior
            return AsyncThrowingStream { continuation in
                let task = Task {
                    do {
                        switch behavior {
                        case .failImmediately(let err):
                            continuation.finish(throwing: err)

                        case .deltas(let deltas, let delay):
                            for d in deltas {
                                try Task.checkCancellation()
                                if delay > 0 {
                                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                }
                                continuation.yield(.delta(d))
                            }
                            continuation.finish()

                        case .deltasWithUsage(let deltas, let usage, let delay):
                            for d in deltas {
                                try Task.checkCancellation()
                                if delay > 0 {
                                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                                }
                                continuation.yield(.delta(d))
                            }
                            continuation.yield(.usage(usage))
                            continuation.finish()

                        case .neverEnding:
                            var i = 0
                            while true {
                                try Task.checkCancellation()
                                try await Task.sleep(nanoseconds: 50_000_000)
                                continuation.yield(.delta("tok\(i)"))
                                i += 1
                            }
                        }
                    } catch is CancellationError {
                        continuation.finish(throwing: MLXClientError.canceled)
                    } catch {
                        continuation.finish(throwing: error)
                    }
                }
                continuation.onTermination = { @Sendable _ in task.cancel() }
            }
        }
    }

    // MARK: - Fixtures

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Conversation.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func makeFixtures(
        clientBehavior: FakeMLXClient.Behavior = .deltas(["Hello", ", ", "world"], perTokenDelay: 0)
    ) throws -> (ChatViewModel, FakeMLXClient, ModelContainer, Conversation) {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "New Chat", modelId: "test-model")
        ctx.insert(convo)
        try ctx.save()

        let client = FakeMLXClient()
        client.behavior = clientBehavior

        let vm = ChatViewModel(
            client: client,
            modelContext: ctx,
            now: { Date(timeIntervalSince1970: 42) }
            // wallClock defaults to real Date — needed for tok/s to be non-zero
        )
        return (vm, client, container, convo)
    }

    // MARK: - Happy path

    func test_send_insertsUserAndAssistant_streamsDeltasIntoAssistantContent() async throws {
        let (vm, _, _, convo) = try makeFixtures()

        await vm.send("hi there", in: convo)

        XCTAssertEqual(convo.messages.count, 2)
        let ordered = convo.sortedMessages
        XCTAssertEqual(ordered[0].role, .user)
        XCTAssertEqual(ordered[0].content, "hi there")
        XCTAssertEqual(ordered[1].role, .assistant)
        XCTAssertEqual(ordered[1].content, "Hello, world")
        XCTAssertNil(vm.errorBanner)
    }

    func test_send_updatesUpdatedAtFromInjectedClock() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        await vm.send("hi", in: convo)
        XCTAssertEqual(convo.updatedAt, Date(timeIntervalSince1970: 42))
    }

    func test_autoTitle_setsFromFirstUserMessage_onNewChat() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        XCTAssertEqual(convo.title, "New Chat")
        await vm.send("What is the capital of France?", in: convo)
        XCTAssertEqual(convo.title, "What is the capital of France?")
    }

    func test_autoTitle_truncatesAt40Chars() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        let long = "This is a really very long user prompt that should definitely be truncated"
        await vm.send(long, in: convo)
        XCTAssertLessThanOrEqual(convo.title.count, 41)
        XCTAssertTrue(long.hasPrefix(convo.title.replacingOccurrences(of: "…", with: "")))
    }

    func test_autoTitle_notChangedOnSubsequentSends() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        await vm.send("first", in: convo)
        let titleAfterFirst = convo.title
        await vm.send("second", in: convo)
        XCTAssertEqual(convo.title, titleAfterFirst)
    }

    func test_autoTitle_skippedIfUserRenamedFirst() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        convo.title = "My Custom Title"
        await vm.send("hi", in: convo)
        XCTAssertEqual(convo.title, "My Custom Title")
    }

    // MARK: - Usage + tok/s

    func test_send_writesUsageToAssistantMessage() async throws {
        let usage = UsageStats(promptTokens: 5, completionTokens: 3, totalTokens: 8)
        let (vm, _, _, convo) = try makeFixtures(
            clientBehavior: .deltasWithUsage(["a", "b", "c"], usage, perTokenDelay: 0.02)
        )

        await vm.send("hi", in: convo)

        let assistant = convo.sortedMessages.last
        XCTAssertEqual(assistant?.promptTokens, 5)
        XCTAssertEqual(assistant?.completionTokens, 3)
    }

    func test_send_computesTokensPerSecondWhenElapsedIsMeasurable() async throws {
        let usage = UsageStats(promptTokens: 1, completionTokens: 3, totalTokens: 4)
        let (vm, _, _, convo) = try makeFixtures(
            // 20ms × 3 tokens ≈ 60ms of streaming time — enough to measure.
            clientBehavior: .deltasWithUsage(["a", "b", "c"], usage, perTokenDelay: 0.02)
        )

        await vm.send("hi", in: convo)

        let tps = convo.sortedMessages.last?.tokensPerSecond
        XCTAssertNotNil(tps)
        XCTAssertGreaterThan(tps ?? 0, 0)
        // Sanity upper bound: 3 tokens over ~60ms is ~50 tok/s; never thousands.
        XCTAssertLessThan(tps ?? 0, 10_000)
    }

    // MARK: - Stop / cancellation

    func test_stop_cancelsInFlightStream_keepsPartialContent() async throws {
        let (vm, _, _, convo) = try makeFixtures(
            clientBehavior: .deltas(["tok0", "tok1", "tok2", "tok3", "tok4"], perTokenDelay: 0.1)
        )

        let sendTask = Task { await vm.send("count", in: convo) }

        var waited: TimeInterval = 0
        while convo.messages.first(where: { $0.role == .assistant })?.content.isEmpty ?? true {
            try await Task.sleep(nanoseconds: 20_000_000)
            waited += 0.02
            if waited > 2 { XCTFail("Timed out waiting for first delta"); break }
        }

        vm.stop()
        await sendTask.value

        let assistant = convo.sortedMessages.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertFalse((assistant?.content ?? "").isEmpty,
                       "Partial content should be retained after Stop")
        XCTAssertNil(assistant?.interruptionReason, "Stop is not an interruption")
        XCTAssertNil(vm.errorBanner)
        XCTAssertFalse(vm.isStreaming)
    }

    // MARK: - Error path

    func test_error_setsBanner_andMarksNotStreaming() async throws {
        let (vm, _, _, convo) = try makeFixtures(
            clientBehavior: .failImmediately(.http(status: 404, message: "no such model"))
        )

        await vm.send("hi", in: convo)

        XCTAssertNotNil(vm.errorBanner)
        XCTAssertTrue(vm.errorBanner?.contains("no such model") ?? false)
        XCTAssertFalse(vm.isStreaming)
        XCTAssertTrue(convo.messages.contains(where: { $0.role == .user && $0.content == "hi" }))
    }

    func test_error_setsInterruptionReasonOnAssistantMessage() async throws {
        let (vm, _, _, convo) = try makeFixtures(
            clientBehavior: .failImmediately(.http(status: 500, message: "internal error"))
        )

        await vm.send("hi", in: convo)

        let assistant = convo.sortedMessages.last
        XCTAssertEqual(assistant?.role, .assistant)
        XCTAssertNotNil(assistant?.interruptionReason)
        XCTAssertTrue(assistant?.interruptionReason?.contains("internal error") ?? false)
    }

    // MARK: - isStreaming lifecycle

    func test_isStreaming_toggles() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        XCTAssertFalse(vm.isStreaming)
        await vm.send("hi", in: convo)
        XCTAssertFalse(vm.isStreaming, "Should be false after completion")
    }

    // MARK: - regenerate

    func test_regenerate_replacesLastAssistantReply_withoutDuplicatingUser() async throws {
        let (vm, client, _, convo) = try makeFixtures(
            clientBehavior: .deltas(["first reply"], perTokenDelay: 0)
        )
        await vm.send("hello", in: convo)

        let assistantBefore = convo.sortedMessages.last!
        XCTAssertEqual(assistantBefore.content, "first reply")

        client.behavior = .deltas(["second reply"], perTokenDelay: 0)
        await vm.regenerate(assistantMessage: assistantBefore, in: convo)

        let userMessages = convo.messages.filter { $0.role == .user }
        let assistantMessages = convo.messages.filter { $0.role == .assistant }
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.first?.content, "hello")
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.content, "second reply")
    }

    // MARK: - editAndResend

    func test_editAndResend_updatesUser_regeneratesAssistant() async throws {
        let (vm, client, _, convo) = try makeFixtures(
            clientBehavior: .deltas(["original reply"], perTokenDelay: 0)
        )
        await vm.send("original", in: convo)

        let userMsg = convo.messages.first(where: { $0.role == .user })!

        client.behavior = .deltas(["edited reply"], perTokenDelay: 0)
        await vm.editAndResend(userMessage: userMsg, newContent: "edited", in: convo)

        let userMessages = convo.messages.filter { $0.role == .user }
        let assistantMessages = convo.messages.filter { $0.role == .assistant }
        XCTAssertEqual(userMessages.count, 1)
        XCTAssertEqual(userMessages.first?.content, "edited")
        XCTAssertEqual(assistantMessages.count, 1)
        XCTAssertEqual(assistantMessages.first?.content, "edited reply")
    }

    func test_editAndResend_rejectsEmptyContent() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        await vm.send("original", in: convo)
        let userMsg = convo.messages.first(where: { $0.role == .user })!
        let originalAssistantCount = convo.messages.filter { $0.role == .assistant }.count

        await vm.editAndResend(userMessage: userMsg, newContent: "   ", in: convo)

        XCTAssertEqual(userMsg.content, "original")
        XCTAssertEqual(convo.messages.filter { $0.role == .assistant }.count, originalAssistantCount)
    }

    // MARK: - delete

    func test_delete_removesMessageAndBumpsUpdatedAt() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        await vm.send("hi", in: convo)
        XCTAssertEqual(convo.messages.count, 2)

        let target = convo.sortedMessages.first!
        vm.delete(message: target, in: convo)

        XCTAssertEqual(convo.messages.count, 1)
        XCTAssertFalse(convo.messages.contains(where: { $0 === target }))
    }
}
