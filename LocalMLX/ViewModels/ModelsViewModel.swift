import Foundation
import OSLog

/// Owns the list of models currently available on the server. Shared across
/// `ChatView` headers and the `SettingsView` Test Connection button.
@Observable
@MainActor
final class ModelsViewModel {

    enum State: Equatable {
        case idle
        case loading
        case loaded([String])
        case failed(String)
    }

    var state: State = .idle

    private let client: any MLXClientProtocol
    private let log = Logger(subsystem: "dev.localmlx", category: "models")

    init(client: any MLXClientProtocol) {
        self.client = client
    }

    /// Fetch `/v1/models` and update `state`. Safe to call from any view.
    func refresh() async {
        state = .loading
        do {
            let ids = try await client.listModels()
            state = .loaded(ids)
        } catch let error as MLXClientError {
            log.error("listModels failed: \(error.localizedDescription, privacy: .public)")
            state = .failed(error.errorDescription ?? "Unknown error")
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    /// Convenience: models list if loaded, else empty.
    var models: [String] {
        if case .loaded(let list) = state { return list }
        return []
    }
}
