import XCTest
@testable import LocalMLX

final class SSEParsingTests: XCTestCase {

    // MARK: - Line-level parsing

    func test_parseLine_returnsNilForBlankLine() {
        XCTAssertNil(SSEParser.parse(line: ""))
        XCTAssertNil(SSEParser.parse(line: "   "))
    }

    func test_parseLine_returnsNilForCommentLine() {
        XCTAssertNil(SSEParser.parse(line: ": this is a heartbeat"))
    }

    func test_parseLine_returnsNilForNonDataField() {
        // id:, event:, retry: — none of which mlx-lm uses, but be liberal.
        XCTAssertNil(SSEParser.parse(line: "event: ping"))
        XCTAssertNil(SSEParser.parse(line: "id: 42"))
    }

    func test_parseLine_returnsDataPayload() {
        XCTAssertEqual(
            SSEParser.parse(line: "data: {\"choices\":[]}"),
            .data("{\"choices\":[]}")
        )
    }

    func test_parseLine_stripsSingleLeadingSpaceAfterColon() {
        // Per SSE spec, "data: foo" == "foo" with exactly one leading space stripped.
        XCTAssertEqual(
            SSEParser.parse(line: "data: hello"),
            .data("hello")
        )
        XCTAssertEqual(
            SSEParser.parse(line: "data:hello"),
            .data("hello")
        )
        // Two spaces: second space is preserved.
        XCTAssertEqual(
            SSEParser.parse(line: "data:  hello"),
            .data(" hello")
        )
    }

    func test_parseLine_recognizesDoneSentinel() {
        XCTAssertEqual(SSEParser.parse(line: "data: [DONE]"), .done)
        XCTAssertEqual(SSEParser.parse(line: "data:[DONE]"), .done)
    }

    func test_parseLine_stripsTrailingCarriageReturn() {
        // URLSession.AsyncBytes.lines strips \n but leaves \r on CRLF streams.
        XCTAssertEqual(SSEParser.parse(line: "data: [DONE]\r"), .done)
        XCTAssertEqual(
            SSEParser.parse(line: "data: {\"ok\":true}\r"),
            .data("{\"ok\":true}")
        )
    }

    // MARK: - Delta extraction from a full fixture

    func test_extractContentDeltas_fromFixture_yieldsFiveDeltas() throws {
        let body = try TestBundle.loadFixtureString("chat_completion_stream", ext: "txt")
        let lines = body.split(whereSeparator: \.isNewline).map(String.init)

        var deltas: [String] = []
        var sawDone = false

        for line in lines {
            guard let event = SSEParser.parse(line: line) else { continue }
            switch event {
            case .done:
                sawDone = true
            case .data(let payload):
                let chunk = try? JSONDecoder().decode(
                    ChatChunk.self, from: Data(payload.utf8))
                if let content = chunk?.choices.first?.delta.content {
                    deltas.append(content)
                }
            }
        }

        XCTAssertTrue(sawDone)
        XCTAssertEqual(deltas, ["Hello", ", ", "world", "!"])
    }

    func test_malformedJSONFrame_isSkipped_surroundingFramesStillYield() {
        let lines = [
            "data: {\"choices\":[{\"delta\":{\"content\":\"a\"}}]}",
            "data: this is not json",
            "data: {\"choices\":[{\"delta\":{\"content\":\"b\"}}]}",
            "data: [DONE]",
        ]

        var deltas: [String] = []
        for line in lines {
            guard let event = SSEParser.parse(line: line) else { continue }
            if case .data(let payload) = event,
               let chunk = try? JSONDecoder().decode(
                    ChatChunk.self, from: Data(payload.utf8)),
               let content = chunk.choices.first?.delta.content {
                deltas.append(content)
            }
        }
        XCTAssertEqual(deltas, ["a", "b"])
    }
}
