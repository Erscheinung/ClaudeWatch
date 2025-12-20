import SwiftUI

struct MessageBubble: View {
    let message: Message
    
    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 20)
            }
            
            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.system(size: 14))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(backgroundColor)
                    .foregroundStyle(foregroundColor)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                
                if let model = message.model {
                    Text(model)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
            }
            
            if message.role == .assistant {
                Spacer(minLength: 20)
            }
        }
    }
    
    private var backgroundColor: Color {
        switch message.role {
        case .user:
            return .purple
        case .assistant:
            return Color(.darkGray)
        }
    }
    
    private var foregroundColor: Color {
        .white
    }
}

#Preview {
    VStack {
        MessageBubble(message: Message(role: .user, content: "Hello Claude!"))
        MessageBubble(message: Message(role: .assistant, content: "Hello! How can I help you today?", model: "Sonnet 4.5"))
    }
    .padding()
}
