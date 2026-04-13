import SwiftUI
import MarkdownUI
import Splash

/// Adapter that plugs `Splash`'s Swift-aware tokenizer into `MarkdownUI`'s
/// `CodeSyntaxHighlighter` protocol so fenced code blocks render with
/// highlighted tokens instead of flat monospaced text.
///
/// Splash is Swift-only by design. For other languages we fall back to the
/// default monospaced rendering — which is still readable, just uncolored.
struct SplashCodeSyntaxHighlighter: CodeSyntaxHighlighter {

    private let syntaxHighlighter: SyntaxHighlighter<TextOutputFormat>

    init(theme: Splash.Theme) {
        self.syntaxHighlighter = SyntaxHighlighter(format: TextOutputFormat(theme: theme))
    }

    func highlightCode(_ content: String, language: String?) -> Text {
        guard let language, language.lowercased() == "swift" else {
            return Text(content)
        }
        return syntaxHighlighter.highlight(content)
    }
}

extension CodeSyntaxHighlighter where Self == SplashCodeSyntaxHighlighter {
    static func splash(theme: Splash.Theme) -> Self {
        SplashCodeSyntaxHighlighter(theme: theme)
    }
}

// MARK: - Splash → SwiftUI.Text bridge

/// Splash ships with an AttributedString-style output format for AppKit, but
/// we need `SwiftUI.Text` fragments so MarkdownUI can compose them into its
/// code-block layout. This format re-emits tokens as concatenated `Text`
/// values with Splash's theme colors applied.
struct TextOutputFormat: OutputFormat {
    private let theme: Splash.Theme

    init(theme: Splash.Theme) {
        self.theme = theme
    }

    func makeBuilder() -> Builder {
        Builder(theme: theme)
    }

    struct Builder: OutputBuilder {
        private let theme: Splash.Theme
        private var accumulated = Text("")

        init(theme: Splash.Theme) {
            self.theme = theme
        }

        mutating func addToken(_ token: String, ofType type: TokenType) {
            let color = theme.tokenColors[type] ?? theme.plainTextColor
            accumulated = accumulated + Text(token).foregroundColor(Color(nsColor: color))
        }

        mutating func addPlainText(_ text: String) {
            accumulated = accumulated
                + Text(text).foregroundColor(Color(nsColor: theme.plainTextColor))
        }

        mutating func addWhitespace(_ whitespace: String) {
            accumulated = accumulated + Text(whitespace)
        }

        func build() -> Text { accumulated }
    }
}
