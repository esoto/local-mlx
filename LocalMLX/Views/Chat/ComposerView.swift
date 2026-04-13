import SwiftUI

struct ComposerView: View {
    @Binding var text: String
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextEditor(text: $text)
                .font(.system(.body))
                .frame(minHeight: 40, maxHeight: 140)
                .padding(6)
                .background(Color(NSColor.textBackgroundColor))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                )
                .focused($focused)
                .onAppear { focused = true }
                // Enter sends, Shift+Enter inserts a newline. ⌘↩ still
                // works via the Send button's keyEquivalent below.
                .onKeyPress(keys: [.return], phases: .down) { press in
                    if press.modifiers.contains(.shift) { return .ignored }
                    handleSubmit()
                    return .handled
                }

            if isStreaming {
                Button(action: onStop) {
                    Label("Stop", systemImage: "stop.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .help("Stop generating")
                .keyboardShortcut(".", modifiers: .command)
            } else {
                Button(action: handleSubmit) {
                    Label("Send", systemImage: "paperplane.fill")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .help("Send (⌘⏎)")
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
    }

    private func handleSubmit() {
        guard canSend else { return }
        onSend()
    }
}
