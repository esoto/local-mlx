import SwiftUI

struct ChatHeaderView: View {
    @Bindable var conversation: Conversation
    var modelsVM: ModelsViewModel?

    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                modelPicker
                Spacer()
                Button {
                    showAdvanced.toggle()
                } label: {
                    Label("Options", systemImage: "slider.horizontal.3")
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
            }

            if showAdvanced {
                advancedControls
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .animation(.easeInOut(duration: 0.15), value: showAdvanced)
    }

    // MARK: - Model picker

    @ViewBuilder
    private var modelPicker: some View {
        let models = modelsVM?.models ?? []
        HStack(spacing: 6) {
            Image(systemName: "cpu")
                .foregroundStyle(.secondary)
            Picker("Model", selection: Binding(
                get: { conversation.modelId ?? "" },
                set: { conversation.modelId = $0.isEmpty ? nil : $0 }
            )) {
                if (conversation.modelId ?? "").isEmpty {
                    Text("Select a model…").tag("")
                }
                ForEach(models, id: \.self) { id in
                    Text(id).tag(id)
                }
                // If the current selection isn't in the loaded list (e.g.,
                // server was restarted with a different model) show it anyway
                // so the picker doesn't silently reset.
                if let current = conversation.modelId,
                   !models.contains(current),
                   !current.isEmpty {
                    Text("\(current)  (offline)").tag(current)
                }
            }
            .labelsHidden()

            Button {
                Task { await modelsVM?.refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Reload model list")
        }
    }

    // MARK: - Advanced controls

    private var advancedControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text("System prompt").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $conversation.systemPrompt)
                    .font(.body)
                    .frame(minHeight: 50, maxHeight: 100)
                    .padding(6)
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
            }

            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Temperature  \(conversation.temperature, specifier: "%.2f")")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $conversation.temperature, in: 0...1.5, step: 0.05)
                        .frame(maxWidth: 220)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top-p  \(conversation.topP, specifier: "%.2f")")
                        .font(.caption).foregroundStyle(.secondary)
                    Slider(value: $conversation.topP, in: 0...1, step: 0.05)
                        .frame(maxWidth: 220)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max tokens  \(conversation.maxTokens)")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $conversation.maxTokens, in: 16...8192, step: 64) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
            }
        }
    }
}
