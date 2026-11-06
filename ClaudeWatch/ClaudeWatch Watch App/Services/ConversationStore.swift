import Foundation

/// Persists the current conversation on the watch so it survives app relaunches.
enum ConversationStore {
    private static let maxStoredMessages = 60

    private static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ) else { return nil }
        return base.appendingPathComponent("conversation.json")
    }

    static func load() -> [Message] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Message].self, from: data)) ?? []
    }

    static func save(_ messages: [Message]) {
        guard let url = fileURL else { return }
        let trimmed = Array(messages.filter { !$0.content.isEmpty }.suffix(maxStoredMessages))
        if trimmed.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(trimmed) {
            try? data.write(to: url, options: .atomic)
        }
    }
}
