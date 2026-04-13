import Foundation

/// Turns raw `MLXClientError` values into user-facing messages that tell
/// the user *what to do* rather than what the server literally said.
///
/// mlx-lm and mlx-vlm surface a handful of cryptic error strings in
/// production (things like `Only 'text' content type is supported.`)
/// that are accurate but provide no guidance. This translator looks for
/// those patterns and rewrites them with actionable instructions. Every
/// unknown error passes through to the raw `errorDescription` so we
/// never *lose* information — we just add a layer of friendliness on
/// top of it.
///
/// Pure so it can be unit-tested without touching a real server.
enum ServerErrorTranslator {

    /// Rewrite a client error into a user-visible string.
    /// Used for both the error banner in `ChatView` and the
    /// `interruptionReason` stored on the persisted assistant message.
    static func friendlyMessage(for error: MLXClientError) -> String {
        if case .http(_, let message?) = error,
           isVisionTextMismatch(message) {
            return """
            The running server doesn't support images. You're hitting \
            mlx_lm.server, which is text-only. To send images: stop the \
            server (Settings → Stop Server, or close its Terminal window), \
            pick a vision-capable model in the catalog — the ones marked \
            with 👁 — and click Start Server again. LocalMLX will \
            automatically launch mlx_vlm.server for vision models.
            """
        }
        return error.errorDescription ?? "Unknown error"
    }

    /// Does a server error message look like mlx_lm.server rejecting a
    /// multimodal request because it only handles text? The exact string
    /// at the time of writing is `Only 'text' content type is supported.`
    /// We match loosely on the distinguishing words so future mlx-lm
    /// versions that reword slightly still get caught.
    static func isVisionTextMismatch(_ message: String) -> Bool {
        let lower = message.lowercased()
        return lower.contains("'text'") && lower.contains("content type")
    }
}
