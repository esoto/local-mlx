import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.mlxClient) private var clientHolder

    @State private var testState: TestState = .idle
    @State private var launchState: LaunchState = .idle
    @State private var modelStatus: ModelDownloadStatus = .unknown(reason: "not yet checked")
    @State private var isCheckingStatus: Bool = false
    /// Handle to the in-flight status check so we can cancel it
    /// before starting a new one. Stored in view state (rather than
    /// using `.task(id:)`) because `.task(id:)` restarts on every
    /// change to its id — and wiring that to `settings.mlxModelPath`
    /// restarted it on every keystroke, which interacted badly with
    /// macOS TextField focus and blocked typing.
    @State private var statusCheckTask: Task<Void, Never>?

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

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("Model")
                    modelCatalogMenu
                    Spacer()
                    modelStatusBadge
                    Button { triggerStatusRefresh() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Re-check whether this model is cached and up to date on HuggingFace.")
                    .disabled(isCheckingStatus
                              || settings.mlxModelPath.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                TextField("Model path",
                          text: $settings.mlxModelPath,
                          prompt: Text("mlx-community/Llama-3.2-3B-Instruct-4bit"))
                    .textFieldStyle(.roundedBorder)
                    .help("HuggingFace repo id or on-disk path. mlx-lm will download the model on first launch if it isn't cached yet. Press Return to re-check download status.")
                    .onSubmit { triggerStatusRefresh() }
                TextField("Python venv (optional)", text: $settings.pythonVenvPath,
                          prompt: Text("~/mlx-env"))
                    .textFieldStyle(.roundedBorder)

                Toggle("Run in background (detach from Terminal)",
                       isOn: $settings.serverRunInBackground)
                    .help("When enabled, the server is nohup'd and logged to ~/Library/Logs/LocalMLX/server.log. The Terminal window opens briefly to start it — you can close it immediately and the server keeps running. Use Stop Server to kill it.")

                // Row 1 — runtime actions on the currently configured model.
                HStack {
                    Button("Start Server") { launchServer() }
                        .disabled(settings.mlxModelPath.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Stop Server") { stopServer() }
                        .disabled(!settings.serverRunInBackground)
                        .help("Only available in background mode. Foreground servers are stopped by closing their Terminal window.")
                    launchStatusView
                    Spacer()
                }

                // Row 2 — model management. Split out of row 1 so four
                // buttons don't overflow the 480px-wide Settings window.
                // Button enablement is driven by `modelStatus`: Download
                // when not cached (or unknown), Update only when there's
                // a newer revision upstream.
                HStack {
                    Button("Download Model…") { downloadModel() }
                        .disabled(!canDownload)
                        .help("Pre-fetches the selected model via huggingface-cli so you can see real download progress in Terminal. Enabled when the model isn't cached locally.")
                    Button("Update Model…") { updateModel() }
                        .disabled(!canUpdate)
                        .help("Forces a fresh re-download, replacing the cached copy with the latest mlx-community build. Only enabled when LocalMLX has detected a newer revision on HuggingFace than what you have cached.")
                    Button("Install MLX…") { installMLX() }
                        .help("First-time setup: creates a Python virtualenv at ~/mlx-env and installs mlx-lm inside it. Opens in Terminal so you can watch the install.")
                    Spacer()
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
        // Fire a single status check the first time Settings opens.
        // Subsequent refreshes are triggered explicitly — catalog
        // menu picks, Return in the model path field, or the small
        // refresh button next to the status badge. Critically NOT
        // on every keystroke: `.task(id: settings.mlxModelPath)`
        // restarts on each character change, and on macOS that
        // loop interfered with TextField input.
        .onAppear { triggerStatusRefresh() }
    }

    private var canDownload: Bool {
        let hasPath = !settings.mlxModelPath.trimmingCharacters(in: .whitespaces).isEmpty
        return hasPath && modelStatus.canDownload
    }

    private var canUpdate: Bool {
        let hasPath = !settings.mlxModelPath.trimmingCharacters(in: .whitespaces).isEmpty
        return hasPath && modelStatus.canUpdate
    }

    /// Compact label next to the model picker. Tells the user whether
    /// the currently selected model is cached, updatable, or not yet
    /// downloaded — and explains why a button is greyed out.
    @ViewBuilder
    private var modelStatusBadge: some View {
        if settings.mlxModelPath.trimmingCharacters(in: .whitespaces).isEmpty {
            EmptyView()
        } else if isCheckingStatus {
            HStack(spacing: 4) {
                ProgressView().controlSize(.small)
                Text("checking…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            switch modelStatus {
            case .notDownloaded:
                Label("Not downloaded", systemImage: "arrow.down.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .upToDate:
                Label("Up to date", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            case .updateAvailable:
                Label("Update available", systemImage: "arrow.clockwise.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            case .unknown:
                Label("Status unknown", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Couldn't reach HuggingFace to compare revisions. Download stays enabled so you can try anyway.")
            }
        }
    }

    /// Kick off a fresh status check, cancelling any in-flight one.
    /// Called from discrete user actions (appear, menu pick, Return
    /// in the text field, explicit refresh button) — never from a
    /// reactive binding that fires on keystrokes.
    private func triggerStatusRefresh() {
        statusCheckTask?.cancel()
        let path = settings.mlxModelPath.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else {
            modelStatus = .unknown(reason: "no model selected")
            isCheckingStatus = false
            return
        }
        isCheckingStatus = true
        statusCheckTask = Task { @MainActor in
            let status = await ModelDownloadStatusResolver.resolve(repoId: path)
            if !Task.isCancelled {
                modelStatus = status
            }
            isCheckingStatus = false
        }
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

    // MARK: - Model catalog menu

    /// Dropdown with curated mlx-community models grouped by family.
    /// Selecting an entry fills in `mlxModelPath`; users can still type
    /// a custom path in the TextField below the menu.
    @ViewBuilder
    private var modelCatalogMenu: some View {
        Menu {
            ForEach(MLXModelCatalog.groupedByFamily, id: \.family) { group in
                Section(group.family.rawValue) {
                    ForEach(group.entries) { entry in
                        Button {
                            settings.mlxModelPath = entry.id
                            triggerStatusRefresh()
                        } label: {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack {
                                    Text("\(entry.displayName)  •  \(formatSize(entry.approxSizeGB))")
                                    if entry.isVision {
                                        Image(systemName: "eye")
                                    }
                                }
                                Text(entry.blurb)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Divider()
            // Field below is the place to type a custom path; this is
            // just a hint row in the menu so the option is discoverable.
            Text("Or type any path in the field below ↓")
                .font(.caption)
                .foregroundStyle(.secondary)
        } label: {
            if let entry = MLXModelCatalog.find(settings.mlxModelPath) {
                Label("\(entry.displayName) • \(formatSize(entry.approxSizeGB))",
                      systemImage: entry.isVision ? "eye" : "cpu")
            } else if settings.mlxModelPath.isEmpty {
                Label("Choose a model…", systemImage: "cpu")
            } else {
                Label("Custom", systemImage: "square.and.pencil")
            }
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    private func formatSize(_ gb: Double) -> String {
        String(format: "%.1f GB", gb)
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
        // Auto-pick vision mode from the catalog if the model is a
        // known vision entry. Custom paths default to text mode.
        let isVisionModel = MLXModelCatalog.find(settings.mlxModelPath)?.isVision ?? false
        let config = ServerLauncher.Config(
            modelPath: settings.mlxModelPath,
            pythonVenvPath: settings.pythonVenvPath,
            port: port,
            background: settings.serverRunInBackground,
            vision: isVisionModel
        )
        do {
            let url = try ServerLauncher.writeAndLaunch(config)
            launchState = .launched(url.path)
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }

    private func stopServer() {
        let port = AppSettings.makeBaseURL().port ?? 8080
        do {
            _ = try ServerLauncher.writeAndLaunchStop(port: port)
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

    private func downloadModel() {
        do {
            let url = try ServerLauncher.writeAndLaunchDownload(
                modelPath: settings.mlxModelPath,
                pythonVenvPath: settings.pythonVenvPath)
            launchState = .launched(url.path)
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }

    private func updateModel() {
        do {
            let url = try ServerLauncher.writeAndLaunchUpdate(
                modelPath: settings.mlxModelPath,
                pythonVenvPath: settings.pythonVenvPath)
            launchState = .launched(url.path)
        } catch {
            launchState = .failed(error.localizedDescription)
        }
    }
}
