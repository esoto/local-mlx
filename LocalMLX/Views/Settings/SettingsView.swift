import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.mlxClient) private var clientHolder

    @State private var testState: TestState = .idle
    @State private var launchState: LaunchState = .idle

    enum TestState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
    }

    enum LaunchState: Equatable {
        case idle
        case launched(String)   // absolute path of the .command file
        case failed(String)
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Base URL", text: $settings.baseURLString,
                          prompt: Text("http://localhost:8080"))
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Button("Test Connection") { Task { await testConnection() } }
                        .disabled(testState == .testing)
                    testStatusView
                }

                Divider().padding(.vertical, 4)

                TextField("Model (HF id or path)", text: $settings.mlxModelPath,
                          prompt: Text("mlx-community/Llama-3.2-3B-Instruct-4bit"))
                    .textFieldStyle(.roundedBorder)
                TextField("Python venv (optional)", text: $settings.pythonVenvPath,
                          prompt: Text("~/mlx-env"))
                    .textFieldStyle(.roundedBorder)

                Toggle("Run in background (detach from Terminal)",
                       isOn: $settings.serverRunInBackground)
                    .help("When enabled, the server is nohup'd and logged to ~/Library/Logs/LocalMLX/server.log. The Terminal window opens briefly to start it — you can close it immediately and the server keeps running. Use Stop Server to kill it.")

                HStack {
                    Button("Start Server") { launchServer() }
                        .disabled(settings.mlxModelPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Stop Server") { stopServer() }
                        .disabled(!settings.serverRunInBackground)
                        .help("Only available in background mode. Foreground servers are stopped by closing their Terminal window.")
                    Button("Install MLX…") { installMLX() }
                        .help("First-time setup: creates a Python virtualenv at ~/mlx-env and installs mlx-lm inside it. Opens in Terminal so you can watch the install.")
                    launchStatusView
                }

                Text("Writes a shell script to the app's Application Support folder and opens it in Terminal. The server runs as a separate process, so its memory (model weights, KV cache) is not counted against LocalMLX. In background mode, logs go to ~/Library/Logs/LocalMLX/server.log.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Section("Defaults for new chats") {
                TextField("Default system prompt", text: $settings.defaultSystemPrompt, axis: .vertical)
                    .lineLimit(2...5)

                HStack {
                    Text("Temperature")
                    Slider(value: $settings.defaultTemperature, in: 0...1.5, step: 0.05)
                    Text(String(format: "%.2f", settings.defaultTemperature))
                        .frame(width: 40)
                }
                HStack {
                    Text("Top-p")
                    Slider(value: $settings.defaultTopP, in: 0...1, step: 0.05)
                    Text(String(format: "%.2f", settings.defaultTopP))
                        .frame(width: 40)
                }
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Max output tokens")
                        Stepper(value: $settings.defaultMaxTokens, in: 16...16384, step: 64) {
                            Text("\(settings.defaultMaxTokens)")
                        }
                    }
                    Text("Upper bound on tokens per assistant reply. The model's own context window is set by the `mlx_lm.server` process, not here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    @ViewBuilder private var testStatusView: some View {
        switch testState {
        case .idle:
            EmptyView()
        case .testing:
            ProgressView().controlSize(.small)
        case .success(let count):
            Label("OK — \(count) model\(count == 1 ? "" : "s")", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failure(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
        }
    }

    @ViewBuilder private var launchStatusView: some View {
        switch launchState {
        case .idle:
            EmptyView()
        case .launched:
            Label("Script opened in Terminal", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.callout)
        case .failed(let msg):
            Label(msg, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .font(.callout)
                .lineLimit(2)
        }
    }

    private func testConnection() async {
        testState = .testing
        do {
            let ids = try await clientHolder.client.listModels()
            testState = .success(ids.count)
        } catch let err as MLXClientError {
            testState = .failure(err.errorDescription ?? "Unknown error")
        } catch {
            testState = .failure(error.localizedDescription)
        }
    }

    private func launchServer() {
        let port = AppSettings.makeBaseURL().port ?? 8080
        let config = ServerLauncher.Config(
            modelPath: settings.mlxModelPath,
            pythonVenvPath: settings.pythonVenvPath,
            port: port,
            background: settings.serverRunInBackground
        )
        do {
            let url = try ServerLauncher.writeAndLaunch(config)
            launchState = .launched(url.path)
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }

    private func stopServer() {
        do {
            _ = try ServerLauncher.writeAndLaunchStop()
            launchState = .launched("Stop script opened in Terminal")
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }

    private func installMLX() {
        do {
            let url = try ServerLauncher.writeAndLaunchInstall()
            launchState = .launched(url.path)
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }
}
