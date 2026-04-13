import XCTest
@testable import LocalMLX

final class HuggingFaceCacheTests: XCTestCase {

    // MARK: - Temp cache helpers

    /// Create a temporary directory shaped like the HuggingFace hub cache
    /// with optional `refs/main` files for each model to pre-populate.
    /// Returns the root directory URL; caller is responsible for cleanup.
    private func makeFakeCache(models: [String: String]) throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory
            .appendingPathComponent("HuggingFaceCacheTests-\(UUID().uuidString)")
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

    // MARK: - cacheDirectoryName

    func test_cacheDirectoryName_replacesSlashWithDoubleDash() {
        XCTAssertEqual(
            HuggingFaceCache.cacheDirectoryName(for: "mlx-community/gemma-3-4b-it-4bit"),
            "models--mlx-community--gemma-3-4b-it-4bit")
    }

    func test_cacheDirectoryName_singleSegment_stillPrefixed() {
        // Malformed repo ids shouldn't crash — just pass through.
        XCTAssertEqual(
            HuggingFaceCache.cacheDirectoryName(for: "just-a-name"),
            "models--just-a-name")
    }

    // MARK: - cachedRevision

    func test_cachedRevision_returnsSHA_whenRefsMainExists() throws {
        let cache = try makeFakeCache(models: [
            "mlx-community/gemma-3-4b-it-4bit": "abc123def456"
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        let sha = HuggingFaceCache.cachedRevision(
            for: "mlx-community/gemma-3-4b-it-4bit", cacheRoot: cache)
        XCTAssertEqual(sha, "abc123def456")
    }

    func test_cachedRevision_trimsTrailingWhitespace() throws {
        let cache = try makeFakeCache(models: [
            "mlx-community/foo": "0123456789abcdef\n"
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        XCTAssertEqual(
            HuggingFaceCache.cachedRevision(for: "mlx-community/foo", cacheRoot: cache),
            "0123456789abcdef",
            "trailing newline from hf-cli writes should be stripped")
    }

    func test_cachedRevision_returnsNil_whenModelNotCached() throws {
        let cache = try makeFakeCache(models: [:])
        defer { try? FileManager.default.removeItem(at: cache) }

        XCTAssertNil(HuggingFaceCache.cachedRevision(
            for: "mlx-community/missing", cacheRoot: cache))
    }

    func test_cachedRevision_returnsNil_whenRefsMainIsEmpty() throws {
        let cache = try makeFakeCache(models: [
            "mlx-community/empty": ""
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        // An empty-string ref is as good as no ref — avoid handing the
        // UI "" as a "valid" revision.
        XCTAssertNil(HuggingFaceCache.cachedRevision(
            for: "mlx-community/empty", cacheRoot: cache))
    }

    func test_cachedRevision_multipleModelsIsolated() throws {
        let cache = try makeFakeCache(models: [
            "mlx-community/a": "sha-a",
            "mlx-community/b": "sha-b",
        ])
        defer { try? FileManager.default.removeItem(at: cache) }

        XCTAssertEqual(
            HuggingFaceCache.cachedRevision(for: "mlx-community/a", cacheRoot: cache),
            "sha-a")
        XCTAssertEqual(
            HuggingFaceCache.cachedRevision(for: "mlx-community/b", cacheRoot: cache),
            "sha-b")
    }
}
