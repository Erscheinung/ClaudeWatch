import Foundation

struct Message: Identifiable, Codable {
    let id: UUID
    let role: Role
    let content: String
    let timestamp: Date
    let model: String?

    enum Role: String, Codable {
        case user
        case assistant
    }

    init(id: UUID = UUID(), role: Role, content: String, model: String? = nil) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = Date()
        self.model = model
    }
}
