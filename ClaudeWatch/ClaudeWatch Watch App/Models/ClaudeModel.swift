import Foundation

enum VoiceInputMode: String, CaseIterable, Identifiable {
    case text
    case audio

    var id: String { rawValue }
    var title: String { self == .text ? "Text" : "Audio" }
    var detail: String {
        self == .text
            ? "Gemini transcribes your recording, then sends the text to your selected model. Requires a Gemini key."
            : "The recording is sent directly to Gemini for understanding."
    }
}

enum ConnectionMode: String, CaseIterable, Identifiable {
    case freeCloud
    case bringYourOwnKey

    var id: String { rawValue }

    var title: String {
        switch self {
        case .freeCloud: return "Fallback"
        case .bringYourOwnKey: return "Gemini & keys"
        }
    }

    var icon: String {
        switch self {
        case .freeCloud: return "cloud.fill"
        case .bringYourOwnKey: return "key.fill"
        }
    }
}

enum AIProvider: String, CaseIterable, Identifiable {
    case openRouter
    case groq
    case anthropic
    case openAI
    case google
    case perplexity
    case pollinations

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        case .anthropic: return "Anthropic"
        case .openAI: return "OpenAI"
        case .google: return "Google AI"
        case .perplexity: return "Perplexity"
        case .pollinations: return "Pollinations"
        }
    }

    var apiKeyPlaceholder: String {
        switch self {
        case .openRouter: return "sk-or-..."
        case .groq: return "gsk_..."
        case .anthropic: return "sk-ant-..."
        case .openAI: return "sk-..."
        case .google: return "AIza..."
        case .perplexity: return "pplx-..."
        case .pollinations: return "pollen_..."
        }
    }
}

struct AIModel: RawRepresentable, Identifiable, Hashable {
    let rawValue: String
    let provider: AIProvider
    let displayName: String
    let family: String
    let icon: String
    let isFreeCloudModel: Bool

    var id: String { "\(provider.rawValue):\(rawValue)" }
    var shortName: String { displayName.replacingOccurrences(of: " ", with: "") }

    init?(rawValue: String) {
        guard let model = Self.allCases.first(where: { $0.storageKey == rawValue }) else { return nil }
        self = model
    }

    init(rawValue: String, provider: AIProvider, displayName: String, family: String, icon: String, isFreeCloudModel: Bool) {
        self.rawValue = rawValue
        self.provider = provider
        self.displayName = displayName
        self.family = family
        self.icon = icon
        self.isFreeCloudModel = isFreeCloudModel
    }

    var storageKey: String { "\(provider.rawValue)|\(rawValue)" }

    static let pollinationsFast = AIModel(rawValue: "openai", provider: .pollinations, displayName: "OpenAI Fast", family: "Free cloud", icon: "bolt.fill", isFreeCloudModel: true)
    static let qwenFree = AIModel(rawValue: "qwen/qwen3-4b:free", provider: .openRouter, displayName: "Qwen3 4B", family: "OpenRouter", icon: "bolt.fill", isFreeCloudModel: false)
    static let kimiFree = AIModel(rawValue: "moonshotai/kimi-k2:free", provider: .openRouter, displayName: "Kimi K2", family: "OpenRouter", icon: "wand.and.stars", isFreeCloudModel: false)
    static let gemmaFree = AIModel(rawValue: "google/gemma-3-4b-it:free", provider: .openRouter, displayName: "Gemma 3 4B", family: "OpenRouter", icon: "leaf.fill", isFreeCloudModel: false)
    static let groqLlama = AIModel(rawValue: "llama-3.1-8b-instant", provider: .groq, displayName: "Llama 3.1 8B", family: "Groq", icon: "hare.fill", isFreeCloudModel: false)
    static let groqGPTOSS = AIModel(rawValue: "openai/gpt-oss-20b", provider: .groq, displayName: "GPT-OSS 20B", family: "Groq", icon: "hare.fill", isFreeCloudModel: false)
    static let haiku = AIModel(rawValue: "claude-haiku-4-5-20251001", provider: .anthropic, displayName: "Claude Haiku", family: "Anthropic", icon: "sparkles", isFreeCloudModel: false)
    static let gptNano = AIModel(rawValue: "gpt-4.1-nano", provider: .openAI, displayName: "GPT-4.1 Nano", family: "OpenAI", icon: "bolt.fill", isFreeCloudModel: false)
    static let gptMini = AIModel(rawValue: "gpt-4o-mini", provider: .openAI, displayName: "GPT-4o mini", family: "OpenAI", icon: "bolt.fill", isFreeCloudModel: false)
    static let geminiFlashLite = AIModel(rawValue: "gemini-3.5-flash-lite", provider: .google, displayName: "Gemini 3.5 Flash-Lite", family: "Google AI", icon: "sparkles", isFreeCloudModel: false)
    static let sonar = AIModel(rawValue: "sonar", provider: .perplexity, displayName: "Perplexity Sonar", family: "Perplexity", icon: "globe", isFreeCloudModel: false)

    static let allCases: [AIModel] = [
        pollinationsFast, qwenFree, kimiFree, gemmaFree, groqLlama, groqGPTOSS,
        geminiFlashLite, haiku, gptNano, gptMini, sonar
    ]

    static let defaultFreeCloudModel = pollinationsFast

    static func preferredModel(for provider: AIProvider) -> AIModel? {
        if provider == .google { return geminiFlashLite }
        return allCases.first { $0.provider == provider && !$0.isFreeCloudModel }
    }
}
