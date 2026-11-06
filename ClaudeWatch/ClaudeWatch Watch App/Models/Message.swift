import Foundation

struct Message: Identifiable, Codable, Equatable {
    let id: UUID
    let role: Role
    var content: String
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

// MARK: - API request / error payloads

struct ClaudeRequest: Encodable {
    let model: String
    let max_tokens: Int
    let stream: Bool
    let messages: [APIMessage]
    let system: String?
    let output_config: OutputConfig?

    struct APIMessage: Encodable {
        let role: String
        let content: String
    }

    struct OutputConfig: Encodable {
        let effort: String
    }
}

struct ClaudeError: Decodable {
    let type: String
    let error: ErrorDetail

    struct ErrorDetail: Decodable {
        let type: String
        let message: String
    }
}

/// One server-sent event from a streaming response (only the fields we use).
struct ClaudeStreamEvent: Decodable {
    let type: String
    let delta: Delta?
    let error: ClaudeError.ErrorDetail?

    struct Delta: Decodable {
        let type: String?
        let text: String?
        let stop_reason: String?
    }
}
