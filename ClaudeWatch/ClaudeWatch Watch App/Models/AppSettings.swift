import SwiftUI
import AVFoundation

enum SpeechSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var rate: Float {
        switch self {
        case .slow: return 0.44
        case .normal: return AVSpeechUtteranceDefaultSpeechRate
        case .fast: return 0.57
        }
    }
}

enum ResponseLength: String, CaseIterable, Identifiable {
    case brief, balanced, detailed
    var id: String { rawValue }

    var label: String { rawValue.capitalized }

    var promptHint: String {
        switch self {
        case .brief: return "Keep replies under 60 words."
        case .balanced: return "Keep replies under 120 words."
        case .detailed: return "You may use up to about 250 words, but stay compact."
        }
    }

    /// Output ceiling. Generous on purpose: the model's reasoning shares this budget.
    var maxTokens: Int {
        switch self {
        case .brief: return 1024
        case .balanced: return 1536
        case .detailed: return 3072
        }
    }
}

final class AppSettings: ObservableObject {
    private enum Key {
        static let provider = "provider"
        static let legacyModel = "selectedModel"
        static let legacyAPIKey = "claudeAPIKey"
        static let legacyKeychain = "anthropic-api-key"
        static let autoSpeak = "autoSpeak"
        static let voiceSlot = "voiceSlot"
        static let speechSpeed = "speechSpeed"
        static let length = "responseLength"
        static let haptics = "hapticsEnabled"
        static let todoistBriefingEnabled = "todoistBriefingEnabled"
        static let todoistReadToken = "todoist-read-token"
        static func keychain(_ p: Provider) -> String { "api-key-\(p.rawValue)" }
        static func model(_ p: Provider) -> String { "model-\(p.rawValue)" }
    }

    private let defaults = UserDefaults.standard

    /// The provider currently used for chat.
    @Published private(set) var provider: Provider
    @Published private var keys: [Provider: String] = [:]
    @Published private var models: [Provider: ModelInfo] = [:]

    /// Read replies aloud automatically. Off by default; the per-message speaker button always works.
    @Published var autoSpeak: Bool { didSet { defaults.set(autoSpeak, forKey: Key.autoSpeak) } }
    @Published var voiceSlot: String { didSet { defaults.set(voiceSlot, forKey: Key.voiceSlot) } }
    @Published var speechSpeed: SpeechSpeed { didSet { defaults.set(speechSpeed.rawValue, forKey: Key.speechSpeed) } }
    @Published var responseLength: ResponseLength { didSet { defaults.set(responseLength.rawValue, forKey: Key.length) } }
    @Published var hapticsEnabled: Bool { didSet { defaults.set(hapticsEnabled, forKey: Key.haptics) } }
    /// Gemini-only Todoist reads are opt-in and remain off for existing installs.
    @Published var todoistBriefingEnabled: Bool { didSet { defaults.set(todoistBriefingEnabled, forKey: Key.todoistBriefingEnabled) } }
    @Published private(set) var hasTodoistToken: Bool

    init() {
        provider = Provider(rawValue: defaults.string(forKey: Key.provider) ?? "") ?? .anthropic
        autoSpeak = defaults.object(forKey: Key.autoSpeak) as? Bool ?? false
        voiceSlot = defaults.string(forKey: Key.voiceSlot) ?? VoiceCatalog.defaultSlot
        speechSpeed = SpeechSpeed(rawValue: defaults.string(forKey: Key.speechSpeed) ?? "") ?? .normal
        responseLength = ResponseLength(rawValue: defaults.string(forKey: Key.length) ?? "") ?? .brief
        hapticsEnabled = defaults.object(forKey: Key.haptics) as? Bool ?? true
        todoistBriefingEnabled = defaults.object(forKey: Key.todoistBriefingEnabled) as? Bool ?? false
        hasTodoistToken = KeychainStore.get(Key.todoistReadToken)?.isEmpty == false

        for p in Provider.allCases {
            if let key = KeychainStore.get(Key.keychain(p)) { keys[p] = key }
            if let data = defaults.data(forKey: Key.model(p)),
               let model = try? JSONDecoder().decode(ModelInfo.self, from: data) { models[p] = model }
        }
        migrateFromEarlierVersions()
        seedFromLaunchEnvironment()
    }

