import SwiftUI
import SwiftData
import Combine

/// Top-level split view: sidebar of conversations + chat detail.
struct RootView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.mlxClient) private var clientHolder
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settings: AppSettings

    @Query(sort: [SortDescriptor(\Conversation.updatedAt, order: .reverse)])
    private var conversations: [Conversation]

    @State private var selectedID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                conversations: conversations,
                selection: $selectedID,
                onNewChat: createNewChat,
                onDelete: deleteConversation,
                onOpenInNewWindow: { openWindow(id: "chat", value: $0.id) }
            )
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let convo = selectedConversation {
                ChatView(conversation: convo)
                    .id(convo.id)   // recreate view model per conversation
            } else {
                ContentUnavailableView(
                    "No Conversation",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Create a new chat from the sidebar or press ⌘N.")
                )
            }
        }
        .onAppear {
            if selectedID == nil { selectedID = conversations.first?.id }
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            createNewChat()
        }
    }

    private var selectedConversation: Conversation? {
        guard let id = selectedID else { return nil }
        return conversations.first(where: { $0.id == id })
    }

    // MARK: - Actions

    private func createNewChat() {
        let convo = Conversation(
            systemPrompt: settings.defaultSystemPrompt,
            modelId: settings.defaultModelId.isEmpty ? nil : settings.defaultModelId,
            temperature: settings.defaultTemperature,
            topP: settings.defaultTopP,
            maxTokens: settings.defaultMaxTokens
        )
        modelContext.insert(convo)
        try? modelContext.save()
        selectedID = convo.id
    }

    private func deleteConversation(_ convo: Conversation) {
        if selectedID == convo.id { selectedID = nil }
        modelContext.delete(convo)
        try? modelContext.save()
    }
}
