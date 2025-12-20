import Foundation

enum ClaudeModel: String, CaseIterable, Identifiable {
    case opus = "claude-opus-4-5-20251101"
    case sonnet = "claude-sonnet-4-5-20250929"
    case haiku = "claude-haiku-4-5-20251001"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .opus: return "Opus 4.5"
        case .sonnet: return "Sonnet 4.5"
        case .haiku: return "Haiku 4.5"
        }
    }
    
    var shortName: String {
        switch self {
        case .opus: return "Opus"
        case .sonnet: return "Sonnet"
        case .haiku: return "Haiku"
        }
    }
    
    var icon: String {
        switch self {
        case .opus: return "brain.head.profile"
        case .sonnet: return "sparkles"
        case .haiku: return "bolt"
        }
    }
    
    var color: String {
        switch self {
        case .opus: return "purple"
        case .sonnet: return "orange"
        case .haiku: return "green"
        }
    }
}
