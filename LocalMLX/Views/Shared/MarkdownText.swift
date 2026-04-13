import SwiftUI
import MarkdownUI

/// Thin wrapper around `MarkdownUI.Markdown` so we pick a single theme in one
/// place and the rest of the app just uses `MarkdownText(content:)`.
struct MarkdownText: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(.gitHub)
            .textSelection(.enabled)
    }
}
