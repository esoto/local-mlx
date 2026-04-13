import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selection: UUID?
    let onNewChat: () -> Void
    let onDelete: (Conversation) -> Void
    var onOpenInNewWindow: ((Conversation) -> Void)?

    @State private var searchText: String = ""

    var body: some View {
        List(selection: $selection) {
            ForEach(groupedConversations, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.conversations, id: \.id) { convo in
                        ConversationRow(conversation: convo)
                            .tag(convo.id)
                            .contextMenu {
                                if let onOpenInNewWindow {
                                    Button {
                                        onOpenInNewWindow(convo)
                                    } label: {
                                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                                    }
                                    Divider()
                                }
                                Button(role: .destructive) {
                                    onDelete(convo)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 220)
        .searchable(text: $searchText,
                    placement: .sidebar,
                    prompt: "Search chats")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New Chat (⌘N)")
            }
        }
    }

    // MARK: - Filtering + grouping

    private var filtered: [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return conversations }
        return conversations.filter { convo in
            if convo.title.lowercased().contains(query) { return true }
            return convo.messages.contains { msg in
                msg.content.lowercased().contains(query)
            }
        }
    }

    private var groupedConversations: [SidebarDateGroup] {
        SidebarGrouping.group(filtered, now: .now)
    }
}
