import XCTest
@testable import LocalMLX

final class OpenAIDTOsTests: XCTestCase {

    // MARK: - ChatRequest encoding

    func test_chatRequest_encodesExpectedJSONShape() throws {
        let request = ChatRequest(
            model: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            messages: [
                ChatMessage(role: "system", content: "You are helpful."),
                ChatMessage(role: "user", content: "Hello")
            ],
            stream: true,
            temperature: 0.7,
            topP: 1.0,
            maxTokens: 1024
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["model"] as? String, "mlx-community/Llama-3.2-3B-Instruct-4bit")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["temperature"] as? Double, 0.7)
        XCTAssertEqual(json["top_p"] as? Double, 1.0)
        XCTAssertEqual(json["max_tokens"] as? Int, 1024)

        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0]["role"] as? String, "system")
        XCTAssertEqual(messages[0]["content"] as? String, "You are helpful.")
        XCTAssertEqual(messages[1]["role"] as? String, "user")
        XCTAssertEqual(messages[1]["content"] as? String, "Hello")
    }

    func test_chatRequest_omitsSystemMessageWhenEmpty_whenConstructedFromConversation() throws {
        // The helper used by ChatViewModel should drop an empty system prompt.
        let messages = ChatRequest.buildMessages(
            systemPrompt: "",
            history: [
                (role: "user", content: "hi"),
                (role: "assistant", content: "hello")
            ]
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.role, "user")
    }

    func test_chatRequest_includesSystemMessageWhenPresent() throws {
        let messages = ChatRequest.buildMessages(
            systemPrompt: "  be terse  ",
            history: [(role: "user", content: "hi")]
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[0].content, "be terse")
        XCTAssertEqual(messages[1].role, "user")
    }

    // MARK: - ChatChunk decoding

    func test_chatChunk_decodesContentDelta() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [
            { "index": 0,
              "delta": { "content": "Hello" },
              "finish_reason": null }
          ]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.delta.content, "Hello")
        XCTAssertNil(chunk.choices.first?.finishReason)
    }

    func test_chatChunk_decodesRoleOnlyDelta_withNilContent() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [
            { "index": 0,
              "delta": { "role": "assistant" },
              "finish_reason": null }
          ]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        XCTAssertNil(chunk.choices.first?.delta.content)
    }

    func test_chatChunk_decodesFinishReason() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [
            { "index": 0, "delta": {}, "finish_reason": "stop" }
          ]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        XCTAssertEqual(chunk.choices.first?.finishReason, "stop")
    }

    // MARK: - ModelList decoding

    func test_modelList_decodesFromFixture() throws {
        let data = try TestBundle.loadFixture("models_list", ext: "json")
        let list = try JSONDecoder().decode(ModelList.self, from: data)
        XCTAssertEqual(list.data.count, 3)
        XCTAssertEqual(list.data.first?.id, "mlx-community/Llama-3.2-3B-Instruct-4bit")
    }

    // MARK: - Server error shape

    func test_serverError_decodesNestedMessage() throws {
        let json = """
        { "error": { "message": "No such model", "type": "invalid_request_error" } }
        """.data(using: .utf8)!
        let error = try JSONDecoder().decode(ServerErrorBody.self, from: json)
        XCTAssertEqual(error.error.message, "No such model")
    }
}
