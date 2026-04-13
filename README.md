# LocalMLX

A native macOS chat app for a local [`mlx-lm`](https://github.com/ml-explore/mlx-lm) server — like Ollama's chat UI, but talking to Apple's MLX framework on Apple Silicon.

## Features

- **Multi-conversation sidebar** with new/rename/delete, persisted via SwiftData.
- **Live token streaming** from `mlx_lm.server` with a Stop button that cancels mid-generation.
- **Model picker** populated from `GET /v1/models`.
- **Per-chat system prompt** and sampling controls (temperature, top_p, max tokens).
- **Markdown rendering** with fenced code blocks via [swift-markdown-ui](https://github.com/gonzalezreal/swift-markdown-ui).
- **Configurable server URL** — defaults to `http://localhost:8080`; also works with LM Studio or a remote MLX box.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 15 or newer
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the `.xcodeproj`
- Python 3.10+ with `mlx-lm` for the backend server

## Building

```sh
# one-time
brew install xcodegen

# from the repo root
xcodegen generate
open LocalMLX.xcodeproj       # then press ⌘R in Xcode to run
```

## Running the MLX server (for testing)

In a separate terminal:

```sh
python3 -m venv .venv && source .venv/bin/activate
pip install mlx-lm
mlx_lm.server --model mlx-community/Llama-3.2-3B-Instruct-4bit --port 8080

# sanity check
curl http://localhost:8080/v1/models
```

Then hit **Test Connection** in the app's Settings to confirm it sees your server.

## Running tests

```sh
xcodebuild test -project LocalMLX.xcodeproj -scheme LocalMLX \
                -destination 'platform=macOS'
```

The test suite covers:

- OpenAI-compatible DTO encoding/decoding
- SSE frame parsing (including malformed frames and `[DONE]`)
- `MLXClient.listModels()` and `streamChat()` happy paths, HTTP errors, cancellation
- `Conversation`/`Message` SwiftData cascade deletes
- `ChatViewModel` send/stop/error flow and auto-titling

All tests run fully offline against a `MockURLProtocol`.

## Project layout

```
LocalMLX/
  App/                # @main, ModelContainer, @AppStorage settings
  Models/             # SwiftData @Model: Conversation, Message
  Networking/         # MLXClient (OpenAI-compatible) + DTOs + errors
  ViewModels/         # @Observable ChatViewModel, ModelsViewModel
  Views/              # SwiftUI: RootView, Sidebar, Chat, Settings
LocalMLXTests/        # XCTest + MockURLProtocol + fixtures
project.yml           # XcodeGen source of truth
```
