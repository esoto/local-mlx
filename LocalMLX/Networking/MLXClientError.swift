import Foundation

/// Errors produced by `MLXClient`. The switchable cases are shaped so the
/// ChatView error banner can present a useful message per category without
/// string-matching on `localizedDescription`.
enum MLXClientError: Error, LocalizedError, Equatable, Sendable {
    /// The server host was not reachable — connection refused, timed out, or
    /// the network dropped. The banner prompts the user to start/check their
    /// `mlx_lm.server`.
    case unreachable(underlying: String)

    /// The server returned a non-2xx status. `message` is the decoded
    /// `error.message` from an OpenAI-style error body if we could parse one.
    case http(status: Int, message: String?)

    /// The response wasn't parseable as the expected DTO.
    case decoding(String)

    /// The stream ended because the consumer cancelled its `Task`.
    case canceled

    var errorDescription: String? {
        switch self {
        case .unreachable(let underlying):
            return "Cannot reach MLX server. (\(underlying))"
        case .http(let status, let message):
            if let message {
                return "Server error \(status): \(message)"
            }
            return "Server error \(status)"
        case .decoding(let details):
            return "Failed to parse server response: \(details)"
        case .canceled:
            return "Generation canceled."
        }
    }
}
