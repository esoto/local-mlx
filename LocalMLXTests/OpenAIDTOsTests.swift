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

    func test_chatRequest_encodesExtraSamplingParams_whenSet() throws {
        let request = ChatRequest(
            model: "m",
            messages: [ChatMessage(role: "user", content: "hi")],
            stream: true,
            temperature: 0.7,
            topP: 1.0,
            maxTokens: 128,
            presencePenalty: 0.3,
            frequencyPenalty: 0.4,
            repetitionPenalty: 1.1,
            seed: 42,
            streamOptions: .init(includeUsage: true)
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["presence_penalty"] as? Double, 0.3)
        XCTAssertEqual(json["frequency_penalty"] as? Double, 0.4)
        XCTAssertEqual(json["repetition_penalty"] as? Double, 1.1)
        XCTAssertEqual(json["seed"] as? Int, 42)

        let streamOpts = try XCTUnwrap(json["stream_options"] as? [String: Any])
        XCTAssertEqual(streamOpts["include_usage"] as? Bool, true)
    }

    func test_chatRequest_omitsExtraSamplingParams_whenNil() throws {
        let request = ChatRequest(
            model: "m",
            messages: [ChatMessage(role: "user", content: "hi")],
            stream: true,
            temperature: 0.7,
            topP: 1.0,
            maxTokens: 128
        )

        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertNil(json["presence_penalty"])
        XCTAssertNil(json["frequency_penalty"])
        XCTAssertNil(json["repetition_penalty"])
        XCTAssertNil(json["seed"])
        XCTAssertNil(json["stream_options"])
    }

    func test_chatRequest_omitsSystemMessageWhenEmpty_whenConstructedFromConversation() throws {
        // The helper used by ChatViewModel should drop an empty system prompt.
        let messages = ChatRequest.buildMessages(
            systemPrompt: "",
            history: [
                ChatHistoryEntry(role: "user", text: "hi"),
                ChatHistoryEntry(role: "assistant", text: "hello")
            ]
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages.first?.role, "user")
    }

    func test_chatRequest_includesSystemMessageWhenPresent() throws {
        let messages = ChatRequest.buildMessages(
            systemPrompt: "  be terse  ",
            history: [ChatHistoryEntry(role: "user", text: "hi")]
        )
        XCTAssertEqual(messages.count, 2)
        XCTAssertEqual(messages[0].role, "system")
        XCTAssertEqual(messages[0].content, .text("be terse"))
        XCTAssertEqual(messages[1].role, "user")
    }

    // MARK: - Multimodal content encoding

    func test_messageContent_text_encodesAsPlainJSONString() throws {
        // Critical for backwards compat: a text-only message must NOT
        // become a one-element array because non-vision mlx-lm builds
        // still expect `content: "..."` in the plain string form.
        let msg = ChatMessage(role: "user", content: .text("hello"))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(msg)
        let str = String(data: data, encoding: .utf8)!
        XCTAssertEqual(str, #"{"content":"hello","role":"user"}"#)
    }

    func test_messageContent_parts_encodesAsJSONArray() throws {
        let msg = ChatMessage(
            role: "user",
            content: .parts([
                .text("What is in this picture?"),
                .imageURL("data:image/jpeg;base64,AAAA"),
            ])
        )
        let data = try JSONEncoder().encode(msg)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        let content = try XCTUnwrap(json["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "What is in this picture?")

        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/jpeg;base64,AAAA")
    }

    func test_contentPart_text_hasExactOpenAIShape() throws {
        let data = try JSONEncoder().encode(ContentPart.text("hi"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "text")
        XCTAssertEqual(json["text"] as? String, "hi")
        XCTAssertEqual(json.keys.sorted(), ["text", "type"])
    }

    func test_contentPart_imageURL_wrapsURLInNestedObject() throws {
        // OpenAI's shape is `"image_url": {"url": "..."}`, not a bare string.
        let data = try JSONEncoder().encode(
            ContentPart.imageURL("data:image/png;base64,ZZZ"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(json["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,ZZZ")
    }

    func test_messageContent_expressibleByStringLiteral_producesTextCase() {
        // Existing text-only call sites pass string literals directly.
        let content: MessageContent = "literal"
        XCTAssertEqual(content, .text("literal"))
    }

    // MARK: - buildMessages with attachments

    func test_buildMessages_withAttachments_producesContentPartsArray() {
        let attachment = ChatHistoryEntry.Attachment(
            data: Data([0xFF, 0xD8]),   // JPEG magic bytes, just for the test
            mimeType: "image/jpeg")
        let messages = ChatRequest.buildMessages(
            systemPrompt: "",
            history: [
                ChatHistoryEntry(role: "user",
                                 text: "describe this",
                                 attachments: [attachment])
            ])
        XCTAssertEqual(messages.count, 1)
        guard case .parts(let parts) = messages[0].content else {
            XCTFail("expected parts for a message with attachments")
            return
        }
        XCTAssertEqual(parts.count, 2)
        XCTAssertEqual(parts[0], .text("describe this"))
        // Base64 of [0xFF, 0xD8] is "/9g="
        XCTAssertEqual(parts[1], .imageURL("data:image/jpeg;base64,/9g="))
    }

    func test_buildMessages_withEmptyTextAndAttachment_omitsEmptyTextPart() {
        // If the user just drops an image without typing anything, we
        // shouldn't emit a blank text part — just the image.
        let attachment = ChatHistoryEntry.Attachment(
            data: Data([0x89]), mimeType: "image/png")
        let messages = ChatRequest.buildMessages(
            systemPrompt: "",
            history: [
                ChatHistoryEntry(role: "user",
                                 text: "",
                                 attachments: [attachment])
            ])
        guard case .parts(let parts) = messages[0].content else {
            XCTFail("expected parts")
            return
        }
        XCTAssertEqual(parts.count, 1)
        XCTAssertEqual(parts[0], .imageURL("data:image/png;base64,iQ=="))
    }

    func test_buildMessages_noAttachments_stillUsesPlainStringContent() {
        // Sanity check: removing attachments must leave the wire
        // format untouched for existing text-only servers.
        let messages = ChatRequest.buildMessages(
            systemPrompt: "",
            history: [ChatHistoryEntry(role: "user", text: "hi")])
        XCTAssertEqual(messages[0].content, .text("hi"))
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

    func test_chatChunk_decodesUsage_whenPresent() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [],
          "usage": {
            "prompt_tokens": 13,
            "completion_tokens": 42,
            "total_tokens": 55
          }
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        XCTAssertEqual(chunk.usage?.promptTokens, 13)
        XCTAssertEqual(chunk.usage?.completionTokens, 42)
        XCTAssertEqual(chunk.usage?.totalTokens, 55)
    }

    func test_chatChunk_usageIsNil_whenAbsent() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [{ "index": 0, "delta": { "content": "x" }, "finish_reason": null }]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(ChatChunk.self, from: json)
        XCTAssertNil(chunk.usage)
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
