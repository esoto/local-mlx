import XCTest
import SwiftData
@testable import LocalMLX

@MainActor
final class ConversationModelTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Conversation.self, Message.self, MessageAttachment.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func test_insertConversationWithMessages_roundTrips() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "Hello", systemPrompt: "be terse")
        ctx.insert(convo)

        let m1 = Message(role: .user, content: "hi", conversation: convo)
        let m2 = Message(role: .assistant, content: "hey", conversation: convo)
        ctx.insert(m1)
        ctx.insert(m2)

        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Conversation>())
        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.title, "Hello")
        XCTAssertEqual(fetched.first?.systemPrompt, "be terse")
        XCTAssertEqual(fetched.first?.messages.count, 2)
    }

    func test_messagesOrderedByCreatedAt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "Order")
        ctx.insert(convo)

        let start = Date(timeIntervalSince1970: 1_000_000_000)
        let m1 = Message(role: .user, content: "first",
                         createdAt: start, conversation: convo)
        let m2 = Message(role: .assistant, content: "second",
                         createdAt: start.addingTimeInterval(1), conversation: convo)
        let m3 = Message(role: .user, content: "third",
                         createdAt: start.addingTimeInterval(2), conversation: convo)
        ctx.insert(m1); ctx.insert(m2); ctx.insert(m3)
        try ctx.save()

        // `Conversation.sortedMessages` is the convenience the views use.
        let ordered = convo.sortedMessages
        XCTAssertEqual(ordered.map(\.content), ["first", "second", "third"])
    }

    func test_deletingConversationCascadesMessages() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "Doomed")
        ctx.insert(convo)
        ctx.insert(Message(role: .user, content: "x", conversation: convo))
        ctx.insert(Message(role: .assistant, content: "y", conversation: convo))
        try ctx.save()

        ctx.delete(convo)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<Message>())
        XCTAssertEqual(remaining.count, 0)
    }

    func test_defaultsAreSaneForNewConversation() {
        let convo = Conversation(title: "New Chat")
        XCTAssertEqual(convo.title, "New Chat")
        XCTAssertEqual(convo.temperature, 0.7)
        XCTAssertEqual(convo.topP, 1.0)
        XCTAssertEqual(convo.maxTokens, 1024)
        XCTAssertEqual(convo.systemPrompt, "")
        XCTAssertNil(convo.modelId)
        XCTAssertTrue(convo.messages.isEmpty)
        XCTAssertFalse(convo.isArchived, "new conversations start active")
    }

    func test_archivedFilter_excludesArchivedFromActiveQuery() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let active = Conversation(title: "Active")
        let archived = Conversation(title: "Old", isArchived: true)
        ctx.insert(active)
        ctx.insert(archived)
        try ctx.save()

        // The active query used by RootView.
        let activeDescriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { !$0.isArchived })
        let activeResults = try ctx.fetch(activeDescriptor)
        XCTAssertEqual(activeResults.map(\.title), ["Active"])

        // The archived query used by RootView when "Show archived" is on.
        let archivedDescriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { $0.isArchived })
        let archivedResults = try ctx.fetch(archivedDescriptor)
        XCTAssertEqual(archivedResults.map(\.title), ["Old"])
    }

    func test_attachment_roundTripsThroughPersistence() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "With image")
        ctx.insert(convo)

        let msg = Message(role: .user, content: "what is in this?", conversation: convo)
        ctx.insert(msg)

        let bytes = Data([0x89, 0x50, 0x4E, 0x47])  // PNG magic
        let attachment = MessageAttachment(
            mimeType: "image/png",
            data: bytes,
            width: 32,
            height: 32,
            message: msg)
        ctx.insert(attachment)

        try ctx.save()

        let fetched = try ctx.fetch(FetchDescriptor<Message>()).first
        XCTAssertEqual(fetched?.attachments.count, 1)
        XCTAssertEqual(fetched?.attachments.first?.mimeType, "image/png")
        XCTAssertEqual(fetched?.attachments.first?.data, bytes)
        XCTAssertEqual(fetched?.attachments.first?.width, 32)
    }

    func test_attachment_cascadeDeletesWithMessage() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "Cascade")
        ctx.insert(convo)

        let msg = Message(role: .user, content: "hi", conversation: convo)
        ctx.insert(msg)

        let attachment = MessageAttachment(
            mimeType: "image/png",
            data: Data([0x01]),
            message: msg)
        ctx.insert(attachment)
        try ctx.save()

        ctx.delete(msg)
        try ctx.save()

        let remaining = try ctx.fetch(FetchDescriptor<MessageAttachment>())
        XCTAssertEqual(remaining.count, 0,
                       "deleting a message should cascade to its attachments")
    }

    func test_attachment_cascadeDeletesWhenConversationIsDeleted() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "Deep cascade")
        ctx.insert(convo)
        let msg = Message(role: .user, content: "hi", conversation: convo)
        ctx.insert(msg)
        ctx.insert(MessageAttachment(
            mimeType: "image/jpeg",
            data: Data([0x02]),
            message: msg))
        try ctx.save()

        ctx.delete(convo)
        try ctx.save()

        XCTAssertEqual(try ctx.fetch(FetchDescriptor<Message>()).count, 0)
        XCTAssertEqual(try ctx.fetch(FetchDescriptor<MessageAttachment>()).count, 0)
    }

    func test_toggleArchiveFlag_movesBetweenQueries() throws {
        let container = try makeContainer()
        let ctx = container.mainContext

        let convo = Conversation(title: "Toggle")
        ctx.insert(convo)
        try ctx.save()

        let activeDescriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { !$0.isArchived })
        XCTAssertEqual(try ctx.fetch(activeDescriptor).count, 1)

        convo.isArchived = true
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(activeDescriptor).count, 0,
                       "archiving should remove from the active query")

        convo.isArchived = false
        try ctx.save()
        XCTAssertEqual(try ctx.fetch(activeDescriptor).count, 1,
                       "unarchiving should restore it")
    }
}
