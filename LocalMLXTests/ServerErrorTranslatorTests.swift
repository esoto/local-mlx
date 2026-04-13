import XCTest
@testable import LocalMLX

final class ServerErrorTranslatorTests: XCTestCase {

    // MARK: - isVisionTextMismatch

    func test_isVisionTextMismatch_exactMlxLmString() {
        XCTAssertTrue(ServerErrorTranslator.isVisionTextMismatch(
            "Only 'text' content type is supported."))
    }

    func test_isVisionTextMismatch_caseInsensitive() {
        XCTAssertTrue(ServerErrorTranslator.isVisionTextMismatch(
            "ONLY 'TEXT' CONTENT TYPE IS SUPPORTED"))
        XCTAssertTrue(ServerErrorTranslator.isVisionTextMismatch(
            "only 'text' content type"))
    }

    func test_isVisionTextMismatch_trailingPunctuationIgnored() {
        // mlx-lm might reword slightly across versions — we want loose
        // matching on the distinguishing words, not exact substring.
        XCTAssertTrue(ServerErrorTranslator.isVisionTextMismatch(
            "Error: only the 'text' content type is supported by this server."))
    }

    func test_isVisionTextMismatch_negative_similarErrors() {
        XCTAssertFalse(ServerErrorTranslator.isVisionTextMismatch(
            "Only JSON content type is supported."),
            "a content-type error about JSON shouldn't trigger the vision rewrite")
        XCTAssertFalse(ServerErrorTranslator.isVisionTextMismatch(
            "Text 'content' not found"),
            "unrelated 'text' and 'content' words should not match")
        XCTAssertFalse(ServerErrorTranslator.isVisionTextMismatch(""))
    }

    // MARK: - friendlyMessage

    func test_friendlyMessage_rewritesVisionMismatch() {
        let err = MLXClientError.http(
            status: 404,
            message: "Only 'text' content type is supported.")
        let msg = ServerErrorTranslator.friendlyMessage(for: err)

        XCTAssertTrue(msg.contains("doesn't support images"),
                      "rewritten message should explain the mismatch")
        XCTAssertTrue(msg.contains("Stop"),
                      "should tell the user what action to take")
        XCTAssertTrue(msg.contains("mlx_vlm.server") || msg.contains("vision"),
                      "should point at the vision-capable path")
        XCTAssertFalse(msg.contains("Only 'text' content type"),
                       "should not surface the raw server string once translated")
    }

    func test_friendlyMessage_passesThroughHTTPErrorsWithoutKnownPattern() {
        let err = MLXClientError.http(status: 500, message: "Internal server error")
        let msg = ServerErrorTranslator.friendlyMessage(for: err)
        XCTAssertEqual(msg, "Server error 500: Internal server error")
    }

    func test_friendlyMessage_passesThroughHTTPErrorsWithNoMessage() {
        let err = MLXClientError.http(status: 502, message: nil)
        let msg = ServerErrorTranslator.friendlyMessage(for: err)
        XCTAssertEqual(msg, "Server error 502")
    }

    func test_friendlyMessage_passesThroughUnreachable() {
        let err = MLXClientError.unreachable(underlying: "Connection refused")
        let msg = ServerErrorTranslator.friendlyMessage(for: err)
        XCTAssertEqual(msg, "Cannot reach MLX server. (Connection refused)")
    }

    func test_friendlyMessage_passesThroughDecoding() {
        let err = MLXClientError.decoding("malformed SSE frame")
        let msg = ServerErrorTranslator.friendlyMessage(for: err)
        XCTAssertEqual(msg, "Failed to parse server response: malformed SSE frame")
    }

    func test_friendlyMessage_passesThroughCanceled() {
        let msg = ServerErrorTranslator.friendlyMessage(for: .canceled)
        XCTAssertEqual(msg, "Generation canceled.")
    }
}
