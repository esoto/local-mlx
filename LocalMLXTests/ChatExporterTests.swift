import XCTest
import SwiftData
@testable import LocalMLX

@MainActor
final class ChatExporterTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Conversation.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    func test_markdown_includesTitleAndModel() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "My chat", modelId: "llama3")
        ctx.insert(convo)

        let md = ChatExporter.markdown(
            from: convo,
            now: Date(timeIntervalSince1970: 1_735_689_600))

        XCTAssertTrue(md.hasPrefix("# My chat"))
        XCTAssertTrue(md.contains("**Model:** `llama3`"))
        XCTAssertTrue(md.contains("**Exported:**"))
    }

    func test_markdown_rendersSystemPromptAsBlockquote() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "t", systemPrompt: "Be terse\nand polite")
        ctx.insert(convo)

        let md = ChatExporter.markdown(from: convo)
        XCTAssertTrue(md.contains("> **System prompt:**"))
        XCTAssertTrue(md.contains("> Be terse"))
        XCTAssertTrue(md.contains("> and polite"))
    }

    func test_markdown_omitsSystemPromptBlockWhenEmpty() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "t", systemPrompt: "   ")
        ctx.insert(convo)

        let md = ChatExporter.markdown(from: convo)
        XCTAssertFalse(md.contains("System prompt"))
    }

    func test_markdown_rendersUserAndAssistantHeadingsAndBodies() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "t")
        ctx.insert(convo)
        let base = Date(timeIntervalSince1970: 1_000)
        ctx.insert(Message(role: .user, content: "Hi",
                           createdAt: base, conversation: convo))
        ctx.insert(Message(role: .assistant, content: "Hello",
                           createdAt: base.addingTimeInterval(1),
                           conversation: convo))
        try ctx.save()

        let md = ChatExporter.markdown(from: convo)
        XCTAssertTrue(md.contains("### You"))
        XCTAssertTrue(md.contains("Hi"))
        XCTAssertTrue(md.contains("### Assistant"))
        XCTAssertTrue(md.contains("Hello"))
    }

    func test_markdown_ordersMessagesByCreatedAt() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "t")
        ctx.insert(convo)
        let base = Date(timeIntervalSince1970: 1_000)
        ctx.insert(Message(role: .user, content: "first",
                           createdAt: base, conversation: convo))
        ctx.insert(Message(role: .assistant, content: "second",
                           createdAt: base.addingTimeInterval(1),
                           conversation: convo))
        ctx.insert(Message(role: .user, content: "third",
                           createdAt: base.addingTimeInterval(2),
                           conversation: convo))

        let md = ChatExporter.markdown(from: convo)
        let firstIdx = md.range(of: "first")!.lowerBound
        let secondIdx = md.range(of: "second")!.lowerBound
        let thirdIdx = md.range(of: "third")!.lowerBound
        XCTAssertLessThan(firstIdx, secondIdx)
        XCTAssertLessThan(secondIdx, thirdIdx)
    }

    func test_markdown_includesTokenMetadataWhenPresent() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "t")
        ctx.insert(convo)
        let base = Date(timeIntervalSince1970: 1_000)
        ctx.insert(Message(role: .user, content: "hi",
                           createdAt: base, conversation: convo))
        ctx.insert(Message(role: .assistant,
                           content: "hello",
                           createdAt: base.addingTimeInterval(1),
                           conversation: convo,
                           tokensPerSecond: 42.5,
                           completionTokens: 10))

        let md = ChatExporter.markdown(from: convo)
        XCTAssertTrue(md.contains("42.5 tok/s"))
        XCTAssertTrue(md.contains("10 tokens"))
    }

    func test_markdown_notesInterruption() throws {
        let container = try makeContainer()
        let ctx = container.mainContext
        let convo = Conversation(title: "t")
        ctx.insert(convo)
        let base = Date(timeIntervalSince1970: 1_000)
        ctx.insert(Message(role: .user, content: "hi",
                           createdAt: base, conversation: convo))
        ctx.insert(Message(role: .assistant,
                           content: "partial",
                           createdAt: base.addingTimeInterval(1),
                           conversation: convo,
                           interruptionReason: "connection lost"))

        let md = ChatExporter.markdown(from: convo)
        XCTAssertTrue(md.contains("connection lost"))
    }

    func test_suggestedFilename_sanitizesSpecialCharacters() {
        let convo = Conversation(title: "my /\\: chat?")
        XCTAssertEqual(ChatExporter.suggestedFilename(for: convo), "my ---- chat-.md")
    }

    func test_suggestedFilename_fallsBackToChatForEmptyTitle() {
        let convo = Conversation(title: "")
        XCTAssertEqual(ChatExporter.suggestedFilename(for: convo), "chat.md")
    }
}
