import Foundation

/// A `URLProtocol` that intercepts requests on an ephemeral `URLSession` and
/// serves canned responses — used to drive `MLXClient` deterministically in tests.
///
/// Usage:
/// ```swift
/// let config = URLSessionConfiguration.ephemeral
/// config.protocolClasses = [MockURLProtocol.self]
/// let session = URLSession(configuration: config)
///
/// MockURLProtocol.handler = { request in
///     let response = HTTPURLResponse(url: request.url!, statusCode: 200,
///                                    httpVersion: "HTTP/1.1", headerFields: nil)!
///     return .success((response, bodyData, chunks: nil))
/// }
/// ```
///
/// For streaming bodies, provide `chunks` — each chunk is delivered via
/// `client?.urlProtocol(_:didLoad:)` separately with an optional delay. This
/// simulates mlx-lm's incremental SSE output so cancellation tests are realistic.
final class MockURLProtocol: URLProtocol {

    struct StreamedResponse {
        let response: HTTPURLResponse
        /// If non-nil, delivered as a single `didLoad` call.
        let body: Data?
        /// If non-nil, delivered chunk-by-chunk with an optional sleep between
        /// each chunk. Takes precedence over `body` when both are set.
        let chunks: [Data]?
        /// Seconds to pause between successive chunks. Default 0.
        let chunkInterval: TimeInterval

        init(response: HTTPURLResponse,
             body: Data? = nil,
             chunks: [Data]? = nil,
             chunkInterval: TimeInterval = 0) {
            self.response = response
            self.body = body
            self.chunks = chunks
            self.chunkInterval = chunkInterval
        }
    }

    enum Outcome {
        case success(StreamedResponse)
        case failure(Error)
    }

    /// The handler is invoked for every request. Reset between tests.
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) -> Outcome)?

    /// Reset all handler state between tests.
    static func reset() {
        handler = nil
    }

    // MARK: - URLProtocol

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override class func requestIsCacheEquivalent(_ a: URLRequest, to b: URLRequest) -> Bool { false }

    override func startLoading() {
        guard let handler = MockURLProtocol.handler else {
            client?.urlProtocol(self, didFailWithError: NSError(
                domain: "MockURLProtocol", code: -1,
                userInfo: [NSLocalizedDescriptionKey: "No handler set"]))
            return
        }

        switch handler(request) {
        case .failure(let error):
            client?.urlProtocol(self, didFailWithError: error)

        case .success(let streamed):
            client?.urlProtocol(self, didReceive: streamed.response,
                                cacheStoragePolicy: .notAllowed)

            if let chunks = streamed.chunks {
                Task.detached { [weak self] in
                    guard let self else { return }
                    for chunk in chunks {
                        if Task.isCancelled { return }
                        self.client?.urlProtocol(self, didLoad: chunk)
                        if streamed.chunkInterval > 0 {
                            try? await Task.sleep(nanoseconds: UInt64(streamed.chunkInterval * 1_000_000_000))
                        }
                    }
                    self.client?.urlProtocolDidFinishLoading(self)
                }
            } else {
                if let body = streamed.body {
                    client?.urlProtocol(self, didLoad: body)
                }
                client?.urlProtocolDidFinishLoading(self)
            }
        }
    }

    override func stopLoading() {
        // URLSession cancellation lands here. We have nothing ongoing to release;
        // the detached Task above checks `Task.isCancelled` — but since we don't
        // hold a handle, in practice `stopLoading` just signals that the client
        // will ignore further callbacks.
    }
}

// MARK: - Convenience builders used by tests

extension MockURLProtocol {

    /// Build a JSON response helper.
    static func json(_ body: Data, status: Int = 200, url: URL) -> Outcome {
        let response = HTTPURLResponse(
            url: url,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        return .success(StreamedResponse(response: response, body: body))
    }

    /// Build a streaming SSE response helper. Each chunk should already include
    /// its `data: …\n\n` framing.
    static func sse(chunks: [String], interval: TimeInterval = 0, url: URL) -> Outcome {
        let response = HTTPURLResponse(
            url: url,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"]
        )!
        let datas = chunks.map { Data($0.utf8) }
        return .success(StreamedResponse(response: response,
                                         chunks: datas,
                                         chunkInterval: interval))
    }
}
