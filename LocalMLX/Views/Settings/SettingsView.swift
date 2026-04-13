import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.mlxClient) private var clientHolder

    @State private var testState: TestState = .idle

    enum TestState: Equatable {
        case idle
        case testing
        case success(Int)
        case failure(String)
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
}
