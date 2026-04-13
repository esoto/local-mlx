import Foundation

/// One section in the sidebar: Today, Yesterday, Last 7 days, Last 30 days,
/// Older. Conversations are bucketed by their `updatedAt`.
struct SidebarDateGroup: Equatable {
    let title: String
    let conversations: [Conversation]
}

/// Pure bucketing logic for the sidebar. Takes a list of conversations and
/// returns them split into date groups in display order. Kept testable by
/// accepting the "now" clock as a parameter.
enum SidebarGrouping {

    static func group(_ conversations: [Conversation],
                      now: Date,
                      calendar: Calendar = .current) -> [SidebarDateGroup] {
        // Sort descending so the newest rows appear first in each section.
        let sorted = conversations.sorted { $0.updatedAt > $1.updatedAt }

        let startOfToday = calendar.startOfDay(for: now)
        let startOfYesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let startOfLast7 = calendar.date(byAdding: .day, value: -7, to: startOfToday) ?? startOfToday
        let startOfLast30 = calendar.date(byAdding: .day, value: -30, to: startOfToday) ?? startOfToday

        var today: [Conversation] = []
        var yesterday: [Conversation] = []
        var last7: [Conversation] = []
        var last30: [Conversation] = []
        var older: [Conversation] = []

        for convo in sorted {
            let t = convo.updatedAt
            if t >= startOfToday {
                today.append(convo)
            } else if t >= startOfYesterday {
                yesterday.append(convo)
            } else if t >= startOfLast7 {
                last7.append(convo)
            } else if t >= startOfLast30 {
                last30.append(convo)
            } else {
                older.append(convo)
            }
        }

        var groups: [SidebarDateGroup] = []
        if !today.isEmpty { groups.append(.init(title: "Today", conversations: today)) }
        if !yesterday.isEmpty { groups.append(.init(title: "Yesterday", conversations: yesterday)) }
        if !last7.isEmpty { groups.append(.init(title: "Last 7 days", conversations: last7)) }
        if !last30.isEmpty { groups.append(.init(title: "Last 30 days", conversations: last30)) }
        if !older.isEmpty { groups.append(.init(title: "Older", conversations: older)) }
        return groups
    }
}
