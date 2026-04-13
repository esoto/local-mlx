import SwiftUI
import AppKit

/// Tiny icon button that copies a string to the pasteboard and briefly
/// swaps its icon to a checkmark for feedback.
struct CopyButton: View {
    let textProvider: () -> String
    var compact: Bool = false

    @State private var justCopied = false

    var body: some View {
        Button(action: copy) {
            Image(systemName: justCopied ? "checkmark" : "doc.on.doc")
                .font(compact ? .caption2 : .caption)
                .frame(width: compact ? 16 : 20, height: compact ? 16 : 20)
        }
        .buttonStyle(.borderless)
        .help(justCopied ? "Copied" : "Copy")
        .foregroundStyle(justCopied ? .green : .secondary)
    }

    private func copy() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(textProvider(), forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) { justCopied = true }
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) { justCopied = false }
        }
    }
}
