import Foundation

// MARK: - Chat completion request

/// A single message in the chat history. Matches the OpenAI /v1/chat/completions
/// wire format, which is what mlx-lm's server accepts.
struct ChatMessage: Codable, Equatable, Sendable {
    let role: String
    let content: String
}

/// Request body for `POST /v1/chat/completions`. Only fields mlx-lm honors are
/// modeled — we leave out things like tools/logit_bias/logprobs for v1.
struct ChatRequest: Codable, Equatable, Sendable {
    let model: String
    let messages: [ChatMessage]
    let stream: Bool
    let temperature: Double
    let topP: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, temperature
        case topP = "top_p"
        case maxTokens = "max_tokens"
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

// MARK: - Chat completion streaming chunks

/// One SSE `data: { ... }` frame in the chat completion stream.
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
