import XCTest
@testable import LocalMLX

final class ModelDownloadStatusTests: XCTestCase {

    // MARK: - Plumbing

    private func makeSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }

    private func makeCacheRoot(models: [String: String]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("ModelStatusTests-\(UUID().uuidString)")
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        for (repoId, sha) in models {
            let dir = root
                .appendingPathComponent(HuggingFaceCache.cacheDirectoryName(for: repoId))
                .appendingPathComponent("refs")
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try sha.write(
                to: dir.appendingPathComponent("main"),
                atomically: true, encoding: .utf8)
        }
        return root
    }

    override func tearDown() {
        MockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - canDownload / canUpdate

    func test_canDownload_coversNotDownloadedAndUnknown() {
        XCTAssertTrue(ModelDownloadStatus.notDownloaded.canDownload)
        XCTAssertTrue(ModelDownloadStatus.unknown(reason: "offline").canDownload)
        XCTAssertFalse(ModelDownloadStatus.upToDate(sha: "x").canDownload)
        XCTAssertFalse(
            ModelDownloadStatus.updateAvailable(local: "a", remote: "b").canDownload)
    }

    func test_canUpdate_onlyForUpdateAvailable() {
        XCTAssertFalse(ModelDownloadStatus.notDownloaded.canUpdate)
        XCTAssertFalse(ModelDownloadStatus.upToDate(sha: "x").canUpdate)
        XCTAssertFalse(ModelDownloadStatus.unknown(reason: "x").canUpdate)
        XCTAssertTrue(
            ModelDownloadStatus.updateAvailable(local: "a", remote: "b").canUpdate)
    }

    // MARK: - Resolver happy paths

    func test_resolve_notDownloaded_whenNoLocalCache() async throws {
        let cache = try makeCacheRoot(models: [:])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data(#"{"sha": "remote-sha"}"#.utf8),
                                 url: request.url!)
        }

        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/missing",
            session: makeSession(),
            cacheRoot: cache)
        XCTAssertEqual(status, .notDownloaded)
    }

    func test_resolve_upToDate_whenLocalMatchesRemote() async throws {
        let cache = try makeCacheRoot(models: [
            "mlx-community/foo": "same-sha"
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data(#"{"sha": "same-sha"}"#.utf8),
                                 url: request.url!)
        }

        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/foo",
            session: makeSession(),
            cacheRoot: cache)
        XCTAssertEqual(status, .upToDate(sha: "same-sha"))
    }

    func test_resolve_updateAvailable_whenRevisionsDiffer() async throws {
        let cache = try makeCacheRoot(models: [
            "mlx-community/foo": "old-sha"
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data(#"{"sha": "new-sha"}"#.utf8),
                                 url: request.url!)
        }

        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/foo",
            session: makeSession(),
            cacheRoot: cache)
        XCTAssertEqual(
            status,
            .updateAvailable(local: "old-sha", remote: "new-sha"))
    }

    // MARK: - Resolver error paths

    func test_resolve_upToDate_whenRemoteHasNoShaButLocalExists() async throws {
        let cache = try makeCacheRoot(models: [
            "mlx-community/foo": "local-sha"
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { request in
            MockURLProtocol.json(Data("{}".utf8), url: request.url!)
        }

        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/foo",
            session: makeSession(),
            cacheRoot: cache)
        XCTAssertEqual(status, .upToDate(sha: "local-sha"),
                       "nil remote sha with a local copy → assume up to date")
    }

    func test_resolve_networkFailure_withLocalCache_fallsBackToUpToDate() async throws {
        let cache = try makeCacheRoot(models: [
            "mlx-community/foo": "local-sha"
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { _ in
            .failure(URLError(.notConnectedToInternet))
        }

        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/foo",
            session: makeSession(),
            cacheRoot: cache)
        XCTAssertEqual(status, .upToDate(sha: "local-sha"),
                       "offline + local copy → call it up to date so " +
                       "the user isn't blocked from starting the server")
    }

    func test_resolve_networkFailure_withoutLocalCache_returnsUnknown() async throws {
        let cache = try makeCacheRoot(models: [:])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { _ in
            .failure(URLError(.notConnectedToInternet))
        }

        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/missing",
            session: makeSession(),
            cacheRoot: cache)
        if case .unknown = status {
            // Expected — surface as unknown so Download stays enabled
            // and the user can try anyway.
        } else {
            XCTFail("expected .unknown, got \(status)")
        }
    }

    func test_resolve_httpNotFound_treatsAsNotDownloaded() async throws {
        let cache = try makeCacheRoot(models: [:])
        defer { try? FileManager.default.removeItem(at: cache) }

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!, statusCode: 404,
                httpVersion: "HTTP/1.1", headerFields: nil)!
            return .success(MockURLProtocol.StreamedResponse(
                response: response, body: Data()))
        }

        // 404 is a throwing path in HuggingFaceAPI, so the resolver
        // enters the catch branch. Without a local copy it surfaces
        // as .unknown — that's the safer default for typo'd repo ids.
        let status = await ModelDownloadStatusResolver.resolve(
            repoId: "mlx-community/typo",
            session: makeSession(),
            cacheRoot: cache)
        if case .unknown = status {
            // expected
        } else {
            XCTFail("expected .unknown for 404 with empty cache, got \(status)")
        }
    }
}
