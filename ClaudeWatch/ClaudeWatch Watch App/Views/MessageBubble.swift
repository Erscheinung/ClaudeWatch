import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 22) }
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 3) {
                Text(message.content)
                    .font(.system(size: 14))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(message.role == .user ? Color.cyan.opacity(0.82) : Color.white.opacity(0.13))
                    .foregroundStyle(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                if let model = message.model {
                    Text(model).font(.system(size: 9)).foregroundStyle(Color.secondary)
                }
            }
            if message.role == .assistant { Spacer(minLength: 22) }
        }
    }
}
