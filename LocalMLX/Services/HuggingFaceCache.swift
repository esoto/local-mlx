import Foundation

/// Reads the local HuggingFace hub cache to determine whether a given
/// model has been downloaded and, if so, which revision (commit SHA)
/// is pinned as its "main" ref.
///
/// The hub cache layout is:
///
///     ~/.cache/huggingface/hub/
///       models--<org>--<name>/
///         blobs/           (content-addressed files)
///         refs/
///           main           (text file whose contents is a commit SHA)
///         snapshots/
///           <sha>/         (symlinks to blobs/)
///
/// So the cheapest existence check + revision read is a single file
/// read of `models--<org>--<name>/refs/main`.
///
/// **Sandbox note:** LocalMLX is sandboxed, and `~/.cache/huggingface/`
/// is outside the app's container. Reads from this path succeed only
/// when the app ships with
/// `com.apple.security.temporary-exception.files.home-relative-path.read-only`
/// entitled to `.cache/huggingface/hub/`. Without it,
/// `cachedRevision(for:)` silently returns nil for every repo — which
/// degrades UX but doesn't crash anything.
enum HuggingFaceCache {

    /// Root of the hub cache inside the current user's home directory.
    /// Tests pass their own temp dir via `cacheRoot:` to avoid touching
    /// the real cache.
    static var defaultCacheRoot: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("huggingface", isDirectory: true)
            .appendingPathComponent("hub", isDirectory: true)
    }

    /// Convert a HuggingFace repo id (`mlx-community/gemma-3-4b-it-4bit`)
    /// into the directory name huggingface-hub uses inside the cache
    /// (`models--mlx-community--gemma-3-4b-it-4bit`).
    static func cacheDirectoryName(for repoId: String) -> String {
        "models--" + repoId.replacingOccurrences(of: "/", with: "--")
    }

    /// The local revision of a cached model, or nil if nothing is
    /// cached for the given repo. Reads `refs/main` directly — no
    /// directory walks, single file stat + read.
    static func cachedRevision(for repoId: String, cacheRoot: URL? = nil) -> String? {
        let root = cacheRoot ?? Self.defaultCacheRoot
        let refsMain = root
            .appendingPathComponent(cacheDirectoryName(for: repoId), isDirectory: true)
            .appendingPathComponent("refs", isDirectory: true)
            .appendingPathComponent("main")

        guard let data = try? Data(contentsOf: refsMain),
              let raw = String(data: data, encoding: .utf8)
        else { return nil }

        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
