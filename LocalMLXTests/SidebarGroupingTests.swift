import XCTest
import SwiftData
@testable import LocalMLX

@MainActor
final class SidebarGroupingTests: XCTestCase {

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([Conversation.self, Message.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [config])
    }

    /// Fixed "now" so group boundaries are deterministic.
    private let now = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13 UTC

    /// A Gregorian calendar pinned to UTC so `startOfDay` doesn't drift by
    /// the machine's local time zone.
    private var utcCalendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }

    private func convo(title: String, daysAgo: Double) throws -> Conversation {
        let convo = Conversation(title: title)
        convo.updatedAt = now.addingTimeInterval(-daysAgo * 86_400)
        return convo
    }

    func test_group_bucketsIntoTodayYesterdayWeekMonthOlder() throws {
        let today = try convo(title: "today", daysAgo: 0.01)
        let yesterday = try convo(title: "yesterday", daysAgo: 1.1)
        let threeDaysAgo = try convo(title: "3-days", daysAgo: 3.0)
        let twoWeeksAgo = try convo(title: "2-weeks", daysAgo: 14.0)
        let twoMonthsAgo = try convo(title: "2-months", daysAgo: 60.0)

        let groups = SidebarGrouping.group(
            [today, yesterday, threeDaysAgo, twoWeeksAgo, twoMonthsAgo],
            now: now,
            calendar: utcCalendar
        )

        XCTAssertEqual(groups.map(\.title),
                       ["Today", "Yesterday", "Last 7 days", "Last 30 days", "Older"])
        XCTAssertEqual(groups[0].conversations.map(\.title), ["today"])
        XCTAssertEqual(groups[1].conversations.map(\.title), ["yesterday"])
        XCTAssertEqual(groups[2].conversations.map(\.title), ["3-days"])
        XCTAssertEqual(groups[3].conversations.map(\.title), ["2-weeks"])
        XCTAssertEqual(groups[4].conversations.map(\.title), ["2-months"])
    }

    func test_group_omitsEmptyBuckets() throws {
        let onlyOld = try convo(title: "ancient", daysAgo: 365)
        let groups = SidebarGrouping.group(
            [onlyOld], now: now,
            calendar: utcCalendar)
        XCTAssertEqual(groups.map(\.title), ["Older"])
    }

    func test_group_sortsWithinBucketsNewestFirst() throws {
        let a = try convo(title: "a", daysAgo: 0.5)
        let b = try convo(title: "b", daysAgo: 0.1)
        let c = try convo(title: "c", daysAgo: 0.3)

        let groups = SidebarGrouping.group(
            [a, b, c], now: now,
            calendar: utcCalendar)
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].conversations.map(\.title), ["b", "c", "a"])
    }

    func test_group_emptyInputReturnsEmpty() {
        XCTAssertTrue(SidebarGrouping.group([], now: now).isEmpty)
    }
}
