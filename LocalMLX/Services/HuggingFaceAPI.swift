import Foundation

/// Minimal client for the public HuggingFace model info endpoint.
///
/// We only need a single field — the current main-branch commit SHA —
/// so this is a GET against `https://huggingface.co/api/models/<repo>`
/// with no authentication. The `mlx-community/…` namespace is public,
/// so anonymous requests work. 5-second timeout so a slow or offline
/// HuggingFace doesn't hang the Settings UI.
enum HuggingFaceAPI {

    enum APIError: Error, Equatable {
        case http(status: Int)
        case invalidResponse
        case decodingFailed
    }

    /// Subset of `/api/models/{repo}` we care about.
    private struct ModelInfo: Decodable {
        let sha: String?
    }

    /// Fetch the latest main-branch commit SHA for a repo. Returns
    /// `nil` if the server returns a well-formed response without a
    /// `sha` field — not an error, just "we don't know". Throws on
    /// HTTP / network / decoding errors so the caller can distinguish
    /// "not found" (404) from "offline" (URLError.notConnectedToInternet).
    static func latestRevision(
        for repoId: String,
        session: URLSession = .shared
    ) async throws -> String? {
        // URL-encode each path segment to tolerate unusual repo ids.
        let encodedRepo = repoId
            .split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0) }
            .joined(separator: "/")
        guard let url = URL(string: "https://huggingface.co/api/models/\(encodedRepo)") else {
            throw APIError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode)
        }

        do {
            return try JSONDecoder().decode(ModelInfo.self, from: data).sha
        } catch {
            throw APIError.decodingFailed
        }
    }
}
