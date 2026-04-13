import Foundation

// MARK: - Chat completion request

/// A single message in the chat history. Matches the OpenAI /v1/chat/completions
/// wire format, which both `mlx_lm.server` and `mlx_vlm.server` accept.
struct ChatMessage: Encodable, Equatable, Sendable {
    let role: String
    let content: MessageContent
}

/// Body of a chat message. OpenAI accepts either a bare string (for
/// text-only chat) or an array of content parts (for multimodal input).
/// We encode the plain-string form whenever the message is a single
/// text part so that non-vision servers — which may not understand the
/// array form — keep working unchanged. As soon as an image is attached
/// we switch to the array form.
enum MessageContent: Equatable, Sendable {
    case text(String)
    case parts([ContentPart])
}

extension MessageContent: ExpressibleByStringLiteral {
    init(stringLiteral value: String) { self = .text(value) }
}

extension MessageContent: Encodable {
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let text):
            try container.encode(text)
        case .parts(let parts):
            try container.encode(parts)
        }
    }
}

/// One piece of a multimodal message. Encoded in the OpenAI vision
/// shape: `{"type": "text", "text": "..."}` for text, and
/// `{"type": "image_url", "image_url": {"url": "data:image/...;base64,..."}}`
/// for inline images.
enum ContentPart: Equatable, Sendable {
    case text(String)
    case imageURL(String)
}

extension ContentPart: Encodable {
    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageUrl = "image_url"
    }

    private struct ImageURLPayload: Encodable {
        let url: String
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let text):
            try container.encode("text", forKey: .type)
            try container.encode(text, forKey: .text)
        case .imageURL(let dataURL):
            try container.encode("image_url", forKey: .type)
            try container.encode(ImageURLPayload(url: dataURL), forKey: .imageUrl)
        }
    }
}

/// Inputs to `ChatRequest.buildMessages`. A tuple-of-3 became unwieldy
/// once attachments entered the picture, so each history entry is now
/// a small struct. Attachments carry raw image bytes which get encoded
/// as `data:image/...;base64,...` URLs on the wire.
struct ChatHistoryEntry: Sendable {
    struct Attachment: Sendable {
        let data: Data
        let mimeType: String
    }

    let role: String
    let text: String
    let attachments: [Attachment]

    init(role: String, text: String, attachments: [Attachment] = []) {
        self.role = role
        self.text = text
        self.attachments = attachments
    }
}

/// Request body for `POST /v1/chat/completions`. Only fields mlx-lm honors
/// are modeled. Extra sampling params and `stream_options` are optional and
/// omitted from the encoded JSON when nil.
struct ChatRequest: Encodable, Equatable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double
    let topP: Double
    let maxTokens: Int
    var presencePenalty: Double?
    var frequencyPenalty: Double?
    var repetitionPenalty: Double?
    var seed: Int?
    var streamOptions: StreamOptions?

    /// OpenAI streaming options. We only care about `include_usage`, which
    /// asks the server to emit a final chunk with token counts.
    struct StreamOptions: Encodable, Equatable, Sendable {
        let includeUsage: Bool
        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    init(model: String,
         messages: [ChatMessage],
         stream: Bool,
         temperature: Double,
         topP: Double,
         maxTokens: Int,
         presencePenalty: Double? = nil,
         frequencyPenalty: Double? = nil,
         repetitionPenalty: Double? = nil,
         seed: Int? = nil,
         streamOptions: StreamOptions? = nil) {
        self.model = model
        self.messages = messages
        self.stream = stream
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
        self.streamOptions = streamOptions
    }

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
        case presencePenalty = "presence_penalty"
        case frequencyPenalty = "frequency_penalty"
        case repetitionPenalty = "repetition_penalty"
        case seed
        case streamOptions = "stream_options"
    }

    /// Build the `messages` array from a system prompt + history, trimming
    /// and dropping an empty system prompt. Messages with one or more
    /// attachments are emitted as an array of content parts
    /// (`[text, image_url, image_url, ...]`) in the OpenAI vision shape;
    /// text-only messages stay in the plain-string form so non-vision
    /// servers accept them unchanged. Kept here rather than in the view
    /// model so it has a direct unit test.
    static func buildMessages(
        systemPrompt: String,
        history: [ChatHistoryEntry]
    ) -> [ChatMessage] {
        var out: [ChatMessage] = []
        let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            out.append(ChatMessage(role: "system", content: .text(trimmedSystem)))
        }
        for item in history {
            out.append(ChatMessage(role: item.role, content: makeContent(from: item)))
        }
        return out
    }

    private static func makeContent(from entry: ChatHistoryEntry) -> MessageContent {
        guard !entry.attachments.isEmpty else {
            return .text(entry.text)
        }
        var parts: [ContentPart] = []
        if !entry.text.isEmpty {
            parts.append(.text(entry.text))
        }
        for attachment in entry.attachments {
            let base64 = attachment.data.base64EncodedString()
            let dataURL = "data:\(attachment.mimeType);base64,\(base64)"
            parts.append(.imageURL(dataURL))
        }
        return .parts(parts)
    }
}

// MARK: - Usage stats

/// Token counts from the OpenAI `usage` field on the final streaming chunk
/// (when `stream_options.include_usage: true`) or from a non-streaming reply.
struct UsageStats: Codable, Equatable, Sendable {
    let promptTokens: Int
    let completionTokens: Int
    let totalTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
    }
}

// MARK: - Chat completion streaming chunks

/// One SSE `data: { ... }` frame in the chat completion stream.
/// `choices` may be empty on the final usage-only chunk.
struct ChatChunk: Decodable, Sendable {
    struct Choice: Decodable, Sendable {
        struct Delta: Decodable, Sendable {
            let role: String?
            let content: String?
        }

        let index: Int?
        let delta: Delta
        let finishReason: String?

        enum CodingKeys: String, CodingKey {
            case index, delta
            case finishReason = "finish_reason"
        }
    }

    let id: String?
    let choices: [Choice]
    let usage: UsageStats?
}

// MARK: - Model listing

/// Response from `GET /v1/models`.
struct ModelList: Decodable, Sendable {
    struct Model: Decodable, Sendable, Identifiable {
        let id: String
        let created: Int?
    }

    let data: [Model]
}

// MARK: - Server error body

/// mlx-lm (and most OpenAI-compatible servers) return `{ "error": { "message": ... } }`
/// on 4xx/5xx responses. We try to decode this best-effort to show a useful banner.
struct ServerErrorBody: Decodable, Sendable {
    struct ErrorDetail: Decodable, Sendable {
        let message: String
        let type: String?
    }
    let error: ErrorDetail
}
