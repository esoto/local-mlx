import SwiftUI

struct SidebarView: View {
    let conversations: [Conversation]
    @Binding var selection: UUID?
    let onNewChat: () -> Void
    let onDelete: (Conversation) -> Void

    var body: some View {
        List(selection: $selection) {
            Section("Conversations") {
                ForEach(conversations, id: \.id) { convo in
                    ConversationRow(conversation: convo)
                        .tag(convo.id)
                        .contextMenu {
                            Button(role: .destructive) {
                                onDelete(convo)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }
        .listStyle(.sidebar)
        .frame(minWidth: 200)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: onNewChat) {
                    Label("New Chat", systemImage: "square.and.pencil")
                }
                .help("New Chat (⌘N)")
            }
        }
    }
}