    /// Development convenience: lets `devicectl ... --environment-variables` provision a key and model
    /// without typing on the watch. Compiled out of release builds; nothing is hardcoded.
    private func seedFromLaunchEnvironment() {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment
        guard let raw = env["CLAUDEWATCH_SEED_PROVIDER"], let provider = Provider(rawValue: raw),
              let key = env["CLAUDEWATCH_SEED_KEY"], !key.isEmpty else { return }
        setKey(key, for: provider)
        if let id = env["CLAUDEWATCH_SEED_MODEL"], !id.isEmpty {
            activate(provider, model: ModelInfo(id: id, name: id))
        }
        #endif
    }

    // MARK: Provider / key / model

    var apiKey: String { keys[provider] ?? "" }
    var model: ModelInfo? { models[provider] }

    /// True once the active provider has both a key and a chosen model.
    var isConfigured: Bool { !apiKey.isEmpty && model != nil }

    func key(for provider: Provider) -> String { keys[provider] ?? "" }

    func setKey(_ key: String, for provider: Provider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            keys[provider] = nil
            KeychainStore.delete(Key.keychain(provider))
        } else {
            keys[provider] = trimmed
            KeychainStore.set(trimmed, for: Key.keychain(provider))
        }
    }

    // MARK: Todoist read-only account

    /// Separate from provider keys so a Todoist credential can be replaced or removed independently.
    var todoistReadToken: String { KeychainStore.get(Key.todoistReadToken) ?? "" }

    func setTodoistReadToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            removeTodoistReadToken()
        } else {
            KeychainStore.set(trimmed, for: Key.todoistReadToken)
            hasTodoistToken = true
        }
    }

    func removeTodoistReadToken() {
        KeychainStore.delete(Key.todoistReadToken)
        hasTodoistToken = false
        todoistBriefingEnabled = false
    }

    func model(for provider: Provider) -> ModelInfo? { models[provider] }

    /// Makes `provider` + `model` the active choice (used when finishing setup or switching in Settings).
    func activate(_ provider: Provider, model: ModelInfo) {
        models[provider] = model
        if let data = try? JSONEncoder().encode(model) { defaults.set(data, forKey: Key.model(provider)) }
        self.provider = provider
        defaults.set(provider.rawValue, forKey: Key.provider)
    }

    /// Keys and model choices saved by earlier builds (Anthropic-only) carry over.
    private func migrateFromEarlierVersions() {
        if keys[.anthropic] == nil {
            let legacy = KeychainStore.get(Key.legacyKeychain) ?? defaults.string(forKey: Key.legacyAPIKey) ?? ""
            if !legacy.isEmpty { setKey(legacy, for: .anthropic) }
        }
        KeychainStore.delete(Key.legacyKeychain)
        defaults.removeObject(forKey: Key.legacyAPIKey)

        if models[.anthropic] == nil, keys[.anthropic] != nil {
            let stored = defaults.string(forKey: Key.legacyModel) ?? ""
            let choice = ModelInfo.anthropicFallback.first { stored.contains($0.shortName.lowercased().split(separator: " ")[0]) }
                ?? ModelInfo.anthropicFallback[1]
            models[.anthropic] = choice
            if let data = try? JSONEncoder().encode(choice) { defaults.set(data, forKey: Key.model(.anthropic)) }
        }
        defaults.removeObject(forKey: Key.legacyModel)
    }

    // MARK: Prompt

    /// System prompt tuned for a tiny screen, and for being read aloud when auto-speak is on.
    var systemPrompt: String {
        let format = autoSpeak
            ? "Your reply will be read aloud, so write plain conversational sentences with no markdown, lists, tables, code blocks, emoji or URLs, and spell out symbols."
            : "Light markdown (bold, short bullet lists) is fine; avoid tables and headings."
        return "You are a helpful assistant responding on an Apple Watch. The screen is tiny, so lead with the answer and be direct. \(responseLength.promptHint) \(format)"
    }
}
