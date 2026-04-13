import XCTest
@testable import LocalMLX

final class MLXClientTests: XCTestCase {

    let baseURL = URL(string: "http://localhost:8080")!

    override func tearDown() {
        super.tearDown()
        MockURLProtocol.reset()
    }

    // MARK: - Setup helpers

    private func makeClient() -> LiveMLXClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        config.timeoutIntervalForRequest = 5
        let session = URLSession(configuration: config)
        return LiveMLXClient(session: session, baseURL: { [baseURL] in baseURL })
    }

    private func sampleRequest() -> ChatRequest {
        ChatRequest(
            model: "test-model",
            messages: [ChatMessage(role: "user", content: "hi")],
            stream: true,
            temperature: 0.7,
            topP: 1.0,
            maxTokens: 128
        )
    }

    // MARK: - listModels

    func test_listModels_returnsIDsOn200() async throws {
        let fixture = try TestBundle.loadFixture("models_list", ext: "json")
        MockURLProtocol.handler = { [baseURL] request in
            XCTAssertEqual(request.url?.path, "/v1/models")
            XCTAssertEqual(request.httpMethod, "GET")
            return MockURLProtocol.json(fixture, url: baseURL.appendingPathComponent("v1/models"))
        }

        let client = makeClient()
        let ids = try await client.listModels()

        XCTAssertEqual(ids.count, 3)
        XCTAssertTrue(ids.contains("mlx-community/Llama-3.2-3B-Instruct-4bit"))
    }

    func test_listModels_throwsHTTP404() async {
        MockURLProtocol.handler = { [baseURL] _ in
            let body = Data("""
            { "error": { "message": "not found" } }
            """.utf8)
            let response = HTTPURLResponse(
                url: baseURL.appendingPathComponent("v1/models"),
                statusCode: 404, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return .success(.init(response: response, body: body))
        }

        let client = makeClient()
        do {
            _ = try await client.listModels()
            XCTFail("Expected .http error")
        } catch let error as MLXClientError {
            guard case .http(let status, let message) = error else {
                return XCTFail("Expected .http, got \(error)")
            }
            XCTAssertEqual(status, 404)
            XCTAssertEqual(message, "not found")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_listModels_mapsCannotConnectToUnreachable() async {
        MockURLProtocol.handler = { _ in
            .failure(URLError(.cannotConnectToHost))
        }
        let client = makeClient()
        do {
            _ = try await client.listModels()
            XCTFail("Expected unreachable error")
        } catch let error as MLXClientError {
            guard case .unreachable = error else {
                return XCTFail("Expected .unreachable, got \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    // MARK: - streamChat

    func test_streamChat_yieldsDeltaEventsFromFixture() async throws {
        let body = try TestBundle.loadFixtureString("chat_completion_stream", ext: "txt")
        let frames = body
            .components(separatedBy: "\n\n")
            .filter { !$0.isEmpty }
            .map { $0 + "\n\n" }

        MockURLProtocol.handler = { [baseURL] request in
            XCTAssertEqual(request.url?.path, "/v1/chat/completions")
            XCTAssertEqual(request.httpMethod, "POST")
            return MockURLProtocol.sse(
                chunks: frames,
                url: baseURL.appendingPathComponent("v1/chat/completions"))
        }

        let client = makeClient()
        var collected: [String] = []
        for try await event in try await client.streamChat(sampleRequest()) {
            if case .delta(let d) = event { collected.append(d) }
        }
        XCTAssertEqual(collected, ["Hello", ", ", "world", "!"])
    }

    func test_streamChat_emitsUsageEvent_whenServerSendsUsage() async throws {
        // Two deltas, then a final chunk with `usage`, then [DONE].
        let frames = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"abc\"}}]}\n\n",
            "data: {\"choices\":[{\"delta\":{\"content\":\"def\"}}]}\n\n",
            "data: {\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":6,\"total_tokens\":11}}\n\n",
            "data: [DONE]\n\n",
        ]

        MockURLProtocol.handler = { [baseURL] _ in
            MockURLProtocol.sse(chunks: frames,
                                url: baseURL.appendingPathComponent("v1/chat/completions"))
        }

        let client = makeClient()
        var deltas: [String] = []
        var usage: UsageStats?

        for try await event in try await client.streamChat(sampleRequest()) {
            switch event {
            case .delta(let d): deltas.append(d)
            case .usage(let u): usage = u
            }
        }

        XCTAssertEqual(deltas, ["abc", "def"])
        XCTAssertEqual(usage?.promptTokens, 5)
        XCTAssertEqual(usage?.completionTokens, 6)
        XCTAssertEqual(usage?.totalTokens, 11)
    }

    func test_streamChat_on4xx_throwsDecodedServerMessage() async throws {
        MockURLProtocol.handler = { [baseURL] _ in
            let errJSON = Data("""
            { "error": { "message": "no such model", "type": "invalid_request_error" } }
            """.utf8)
            let response = HTTPURLResponse(
                url: baseURL.appendingPathComponent("v1/chat/completions"),
                statusCode: 400, httpVersion: nil,
                headerFields: ["Content-Type": "application/json"])!
            return .success(.init(response: response, body: errJSON))
        }

        let client = makeClient()
        do {
            let stream = try await client.streamChat(sampleRequest())
            for try await _ in stream {
                XCTFail("Should not yield any events")
            }
            XCTFail("Expected error")
        } catch let error as MLXClientError {
            guard case .http(let status, let message) = error else {
                return XCTFail("Expected .http, got \(error)")
            }
            XCTAssertEqual(status, 400)
            XCTAssertEqual(message, "no such model")
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func test_streamChat_cancellation_stopsMidStreamWithCancellationError() async throws {
        let frames: [String] = (0..<10).map { i in
            "data: {\"choices\":[{\"delta\":{\"content\":\"tok\(i)\"}}]}\n\n"
        }

        MockURLProtocol.handler = { [baseURL] _ in
            MockURLProtocol.sse(
                chunks: frames,
                interval: 0.1,
                url: baseURL.appendingPathComponent("v1/chat/completions"))
        }

        let client = makeClient()
        var partial: [String] = []

        let task = Task {
            do {
                let stream = try await client.streamChat(sampleRequest())
                for try await event in stream {
                    if case .delta(let d) = event { partial.append(d) }
                    if partial.count == 2 { break }
                }
            } catch {
                if let urlErr = error as? URLError, urlErr.code == .cancelled { return }
                if error is CancellationError { return }
                if case MLXClientError.canceled = error { return }
                XCTFail("Unexpected error: \(error)")
            }
        }

        await task.value
        XCTAssertLessThanOrEqual(partial.count, 3)
        XCTAssertGreaterThanOrEqual(partial.count, 1)
    }
}
