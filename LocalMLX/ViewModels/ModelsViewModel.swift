import Foundation
import OSLog

/// Owns the list of models currently available on the server. Shared across
/// `ChatView` headers and the `SettingsView` Test Connection button. Also
/// exposes a coarse `ConnectionStatus` for the header dot.
@Observable
@MainActor
final class ModelsViewModel {

    enum State: Equatable {
        case idle
        case loading
        case loaded([String])
        case failed(String)
    }

    enum ConnectionStatus: Equatable {
        case unknown
        case online
        case offline(String)
    }

    var state: State = .idle
    var connectionStatus: ConnectionStatus = .unknown

    private let client: any MLXClientProtocol
    private let log = Logger(subsystem: "dev.localmlx", category: "models")

    init(client: any MLXClientProtocol) {
        self.client = client
    }

    /// Fetch `/v1/models` and update `state` + `connectionStatus`.
    func refresh() async {
        state = .loading
        do {
            let ids = try await client.listModels()
            state = .loaded(ids)
            connectionStatus = .online
        } catch let error as MLXClientError {
            log.error("listModels failed: \(error.localizedDescription, privacy: .public)")
            let message = error.errorDescription ?? "Unknown error"
            state = .failed(message)
            connectionStatus = .offline(message)
        } catch {
            state = .failed(error.localizedDescription)
            connectionStatus = .offline(error.localizedDescription)
        }
    }

    /// Convenience: models list if loaded, else empty.
    var models: [String] {
        if case .loaded(let list) = state { return list }
        return []
    }
}
