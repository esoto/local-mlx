import SwiftUI

struct ChatHeaderView: View {
    @Bindable var conversation: Conversation
    var modelsVM: ModelsViewModel?
    var onExport: (() -> Void)?

    @State private var showAdvanced = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                connectionDot
                modelPicker
                Spacer()
                if let onExport {
                    Button(action: onExport) {
                        Label("Export", systemImage: "square.and.arrow.up")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.bordered)
                    .help("Export chat as Markdown")
                }
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

    // MARK: - Connection dot

    @ViewBuilder private var connectionDot: some View {
        let status = modelsVM?.connectionStatus ?? .unknown
        let (color, help) = dotColor(for: status)
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .help(help)
    }

    private func dotColor(for status: ModelsViewModel.ConnectionStatus) -> (Color, String) {
        switch status {
        case .unknown:
            return (.gray, "Connection status unknown")
        case .online:
            return (.green, "Connected to MLX server")
        case .offline(let reason):
            return (.red, reason)
        }
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
                HStack {
                    Text("System prompt").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    presetMenu
                }
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

            HStack(alignment: .top, spacing: 16) {
                sliderBlock(title: "Temperature",
                            value: $conversation.temperature,
                            range: 0...1.5, step: 0.05, format: "%.2f")
                sliderBlock(title: "Top-p",
                            value: $conversation.topP,
                            range: 0...1, step: 0.05, format: "%.2f")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Max tokens  \(conversation.maxTokens)")
                        .font(.caption).foregroundStyle(.secondary)
                    Stepper(value: $conversation.maxTokens, in: 16...8192, step: 64) {
                        EmptyView()
                    }
                    .labelsHidden()
                }
            }

            HStack(alignment: .top, spacing: 16) {
                sliderBlock(title: "Presence penalty",
                            value: $conversation.presencePenalty,
                            range: -2...2, step: 0.1, format: "%.1f")
                sliderBlock(title: "Frequency penalty",
                            value: $conversation.frequencyPenalty,
                            range: -2...2, step: 0.1, format: "%.1f")
                sliderBlock(title: "Repetition penalty",
                            value: $conversation.repetitionPenalty,
                            range: 1...2, step: 0.05, format: "%.2f")
            }

            HStack(spacing: 8) {
                Text("Seed").font(.caption).foregroundStyle(.secondary)
                TextField("random", text: Binding(
                    get: { conversation.seed.map(String.init) ?? "" },
                    set: { newValue in
                        let trimmed = newValue.trimmingCharacters(in: .whitespaces)
                        conversation.seed = trimmed.isEmpty ? nil : Int(trimmed)
                    }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(width: 140)
                Button("Clear") { conversation.seed = nil }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Preset menu

    private var presetMenu: some View {
        Menu {
            ForEach(SystemPromptPresets.builtIn) { preset in
                Button {
                    conversation.systemPrompt = preset.content
                } label: {
                    Label(preset.name, systemImage: preset.icon)
                }
            }
        } label: {
            Label("Presets", systemImage: "square.stack.3d.up")
                .labelStyle(.titleAndIcon)
                .font(.caption)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    @ViewBuilder
    private func sliderBlock(title: String,
                             value: Binding<Double>,
                             range: ClosedRange<Double>,
                             step: Double.Stride,
                             format: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(title)  \(value.wrappedValue, specifier: format)")
                .font(.caption).foregroundStyle(.secondary)
            Slider(value: value, in: range, step: step)
                .frame(maxWidth: 220)
        }
    }
}
