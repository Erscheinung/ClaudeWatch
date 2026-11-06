import Foundation

/// An AI provider the app can talk to. Add a case here (plus a transport in ChatAPIService) to support another.
enum Provider: String, CaseIterable, Identifiable, Codable {
    case anthropic
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .gemini: return "Google Gemini"
        }
    }

    /// Short name used for the navigation title.
    var shortName: String {
        switch self {
        case .anthropic: return "Claude"
        case .gemini: return "Gemini"
        }
    }

    var icon: String {
        switch self {
        case .anthropic: return "sparkles"
        case .gemini: return "diamond.fill"
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .gemini: return "AIza…"
        }
    }

    var keyHelp: String {
        switch self {
        case .anthropic: return "Key from console.anthropic.com"
        case .gemini: return "Key from aistudio.google.com"
        }
    }
}

/// A model the user can chat with, as reported by the provider's own model list.
struct ModelInfo: Identifiable, Codable, Hashable {
    let id: String
    let name: String

    /// "Claude Haiku 5.5" -> "Haiku 5.5", "Gemini 3.5 Flash-Lite" -> "3.5 Flash-Lite"
    var shortName: String {
        name.replacingOccurrences(of: "Claude ", with: "")
            .replacingOccurrences(of: "Gemini ", with: "")
    }

    var icon: String {
        let lower = id.lowercased()
        if lower.contains("lite") || lower.contains("haiku") { return "bolt.fill" }
        if lower.contains("opus") || lower.contains("pro") { return "brain.head.profile" }
        return "sparkles"
    }

    /// Used when the live model list can't be fetched (offline) for Anthropic.
    static let anthropicFallback: [ModelInfo] = [
        ModelInfo(id: "claude-haiku-5-5", name: "Claude Haiku 5.5"),
        ModelInfo(id: "claude-sonnet-5-5", name: "Claude Sonnet 5.5"),
        ModelInfo(id: "claude-opus-5-5", name: "Claude Opus 5.5"),
    ]
}
