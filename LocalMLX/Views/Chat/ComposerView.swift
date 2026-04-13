import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ComposerView: View {
    @Binding var text: String
    @Binding var attachments: [ChatViewModel.PendingAttachment]
    let isStreaming: Bool
    let canSend: Bool
    let onSend: () -> Void
    let onStop: () -> Void

    @FocusState private var focused: Bool
    @State private var isDropTargeted = false
    @State private var isPresentingPicker = false

    var body: some View {
        VStack(spacing: 8) {
            if !attachments.isEmpty {
                attachmentStrip
            }

            HStack(alignment: .bottom, spacing: 8) {
                attachButton
                textEditor
                if isStreaming {
                    stopButton
                } else {
                    sendButton
                }
            }
        }
        .padding(12)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isDropTargeted ? Color.accentColor : Color.clear,
                    style: StrokeStyle(lineWidth: 2, dash: [6, 4])
                )
                .padding(6)
        )
        .onDrop(of: [UTType.image, UTType.fileURL],
                isTargeted: $isDropTargeted) { providers in
            handleDrop(providers: providers)
            return true
        }
        .fileImporter(
            isPresented: $isPresentingPicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                handleFileURLs(urls)
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var textEditor: some View {
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
            // ⌘V: intercept and try the pasteboard for an image
            // before letting the text editor handle it normally.
            .onKeyPress(keys: ["v"], phases: .down) { press in
                guard press.modifiers.contains(.command) else { return .ignored }
                if pasteImageFromClipboard() { return .handled }
                return .ignored
            }
    }

    private var attachButton: some View {
        Button {
            isPresentingPicker = true
        } label: {
            Image(systemName: "paperclip")
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.bordered)
        .help("Attach image(s)")
    }

    private var sendButton: some View {
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

    private var stopButton: some View {
        Button(action: onStop) {
            Label("Stop", systemImage: "stop.fill")
                .labelStyle(.iconOnly)
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .help("Stop generating")
        .keyboardShortcut(".", modifiers: .command)
    }

    @ViewBuilder
    private var attachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(attachments.enumerated()), id: \.offset) { index, attachment in
                    AttachmentThumbnail(
                        data: attachment.data,
                        onRemove: { removeAttachment(at: index) }
                    )
                }
            }
            .padding(.vertical, 4)
        }
        .frame(height: 72)
    }

    // MARK: - Actions

    private func handleSubmit() {
        guard canSend else { return }
        onSend()
    }

    private func removeAttachment(at index: Int) {
        guard attachments.indices.contains(index) else { return }
        attachments.remove(at: index)
    }

    private func handleDrop(providers: [NSItemProvider]) {
        for provider in providers {
            // Prefer the image UTI so screenshots and raw images come
            // through as data; fall back to a file URL so things
            // Finder-dragged from disk still work.
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadDataRepresentation(
                    forTypeIdentifier: UTType.image.identifier
                ) { data, _ in
                    if let data = data {
                        attachDataInBackground(data, mimeType: "image/png")
                    }
                }
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadItem(
                    forTypeIdentifier: UTType.fileURL.identifier,
                    options: nil
                ) { item, _ in
                    guard let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil),
                          let fileData = try? Data(contentsOf: url)
                    else { return }
                    let mime = mimeForURL(url)
                    attachDataInBackground(fileData, mimeType: mime)
                }
            }
        }
    }

    private func handleFileURLs(_ urls: [URL]) {
        for url in urls {
            guard let data = try? Data(contentsOf: url) else { continue }
            attachDataInBackground(data, mimeType: mimeForURL(url))
        }
    }

    private func pasteImageFromClipboard() -> Bool {
        let pb = NSPasteboard.general
        if let image = pb.readObjects(forClasses: [NSImage.self])?.first as? NSImage,
           let data = imagePNGData(image) {
            attachDataInBackground(data, mimeType: "image/png")
            return true
        }
        return false
    }

    /// Process raw image bytes off the main thread, then hop back to
    /// update the `@State attachments` binding. The processing step
    /// (NSImage decode + JPEG re-encode) can be hundreds of
    /// milliseconds for a large screenshot — doing it on main made
    /// Send clicks feel unresponsive after a big drop.
    private func attachDataInBackground(_ data: Data, mimeType: String) {
        Task.detached(priority: .userInitiated) {
            guard let processed = ImageProcessing.process(data, originalMimeType: mimeType) else {
                return
            }
            let pending = ChatViewModel.PendingAttachment(
                data: processed.data,
                mimeType: processed.mimeType,
                width: processed.width,
                height: processed.height)
            await MainActor.run {
                attachments.append(pending)
            }
        }
    }

    // MARK: - Helpers

    private func mimeForURL(_ url: URL) -> String {
        guard let type = UTType(filenameExtension: url.pathExtension) else {
            return "image/png"
        }
        if type.conforms(to: .jpeg) { return "image/jpeg" }
        if type.conforms(to: .png)  { return "image/png" }
        if type.conforms(to: .gif)  { return "image/gif" }
        if type.conforms(to: .webP) { return "image/webp" }
        if type.conforms(to: .heic) { return "image/heic" }
        return "image/png"
    }

    private func imagePNGData(_ image: NSImage) -> Data? {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: - Attachment thumbnail

private struct AttachmentThumbnail: View {
    let data: Data
    let onRemove: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let image = NSImage(data: data) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                    )
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 64, height: 64)
                    .overlay(Image(systemName: "photo"))
            }
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.white, .black.opacity(0.7))
            }
            .buttonStyle(.plain)
            .offset(x: 4, y: -4)
            .help("Remove attachment")
        }
    }
}
