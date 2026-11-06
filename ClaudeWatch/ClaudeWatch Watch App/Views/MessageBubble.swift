import SwiftUI

struct MessageBubble: View {
    let message: Message
    let isSpeaking: Bool
    var onToggleSpeak: (() -> Void)?

    private var isUser: Bool { message.role == .user }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if isUser { Spacer(minLength: 16) }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 4) {
                Text(MarkdownLite.attributed(message.content))
                    .font(.footnote)
                    .multilineTextAlignment(.leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(isUser ? Color.purple : Color(white: 0.18))
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                if !isUser {
                    footer
                }
            }

            if !isUser { Spacer(minLength: 16) }
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            if let onToggleSpeak {
                Button(action: onToggleSpeak) {
                    Image(systemName: isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(isSpeaking ? Color.white : Color.purple)
                        .frame(width: 34, height: 26)
                        .background(isSpeaking ? Color.purple : Color.purple.opacity(0.22), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isSpeaking ? "Stop reading" : "Read aloud")
            }

            if let model = message.model {
                Text(model)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 4)
    }
}

#Preview {
    ScrollView {
        VStack(spacing: 8) {
            MessageBubble(message: Message(role: .user, content: "Hello Claude!"), isSpeaking: false)
            MessageBubble(
                message: Message(role: .assistant, content: "Hello! **How** can I help you today?\n- Ask a question\n- Get a summary", model: "Sonnet 5.5"),
                isSpeaking: false,
                onToggleSpeak: {}
            )
        }
        .padding(.horizontal, 4)
    }
}
