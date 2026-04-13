# LocalMLX

A native macOS chat app for a local [`mlx-lm`](https://github.com/ml-explore/mlx-lm) server — like Ollama's chat UI, but talking to Apple's MLX framework on Apple Silicon.

## Features

- **Multi-conversation sidebar** with new/rename/delete, persisted via SwiftData, grouped by date (Today, Yesterday, Last 7 days, Last 30 days, Older).
- **Search across all chats** by title and message content.
- **Multi-window:** right-click any conversation in the sidebar and pick "Open in New Window" to work on two chats side-by-side.
- **Live token streaming** from `mlx_lm.server` with a Stop button that cancels mid-generation and preserves partial content.
- **Tokens-per-second** and token counts displayed on each assistant reply, sourced from the server's `usage` payload with a wall-clock fallback.
- **Stream-interrupted footer** on the specific message when a stream errors mid-response — your partial reply is never silently dropped.
- **Regenerate, edit-and-resend, fork, delete, and copy** buttons on every message (hover to reveal). Forking creates a new conversation branched from exactly that message.
- **System-prompt presets** (Concise, Code reviewer, Socratic teacher, Summarizer, Brainstormer, Translator, JSON shaper) one click from the chat header.
- **Model picker** from `/v1/models` with refresh and an "offline" fallback marker when the selected model isn't currently loaded.
- **Auto-polling connection status dot** in the chat header — green / red / gray, refreshed every 15 seconds in the background.
- **Per-chat system prompt** and full sampling controls: temperature, top_p, max tokens, presence / frequency / repetition penalties, and an optional seed.
- **Markdown rendering** with fenced code blocks and **Swift syntax highlighting** via [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) + [Splash](https://github.com/JohnSundell/Splash).
- **Empty-chat state** with example prompts so a fresh chat isn't just a blinking cursor.
- **Export** any chat as Markdown via the header button, with a system file picker.
- **Configurable server URL** — defaults to `http://localhost:8080`; also works with LM Studio or a remote MLX box.
- **Shortcuts:** ⌘N new chat, ⌘⏎ send, ⌘. stop.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 15 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`
- Python 3.10+ with `mlx-lm` for the backend server

## Building

```sh
# one-time
brew install xcodegen

# optional but recommended: generate the app icon PNGs (runs on macOS)
swift tools/generate-icon.swift

# from the repo root
xcodegen generate
open LocalMLX.xcodeproj       # then press ⌘R in Xcode to run
```

The icon generator is a standalone Swift script that uses AppKit / Core Graphics to draw a purple-to-blue gradient with the sparkles glyph at all required `@2x` sizes and writes them into `LocalMLX/Resources/Assets.xcassets/AppIcon.appiconset/`. Run it once — the PNGs can be checked in.

## Running the MLX server (for testing)

In a separate terminal:

```sh
python3 -m venv .venv && source .venv/bin/activate
pip install mlx-lm
mlx_lm.server --model mlx-community/Llama-3.2-3B-Instruct-4bit --port 8080

# sanity check
curl http://localhost:8080/v1/models
```

Then hit **Test Connection** in the app's Settings to confirm it sees your server, or watch the connection dot in the chat header.

## Running tests

```sh
xcodebuild test -project LocalMLX.xcodeproj -scheme LocalMLX \
                -destination 'platform=macOS'
```

The test suite is fully offline — it uses `MockURLProtocol` to drive `LiveMLXClient` with scripted responses, and a `FakeMLXClient` to exercise `ChatViewModel`. It covers:

- **DTOs**: `ChatRequest` JSON shape, including extra sampling params and `stream_options`; `ChatChunk` with role-only / content / finish-reason / usage variants; `ModelList` fixture; `ServerErrorBody`.
- **SSE**: blank / comment / non-data fields, `[DONE]` sentinel, one-space stripping, trailing `\r`, malformed frames skipped.
- **MLXClient**: `listModels` 200 + fixture, HTTP 404 with decoded server message, `cannotConnectToHost` → `.unreachable`, `streamChat` yields `StreamEvent.delta` sequences, captures `StreamEvent.usage` from the final chunk, 4xx mid-request decoding, mid-stream cancellation.
- **SwiftData models**: in-memory round-trip, ordering, cascade delete.
- **ChatViewModel**: send inserts user + assistant placeholder and streams deltas, `updatedAt` from injected clock, auto-title at 40 chars, stop preserves partial, error path sets banner and writes `interruptionReason` on the assistant message, usage and tok/s populated on the assistant message, `regenerate` replaces only the last assistant reply, `editAndResend` updates the user message and regenerates, `delete` removes messages.
- **ChatExporter**: Markdown rendering with system prompt, message ordering, token metadata, interruption notes, filename sanitization.
- **SidebarGrouping**: Today / Yesterday / Last 7 days / Last 30 days / Older bucketing with deterministic clock and sort-within-bucket.

## Continuous integration

GitHub Actions runs `xcodegen generate && xcodebuild test` on every push and PR on a `macos-14` runner with Xcode 15.4. See `.github/workflows/ci.yml`.

## Project layout

```
LocalMLX/
  App/                # @main, ModelContainer, @AppStorage settings
  Models/             # SwiftData @Model: Conversation, Message
  Networking/         # MLXClient + DTOs + SSE parser + errors
  Services/           # ChatExporter (Markdown)
  ViewModels/         # @Observable ChatViewModel, ModelsViewModel
  Views/              # SwiftUI: RootView, Sidebar, Chat, Settings, Shared
  PrivacyInfo.xcprivacy
LocalMLXTests/        # XCTest + MockURLProtocol + fixtures
.github/workflows/    # CI pipeline
project.yml           # XcodeGen source of truth
```

## Dependencies

| Package | Purpose |
|---|---|
| [gonzalezreal/swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui) | Markdown rendering with a pluggable code highlighter |
| [JohnSundell/Splash](https://github.com/JohnSundell/Splash) | Swift syntax highlighter plugged into MarkdownUI |

No tracking, no analytics, no cloud. All chats live in a local SwiftData store under `~/Library/Containers/dev.localmlx.LocalMLX/`.
