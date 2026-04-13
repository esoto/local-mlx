import Foundation

/// UI-facing download state for a single model repo. Driven by a
/// combination of what's in the local HuggingFace cache + what the
/// remote API reports. Used to decide whether the "Download Model"
/// and "Update Model" buttons in Settings should be enabled.
enum ModelDownloadStatus: Equatable, Sendable {
    /// No local cache entry for this repo.
    case notDownloaded
    /// Cached revision matches the latest main-branch SHA on HuggingFace.
    case upToDate(sha: String)
    /// Cached revision exists but is older than what the remote reports.
    case updateAvailable(local: String, remote: String)
    /// We couldn't determine status — network error, HF offline, weird
    /// response. Buttons fall back to "user decides", Download stays
    /// enabled so the user isn't stuck.
    case unknown(reason: String)

    /// Should the Download button be active for this status?
    var canDownload: Bool {
        switch self {
        case .notDownloaded, .unknown:
            return true
        case .upToDate, .updateAvailable:
            return false
        }
    }

    /// Should the Update button be active for this status?
    var canUpdate: Bool {
        if case .updateAvailable = self { return true }
        return false
    }
}

/// Decides a `ModelDownloadStatus` from the local cache + remote API.
/// Kept as a separate type (rather than a method on the enum) so tests
/// can inject a `URLSession` that routes through `MockURLProtocol` and
/// a custom cache root so the real ~/.cache is never touched.
enum ModelDownloadStatusResolver {

    /// Resolve the status for a given repo. Performs at most one
    /// network request; the cache read is synchronous.
    static func resolve(
        repoId: String,
        session: URLSession = .shared,
        cacheRoot: URL? = nil
    ) async -> ModelDownloadStatus {
        let localSHA = HuggingFaceCache.cachedRevision(
            for: repoId, cacheRoot: cacheRoot)

        do {
            let remoteSHA = try await HuggingFaceAPI.latestRevision(
                for: repoId, session: session)

            switch (localSHA, remoteSHA) {
            case (nil, _):
                return .notDownloaded
            case (let local?, nil):
                // Remote didn't report a sha (unusual for public repos
                // but possible) — assume we're current.
                return .upToDate(sha: local)
            case (let local?, let remote?):
                return local == remote
                    ? .upToDate(sha: local)
                    : .updateAvailable(local: local, remote: remote)
            }
        } catch {
            // Network or server error. Prefer a useful fallback over
            // "error everywhere":
            // - If we have a local copy, call it up-to-date so offline
            //   users can still hit Start Server without the UI
            //   screaming at them.
            // - Otherwise surface .unknown so Download stays enabled
            //   and the user can try anyway.
            if let local = localSHA {
                return .upToDate(sha: local)
            }
            return .unknown(reason: error.localizedDescription)
        }
    }
}
