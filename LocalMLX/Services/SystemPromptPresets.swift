import Foundation

/// A reusable system prompt that the user can apply to a conversation with
/// one click. Built-in presets ship with the app; future versions can add
/// user-defined presets from a JSON file or `@AppStorage`.
struct SystemPromptPreset: Identifiable, Hashable, Sendable {
    /// Stable string id so tests and UI can reference a preset without
    /// relying on its display name (which we might localize later).
    let id: String
    let name: String
    /// SF Symbol shown next to the preset in menus.
    let icon: String
    let content: String
}

/// Catalog of built-in system-prompt presets. Kept as a plain static array
/// so it's pure, testable, and diffable in review.
enum SystemPromptPresets {

    static let builtIn: [SystemPromptPreset] = [
        .init(
            id: "default",
            name: "Default",
            icon: "sparkles",
            content: ""
        ),
        .init(
            id: "concise",
            name: "Concise",
            icon: "text.alignleft",
            content: "Be concise and direct. Skip the preamble. Answer in at most two short paragraphs unless the user asks for more."
        ),
        .init(
            id: "code-reviewer",
            name: "Code reviewer",
            icon: "chevron.left.forwardslash.chevron.right",
            content: """
            You are an experienced senior engineer reviewing code. For each snippet the user shares:
            1. Call out correctness issues first.
            2. Then point out security, performance, and clarity concerns.
            3. Suggest concrete, minimal changes — don't rewrite everything.
            Use Markdown. Use fenced code blocks for suggested diffs.
            """
        ),
        .init(
            id: "socratic",
            name: "Socratic teacher",
            icon: "questionmark.bubble",
            content: "You are a Socratic teacher. Do not give direct answers. Instead, respond with questions that guide the user to discover the answer themselves. Only break character if the user explicitly asks you to give the answer."
        ),
        .init(
            id: "summarizer",
            name: "Summarizer",
            icon: "list.bullet.rectangle",
            content: "Summarize the user's input as a tight bullet list. Preserve key facts and numbers. No introduction, no conclusion — just the bullets."
        ),
        .init(
            id: "brainstormer",
            name: "Brainstormer",
            icon: "lightbulb",
            content: "Generate a diverse list of ideas in response to whatever the user describes. Aim for 6 ideas. Mix obvious and unusual suggestions. Format as a numbered list with one-sentence explanations."
        ),
        .init(
            id: "translator-es",
            name: "Translator (Spanish)",
            icon: "character.book.closed",
            content: "Translate the user's input to natural, idiomatic Spanish. Output only the translation — no commentary, no romanization, no explanation."
        ),
        .init(
            id: "json-shaper",
            name: "JSON shaper",
            icon: "curlybraces",
            content: "You are a data extraction tool. Respond only with a single valid JSON object. Do not wrap it in Markdown fences. Do not include any commentary. If the user's input is ambiguous, make your best guess."
        ),
    ]

    /// Look up a preset by id. Returns nil if unknown.
    static func preset(withId id: String) -> SystemPromptPreset? {
        builtIn.first(where: { $0.id == id })
    }
}
