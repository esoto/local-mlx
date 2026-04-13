import Foundation
import OSLog

/// Owns the list of models currently available on the server. Shared
/// app-wide via the environment so every chat window sees the same
/// connection status and model list without duplicating work.
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
    @ObservationIgnored
    nonisolated(unsafe) private var pollingTask: Task<Void, Never>?

    init(client: any MLXClientProtocol) {
        self.client = client
    }

    deinit {
        pollingTask?.cancel()
    }

    /// Fetch `/v1/models` and update `state` + `connectionStatus`.
    func refresh() async {
        // Keep a stale-but-valid view while reloading so the UI doesn't flash
        // "loading" on every poll tick.
        if case .idle = state { state = .loading }
        do {
            let ids = try await client.listModels()
            state = .loaded(ids)
            connectionStatus = .online
        } catch let error as MLXClientError {
            log.error("listModels failed: \(error.localizedDescription, privacy: .public)")
            let message = error.errorDescription ?? "Unknown error"
            // Don't blow away a previously loaded list on a transient failure
            // — keep the list visible but mark the status offline.
            if case .loaded = state {
                // leave state alone
            } else {
                state = .failed(message)
            }
            connectionStatus = .offline(message)
        } catch {
            state = .failed(error.localizedDescription)
            connectionStatus = .offline(error.localizedDescription)
        }
    }

    /// Start a background poll that calls `refresh()` every `interval`
    /// seconds until `stopPolling()` is called or the view model is
    /// deallocated. Idempotent — calling twice is a no-op.
    func startPolling(interval: TimeInterval = 15) {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            // Kick off the first fetch immediately so the status dot isn't
            // stuck at "unknown" for 15 seconds after launch.
            await self?.refresh()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                if Task.isCancelled { return }
                await self?.refresh()
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Convenience: models list if loaded, else empty.
    var models: [String] {
        if case .loaded(let list) = state { return list }
        return []
    }
}
