import SwiftUI
import SwiftData

/// Wrapper scene content that resolves a `Conversation` by its UUID from
/// the shared `ModelContainer` and renders a `ChatView`. Used as the
/// content of the "chat" `WindowGroup` so a conversation can be opened in
/// its own window via `openWindow(id: "chat", value: conversation.id)`.
struct SingleChatWindow: View {
    let conversationID: UUID

    @Environment(\.modelContext) private var modelContext
    @State private var conversation: Conversation?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let conversation {
                ChatView(conversation: conversation)
                    .navigationTitle(conversation.title)
            } else if loadFailed {
                ContentUnavailableView(
                    "Conversation not found",
                    systemImage: "xmark.octagon",
                    description: Text("The conversation may have been deleted.")
                )
            } else {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .task {
            let id = conversationID
            let descriptor = FetchDescriptor<Conversation>(
                predicate: #Predicate { $0.id == id }
            )
            if let found = try? modelContext.fetch(descriptor).first {
                conversation = found
            } else {
                loadFailed = true
            }
        }
    }
}
