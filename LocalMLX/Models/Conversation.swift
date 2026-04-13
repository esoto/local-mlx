import Foundation
import SwiftData

@Model
final class Conversation {
    @Attribute(.unique) var id: UUID
    var title: String
    var createdAt: Date
    var updatedAt: Date
    var systemPrompt: String
    var modelId: String?
    var temperature: Double
    var topP: Double
    var maxTokens: Int

    /// Additional sampling knobs. All default to "off" values so upgrading a
    /// store that predates these fields auto-migrates cleanly.
    var presencePenalty: Double
    var frequencyPenalty: Double
    var repetitionPenalty: Double
    var seed: Int?

    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message] = []

    init(id: UUID = UUID(),
         title: String = "New Chat",
         createdAt: Date = .now,
         updatedAt: Date? = nil,
         systemPrompt: String = "",
         modelId: String? = nil,
         temperature: Double = 0.7,
         topP: Double = 1.0,
         maxTokens: Int = 1024,
         presencePenalty: Double = 0.0,
         frequencyPenalty: Double = 0.0,
         repetitionPenalty: Double = 1.0,
         seed: Int? = nil) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt ?? createdAt
        self.systemPrompt = systemPrompt
        self.modelId = modelId
        self.temperature = temperature
        self.topP = topP
        self.maxTokens = maxTokens
        self.presencePenalty = presencePenalty
        self.frequencyPenalty = frequencyPenalty
        self.repetitionPenalty = repetitionPenalty
        self.seed = seed
    }

    /// Messages ordered chronologically. SwiftData doesn't guarantee insertion
    /// order on `@Relationship` arrays across fetches, so views sort here.
    var sortedMessages: [Message] {
        messages.sorted { $0.createdAt < $1.createdAt }
    }
}
