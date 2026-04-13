import Foundation

// MARK: - Chat completion request

/// A single message in the chat history. Matches the OpenAI /v1/chat/completions
/// wire format, which is what mlx-lm's server accepts.
struct ChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
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

    /// Build the `messages` array from a system prompt + history, trimming and
    /// dropping an empty system prompt. Kept here (rather than in the view
    /// model) so it has a direct unit test.
    static func buildMessages(
        systemPrompt: String,
        history: [(role: String, content: String)]
    ) -> [ChatMessage] {
        var out: [ChatMessage] = []
        let trimmedSystem = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedSystem.isEmpty {
            out.append(ChatMessage(role: "system", content: trimmedSystem))
        }
        for item in history {
            out.append(ChatMessage(role: item.role, content: item.content))
        }
        return out
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
