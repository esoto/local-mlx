import SwiftUI

struct TranscriptView: View {
    let messages: [Message]
    let isStreaming: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages, id: \.id) { message in
                        MessageBubble(message: message)
                            .id(message.id)
                    }
                    // Invisible anchor to pin the scroll view to the bottom.
                    Color.clear
                        .frame(height: 1)
                        .id("bottom-anchor")
                }
                .padding(16)
            }
            .onChange(of: messages.last?.content) { _, _ in
                withAnimation(.linear(duration: 0.08)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation(.linear(duration: 0.1)) {
                    proxy.scrollTo("bottom-anchor", anchor: .bottom)
                }
            }
        }
    }
}
