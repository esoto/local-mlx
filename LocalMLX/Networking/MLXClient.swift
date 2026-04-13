import Foundation
import OSLog

/// Abstraction used by `ChatViewModel` so tests can inject a fake stream.
protocol MLXClientProtocol: Sendable {
    /// Returns the list of model ids from `GET /v1/models`.
    func listModels() async throws -> [String]

    /// Streams content deltas for a chat completion. The returned stream
    /// terminates normally on `[DONE]`, throws `MLXClientError.canceled` on
    /// consumer cancellation, and throws `MLXClientError.http/.unreachable`
    /// on server / network errors.
    func streamChat(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, Error>
}

/// Production implementation that hits a live `mlx_lm.server` over HTTP.
///
/// The base URL is provided as a closure so runtime edits in the Settings panel
/// take effect on the very next request — the client itself is stateless.
final class LiveMLXClient: MLXClientProtocol {
    private let session: URLSession
    private let baseURL: @Sendable () -> URL
    private let log = Logger(subsystem: "dev.localmlx", category: "sse")

    init(session: URLSession = .shared,
         baseURL: @escaping @Sendable () -> URL) {
        self.session = session
        self.baseURL = baseURL
    }

    // MARK: - listModels

    func listModels() async throws -> [String] {
        let url = baseURL().appendingPathComponent("v1/models")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let err as URLError {
            throw Self.mapURLError(err)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MLXClientError.decoding("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MLXClientError.http(
                status: http.statusCode,
                message: Self.decodeServerErrorMessage(data))
        }

        do {
            let list = try JSONDecoder().decode(ModelList.self, from: data)
            return list.data.map(\.id)
        } catch {
            throw MLXClientError.decoding(error.localizedDescription)
        }
    }

    // MARK: - streamChat

    func streamChat(_ request: ChatRequest) async throws -> AsyncThrowingStream<String, Error> {
        let url = baseURL().appendingPathComponent("v1/chat/completions")
        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        urlRequest.httpBody = try JSONEncoder().encode(request)

        let (bytes, response): (URLSession.AsyncBytes, URLResponse)
        do {
            (bytes, response) = try await session.bytes(for: urlRequest)
        } catch let err as URLError {
            throw Self.mapURLError(err)
        }

        guard let http = response as? HTTPURLResponse else {
            throw MLXClientError.decoding("Non-HTTP response")
        }
        guard (200..<300).contains(http.statusCode) else {
            // Drain the body (up to a sane limit) so we can decode an error message.
            var collected = Data()
            do {
                for try await byte in bytes {
                    collected.append(byte)
                    if collected.count > 8 * 1024 { break }
                }
            } catch {
                // ignore — we still have a best-effort prefix
            }
            throw MLXClientError.http(
                status: http.statusCode,
                message: Self.decodeServerErrorMessage(collected))
        }

        let logger = log
        return AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard let event = SSEParser.parse(line: line) else { continue }
                        switch event {
                        case .done:
                            continuation.finish()
                            return
                        case .data(let payload):
                            guard let data = payload.data(using: .utf8) else { continue }
                            do {
                                let chunk = try JSONDecoder().decode(ChatChunk.self, from: data)
                                if let content = chunk.choices.first?.delta.content,
                                   !content.isEmpty {
                                    continuation.yield(content)
                                }
                            } catch {
                                logger.warning("dropping malformed SSE frame: \(error.localizedDescription, privacy: .public)")
                                continue
                            }
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: MLXClientError.canceled)
                } catch let err as URLError where err.code == .cancelled {
                    continuation.finish(throwing: MLXClientError.canceled)
                } catch let err as URLError {
                    continuation.finish(throwing: LiveMLXClient.mapURLError(err))
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Error mapping

    private static func mapURLError(_ err: URLError) -> MLXClientError {
        switch err.code {
        case .cannotConnectToHost, .cannotFindHost,
             .timedOut, .networkConnectionLost,
             .notConnectedToInternet, .dnsLookupFailed:
            return .unreachable(underlying: err.localizedDescription)
        case .cancelled:
            return .canceled
        default:
            return .unreachable(underlying: err.localizedDescription)
        }
    }

    private static func decodeServerErrorMessage(_ data: Data) -> String? {
        guard !data.isEmpty else { return nil }
        if let body = try? JSONDecoder().decode(ServerErrorBody.self, from: data) {
            return body.error.message
        }
        // Fall back to a truncated UTF-8 dump for servers that return non-JSON.
        if let s = String(data: data, encoding: .utf8), !s.isEmpty {
            return String(s.prefix(200))
        }
        return nil
    }
}
