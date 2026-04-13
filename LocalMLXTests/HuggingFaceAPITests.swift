import XCTest
@testable import LocalMLX

final class HuggingFaceAPITests: XCTestCase {

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Happy path

    func test_latestRevision_returnsShaFromResponse() async throws {
        let body = #"{"sha": "abc123", "downloads": 42}"#
        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data(body.utf8), url: request.url!)
        }

        let sha = try await HuggingFaceAPI.latestRevision(
            for: "mlx-community/gemma-3-4b-it-4bit",
            session: makeSession())
        XCTAssertEqual(sha, "abc123")
    }

    func test_latestRevision_returnsNil_whenResponseOmitsSha() async throws {
        let body = #"{"downloads": 42}"#
        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data(body.utf8), url: request.url!)
        }

        let sha = try await HuggingFaceAPI.latestRevision(
            for: "mlx-community/foo", session: makeSession())
        XCTAssertNil(sha,
                     "missing sha is a soft nil, not a decoding error")
    }

    // MARK: - URL construction

    func test_latestRevision_hitsExpectedURL() async throws {
        var seenURL: URL?
        MockURLProtocol.handler = { request in
            seenURL = request.url
            return MockURLProtocol.json(Data(#"{"sha": "x"}"#.utf8),
                                        url: request.url!)
        }
        _ = try await HuggingFaceAPI.latestRevision(
            for: "mlx-community/gemma-3-4b-it-4bit",
            session: makeSession())

        XCTAssertEqual(
            seenURL?.absoluteString,
            "https://huggingface.co/api/models/mlx-community/gemma-3-4b-it-4bit",
            "must hit the HF model info endpoint with the repo id in the path")
    }

    func test_latestRevision_sendsAcceptHeader() async throws {
        var acceptHeader: String?
        MockURLProtocol.handler = { request in
            acceptHeader = request.value(forHTTPHeaderField: "Accept")
            return MockURLProtocol.json(Data(#"{"sha": "x"}"#.utf8),
                                        url: request.url!)
        }
        _ = try await HuggingFaceAPI.latestRevision(
            for: "mlx-community/foo", session: makeSession())
        XCTAssertEqual(acceptHeader, "application/json")
    }

    // MARK: - Error mapping

    func test_latestRevision_throwsHTTP_on404() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            return .success(MockURLProtocol.StreamedResponse(
                response: response, body: Data()))
        }

        do {
            _ = try await HuggingFaceAPI.latestRevision(
                for: "mlx-community/does-not-exist", session: makeSession())
            XCTFail("expected http(404)")
        } catch HuggingFaceAPI.APIError.http(let status) {
            XCTAssertEqual(status, 404)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func test_latestRevision_throwsDecodingFailed_onMalformedJSON() async {
        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data("not json".utf8), url: request.url!)
        }
        do {
            _ = try await HuggingFaceAPI.latestRevision(
                for: "mlx-community/foo", session: makeSession())
            XCTFail("expected decodingFailed")
        } catch HuggingFaceAPI.APIError.decodingFailed {
            // expected
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }
}
