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

// API Request/Response structures
struct ClaudeRequest: Codable {
    let model: String
    let max_tokens: Int
    let messages: [APIMessage]
    let system: String?
    
    struct APIMessage: Codable {
        let role: String
        let content: String
    }
}

struct ClaudeResponse: Codable {
    let id: String
    let content: [ContentBlock]
    let model: String
    let stop_reason: String?
    
    struct ContentBlock: Codable {
        let type: String
        let text: String?
    }
    
    var textContent: String {
        content.compactMap { $0.text }.joined()
    }
}

struct ClaudeError: Codable {
    let type: String
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let type: String
        let message: String
    }
}
