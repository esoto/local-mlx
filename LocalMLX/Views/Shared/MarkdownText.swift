import SwiftUI
import MarkdownUI
import Splash

/// Thin wrapper around `MarkdownUI.Markdown` so we pick a single theme and
/// code highlighter in one place. Swift fenced code blocks get Splash-based
/// syntax highlighting; other languages fall back to plain monospaced text.
struct MarkdownText: View {
    let content: String

    var body: some View {
        Markdown(content)
            .markdownTheme(.gitHub)
            .markdownCodeSyntaxHighlighter(.splash(theme: .sunset(withFont: .init(size: 13))))
            .textSelection(.enabled)
    }
}
