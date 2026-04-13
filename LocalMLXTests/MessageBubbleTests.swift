import XCTest
@testable import LocalMLX

/// `MessageBubble` itself is a SwiftUI view and only manually tested.
/// The bits worth unit-testing are the pure helpers that drive what
/// the view shows — currently just `waitingText`, which produces the
/// progressive hint text in the "waiting for first token" indicator.
final class MessageBubbleWaitingTextTests: XCTestCase {

    func test_waitingText_under3Seconds_generic() {
        XCTAssertEqual(MessageBubble.waitingText(elapsed: 0),
                       "Waiting for response…")
        XCTAssertEqual(MessageBubble.waitingText(elapsed: 2.9),
                       "Waiting for response…")
    }

    func test_waitingText_between3And15Seconds_showsElapsedSeconds() {
        let text = MessageBubble.waitingText(elapsed: 8)
        XCTAssertTrue(text.contains("first token"))
        XCTAssertTrue(text.contains("8s"))
    }

    func test_waitingText_between15And45Seconds_mentionsVisionModelLatency() {
        let text = MessageBubble.waitingText(elapsed: 25)
        XCTAssertTrue(text.contains("25s"))
        XCTAssertTrue(text.contains("Vision"),
                      "the 15-45s range should name vision model latency as a likely cause")
    }

    func test_waitingText_between45And120Seconds_suggestsStopAndLoadingHint() {
        let text = MessageBubble.waitingText(elapsed: 90)
        XCTAssertTrue(text.contains("90s"))
        XCTAssertTrue(text.contains("loading") || text.contains("prompt processing"),
                      "long-wait hint should point at model load or prompt processing")
        XCTAssertTrue(text.contains("Stop"),
                      "should remind the user they can cancel")
    }

    func test_waitingText_over120Seconds_namesPossibleHangAndTerminalCheck() {
        let text = MessageBubble.waitingText(elapsed: 180)
        XCTAssertTrue(text.contains("180s"))
        XCTAssertTrue(text.contains("stuck") || text.contains("still loading"),
                      "2-minute hint should call out a likely hang or giant model")
        XCTAssertTrue(text.contains("Terminal"),
                      "should direct the user to check the Terminal for errors")
    }

    func test_waitingText_secondsAreIntegerOnly() {
        // No "8.7s" precision — the hint is for humans, round to ints.
        let text = MessageBubble.waitingText(elapsed: 8.7)
        XCTAssertFalse(text.contains("8.7"))
        XCTAssertTrue(text.contains("8s"))
    }
}
