import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    let archivedConversations: [Conversation]
    @Binding var selection: UUID?
    @Binding var showArchived: Bool
    let onNewChat: () -> Void
    let onDelete: (Conversation) -> Void
    let onArchive: (Conversation) -> Void
    let onUnarchive: (Conversation) -> Void
    var onOpenInNewWindow: ((Conversation) -> Void)?

    @State private var searchText: String = ""

    var body: some View {
        List(selection: $selection) {
            ForEach(groupedConversations, id: \.title) { group in
                Section(group.title) {
                    ForEach(group.conversations, id: \.id) { convo in
                        row(for: convo, archived: false)
                    }
                }
            }

            if showArchived && !filteredArchived.isEmpty {
                Section("Archived") {
                    ForEach(filteredArchived, id: \.id) { convo in
                        row(for: convo, archived: true)
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
            ToolbarItem(placement: .secondaryAction) {
                Button {
                    showArchived.toggle()
                } label: {
                    Label(
                        showArchived ? "Hide Archived" : "Show Archived",
                        systemImage: showArchived ? "archivebox.fill" : "archivebox"
                    )
                }
                .help(showArchived ? "Hide archived chats" : "Show archived chats")
            }
        }
    }

    // MARK: - Row builder

    @ViewBuilder
    private func row(for convo: Conversation, archived: Bool) -> some View {
        ConversationRow(conversation: convo)
            .tag(convo.id)
            .opacity(archived ? 0.6 : 1.0)
            .contextMenu {
                if let onOpenInNewWindow {
                    Button {
                        onOpenInNewWindow(convo)
                    } label: {
                        Label("Open in New Window", systemImage: "macwindow.badge.plus")
                    }
                    Divider()
                }
                if archived {
                    Button {
                        onUnarchive(convo)
                    } label: {
                        Label("Unarchive", systemImage: "tray.and.arrow.up")
                    }
                } else {
                    Button {
                        onArchive(convo)
                    } label: {
                        Label("Archive", systemImage: "archivebox")
                    }
                }
                Divider()
                Button(role: .destructive) {
                    onDelete(convo)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }

    // MARK: - Filtering + grouping

    private var filtered: [Conversation] {
        applySearch(conversations)
    }

    private var filteredArchived: [Conversation] {
        applySearch(archivedConversations)
    }

    private func applySearch(_ input: [Conversation]) -> [Conversation] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if query.isEmpty { return input }
        return input.filter { convo in
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
