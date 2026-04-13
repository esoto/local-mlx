import Foundation
import SwiftData

/// Roles recognized by the OpenAI-compatible chat API.
enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

@Model
final class Message: Identifiable {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var conversation: Conversation?

    /// Inline image attachments for multimodal messages. Cascading
    /// delete keeps things tidy: when the message is removed, its
    /// image blobs go with it. Lightweight-migrates from stores that
    /// predate the attachments model because the relationship
    /// defaults to an empty array.
    @Relationship(deleteRule: .cascade, inverse: \MessageAttachment.message)
    var attachments: [MessageAttachment] = []

    /// Computed tokens/sec for this assistant reply (from elapsed time and
    /// either server-reported `completion_tokens` or the delta count).
    /// nil for user messages and messages generated before tok/s tracking.
    var tokensPerSecond: Double?

    /// Server-reported prompt tokens (from the final streaming `usage`
    /// chunk). nil if the server didn't emit one.
    var promptTokens: Int?

    /// Server-reported completion tokens.
    var completionTokens: Int?

    /// If the stream ended in an error (but not user cancellation), the
    /// reason is stored here so the UI can show "(stream interrupted: …)".
    var interruptionReason: String?

    /// `role` is stored as a raw string so SwiftData can persist it cleanly
    /// (SwiftData doesn't support enum types directly in every Xcode version).
    var role: MessageRole {
        get { MessageRole(rawValue: roleRaw) ?? .assistant }
        set { roleRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(),
         role: MessageRole,
         content: String,
         createdAt: Date = .now,
         conversation: Conversation? = nil,
         tokensPerSecond: Double? = nil,
         promptTokens: Int? = nil,
         completionTokens: Int? = nil,
         interruptionReason: String? = nil) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.conversation = conversation
        self.tokensPerSecond = tokensPerSecond
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.interruptionReason = interruptionReason
    }
}
