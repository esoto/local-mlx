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
            case failImmediately(MLXClientError)
            case neverEnding // yields forever until cancelled
        }

        var behavior: Behavior = .deltas(["Hello", " ", "world"], perTokenDelay: 0)
        var models: [String] = []

        func listModels() async throws -> [String] { models }

        func streamChat(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, Error> {
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
                                continuation.yield(d)
                            }
                            continuation.finish()

                        case .neverEnding:
                            var i = 0
                            while true {
                                try Task.checkCancellation()
                                try await Task.sleep(nanoseconds: 50_000_000)
                                continuation.yield("tok\(i)")
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
        XCTAssertLessThanOrEqual(convo.title.count, 41) // 40 + optional ellipsis
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

    // MARK: - Stop / cancellation

    func test_stop_cancelsInFlightStream_keepsPartialContent() async throws {
        let (vm, _, _, convo) = try makeFixtures(
            clientBehavior: .deltas(["tok0", "tok1", "tok2", "tok3", "tok4"], perTokenDelay: 0.1)
        )

        let sendTask = Task { await vm.send("count", in: convo) }

        // Wait until we've streamed at least one delta.
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
        // Stop is a user action, not an error — banner stays nil.
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
        // User message is still visible (so retry is possible).
        XCTAssertTrue(convo.messages.contains(where: { $0.role == .user && $0.content == "hi" }))
    }

    // MARK: - isStreaming flag lifecycle

    func test_isStreaming_toggles() async throws {
        let (vm, _, _, convo) = try makeFixtures()
        XCTAssertFalse(vm.isStreaming)
        await vm.send("hi", in: convo)
        XCTAssertFalse(vm.isStreaming, "Should be false after completion")
    }
}
