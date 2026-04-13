import Foundation
import SwiftData

/// Roles recognized by the OpenAI-compatible chat API.
enum MessageRole: String, Codable, Sendable {
    case system
    case user
    case assistant
}

@Model
final class Message {
    @Attribute(.unique) var id: UUID
    var roleRaw: String
    var content: String
    var createdAt: Date
    var conversation: Conversation?

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
         conversation: Conversation? = nil) {
        self.id = id
        self.roleRaw = role.rawValue
        self.content = content
        self.createdAt = createdAt
        self.conversation = conversation
    }
}
