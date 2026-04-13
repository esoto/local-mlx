import SwiftUI
import SwiftData

@main
struct LocalMLXApp: App {

    @StateObject private var settings = AppSettings()

    /// One shared ModelsViewModel for the whole app so every window sees
    /// the same connection status and model list. Held as a `let` because
    /// the App struct is constructed exactly once by SwiftUI, so reference
    /// identity is naturally stable; the view model is an `@Observable`
    /// class, so its properties are still tracked in views that read them.
    @MainActor
    private static let sharedModelsVM: ModelsViewModel = ModelsViewModel(
        client: LiveMLXClient(baseURL: { AppSettings.makeBaseURL() })
    )

    private var modelsVM: ModelsViewModel { Self.sharedModelsVM }

    private let modelContainer: ModelContainer = {
        let schema = Schema([Conversation.self, Message.self])
        do {
            return try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema)]
            )
        } catch {
            NSLog("LocalMLX: SwiftData container failed: \(error). Using in-memory store.")
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            // swiftlint:disable:next force_try
            return try! ModelContainer(for: schema, configurations: [config])
        }
    }()

    /// A single shared client for the whole app. The closure reads
    /// UserDefaults on every call so URL edits in Settings take effect on
    /// the very next request.
    private let clientHolder = MLXClientEnvironmentKey.LiveHolder(
        LiveMLXClient(baseURL: { AppSettings.makeBaseURL() })
    )

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environment(\.mlxClient, clientHolder)
                .environment(modelsVM)
                .frame(minWidth: 800, minHeight: 500)
                .task {
                    // Kick off polling the first time the main window appears.
                    modelsVM.startPolling()
                }
        }
        .modelContainer(modelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {
                NewChatCommand()
            }
        }

        // Detail window — one per conversation, addressable by UUID.
        WindowGroup(id: "chat", for: UUID.self) { $conversationID in
            if let id = conversationID {
                SingleChatWindow(conversationID: id)
                    .environmentObject(settings)
                    .environment(\.mlxClient, clientHolder)
                    .environment(modelsVM)
                    .frame(minWidth: 720, minHeight: 500)
            } else {
                ContentUnavailableView(
                    "No Conversation",
                    systemImage: "xmark.octagon",
                    description: Text("This window was opened without a conversation id.")
                )
            }
        }
        .modelContainer(modelContainer)

        Settings {
            SettingsView()
                .environmentObject(settings)
                .environment(\.mlxClient, clientHolder)
        }
    }
}

/// Keyboard shortcut ⌘N — creates a new conversation via a notification that
/// `RootView` listens for.
private struct NewChatCommand: View {
    var body: some View {
        Button("New Chat") {
            NotificationCenter.default.post(name: .newChatRequested, object: nil)
        }
        .keyboardShortcut("n", modifiers: .command)
    }
}

extension Notification.Name {
    static let newChatRequested = Notification.Name("LocalMLX.newChatRequested")
    /// Posted with a `UUID` as the object when the UI should switch the
    /// main window to a different conversation (e.g. after forking).
    static let conversationActivated = Notification.Name("LocalMLX.conversationActivated")
}

// MARK: - MLXClient environment injection

/// A small environment key carrying a shared `MLXClient` into views.
/// Boxed in a class so an `any MLXClientProtocol` existential can live
/// inside an `EnvironmentKey.defaultValue` without copy-on-use hassle.
struct MLXClientEnvironmentKey: EnvironmentKey {
    /// `@unchecked Sendable` because the only stored property is an immutable
    /// `any MLXClientProtocol` existential, which is itself Sendable — but
    /// Swift can't currently prove that for class wrappers around
    /// existentials, so we assert it by hand.
    final class LiveHolder: @unchecked Sendable {
        let client: any MLXClientProtocol
        init(_ client: any MLXClientProtocol) { self.client = client }
    }

    static let defaultValue: LiveHolder = LiveHolder(
        LiveMLXClient(baseURL: { AppSettings.makeBaseURL() })
    )
}

extension EnvironmentValues {
    var mlxClient: MLXClientEnvironmentKey.LiveHolder {
        get { self[MLXClientEnvironmentKey.self] }
        set { self[MLXClientEnvironmentKey.self] = newValue }
    }
}
