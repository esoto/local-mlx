import Foundation

/// Minimal Server-Sent Events line parser scoped to what mlx-lm emits.
///
/// The full SSE spec supports `id:`, `event:`, `retry:`, and multi-line `data:`
/// reassembly. mlx-lm only sends single-line `data:` frames plus blank
/// separators, so we honor those and discard everything else as a no-op. This
/// is pure and synchronous so it has straightforward unit tests.
enum SSEParser {

    enum Event: Equatable {
        /// A `data: <payload>` frame. The payload has SSE framing stripped but
        /// is NOT JSON-decoded here; the caller does that.
        case data(String)
        /// The `data: [DONE]` sentinel OpenAI-compatible servers send to mark
        /// end-of-stream before the connection closes.
        case done
    }

    /// Parse a single SSE line. Returns `nil` for blanks, comments, or non-`data:`
    /// fields. Per SSE spec, exactly one leading space after the `:` is stripped.
    ///
    /// Accepts both `\n` and `\r\n` terminated lines — `URLSession.AsyncBytes.lines`
    /// strips the `\n` but leaves the `\r`, which would otherwise make `[DONE]`
    /// comparisons fail.
    static func parse(line rawLine: String) -> Event? {
        // Drop a single trailing CR if present.
        var line = rawLine
        if line.hasSuffix("\r") {
            line = String(line.dropLast())
        }

        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return nil }
        if trimmed.hasPrefix(":") { return nil } // comment / heartbeat

        // SSE field lines look like `field: value` or `field:value`.
        // We only care about `data:`.
        guard let colonIdx = line.firstIndex(of: ":") else { return nil }
        let field = line[..<colonIdx]
        if field != "data" { return nil }

        // Strip the colon, then one optional leading space per spec.
        var rest = line[line.index(after: colonIdx)...]
        if rest.first == " " {
            rest = rest.dropFirst()
        }

        let payload = String(rest)
        if payload == "[DONE]" { return .done }
        return .data(payload)
    }
}
