import SwiftUI
import SwiftData
import Combine

/// Top-level split view: sidebar of conversations + chat detail.
struct RootView: View {

    @Environment(\.modelContext) private var modelContext
    @Environment(\.mlxClient) private var clientHolder
    @Environment(\.openWindow) private var openWindow
    @EnvironmentObject private var settings: AppSettings

    // Active conversations only. Archived rows are filtered out at the
    // SwiftData layer so they aren't hydrated into memory unless the
    // user explicitly asks for them.
    @Query(
        filter: #Predicate<Conversation> { !$0.isArchived },
        sort: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
    )
    private var activeConversations: [Conversation]

    @Query(
        filter: #Predicate<Conversation> { $0.isArchived },
        sort: [SortDescriptor(\Conversation.updatedAt, order: .reverse)]
    )
    private var archivedConversations: [Conversation]

    @State private var selectedID: UUID?

    var body: some View {
        NavigationSplitView {
            SidebarView(
                conversations: activeConversations,
                archivedConversations: archivedConversations,
                selection: $selectedID,
                showArchived: $settings.showArchived,
                onNewChat: createNewChat,
                onDelete: deleteConversation,
                onArchive: archiveConversation,
                onUnarchive: unarchiveConversation,
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
            restoreSelectionOnLaunch()
        }
        .onChange(of: selectedID) { _, newID in
            settings.lastSelectedConversationID = newID?.uuidString ?? ""
        }
        .onReceive(NotificationCenter.default.publisher(for: .newChatRequested)) { _ in
            createNewChat()
        }
        .onReceive(NotificationCenter.default.publisher(for: .conversationActivated)) { note in
            if let id = note.object as? UUID { selectedID = id }
        }
    }

    private var allConversations: [Conversation] {
        activeConversations + archivedConversations
    }

    private var selectedConversation: Conversation? {
        guard let id = selectedID else { return nil }
        return allConversations.first(where: { $0.id == id })
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

    private func archiveConversation(_ convo: Conversation) {
        convo.isArchived = true
        convo.updatedAt = .now
        if selectedID == convo.id { selectedID = nil }
        try? modelContext.save()
    }

    private func unarchiveConversation(_ convo: Conversation) {
        convo.isArchived = false
        convo.updatedAt = .now
        try? modelContext.save()
        selectedID = convo.id
    }

    /// On first appearance, pick a starting selection: the UUID we
    /// persisted at last shutdown if it still exists, otherwise the
    /// newest active conversation.
    private func restoreSelectionOnLaunch() {
        guard selectedID == nil else { return }
        let stored = settings.lastSelectedConversationID
        if !stored.isEmpty,
           let uuid = UUID(uuidString: stored),
           allConversations.contains(where: { $0.id == uuid }) {
            selectedID = uuid
        } else {
            selectedID = activeConversations.first?.id
        }
    }
}
