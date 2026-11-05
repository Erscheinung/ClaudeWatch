import SwiftUI
import Security

@main
struct ClaudeWatchApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(settings.companion)
        }
    }
}
 
final class AppSettings: ObservableObject {
    let companion = CompanionConnection()
    @Published private(set) var liveGeminiModels: [AIModel] = []
    var availableModels: [AIModel] {
        let catalog = liveGeminiModels.isEmpty ? AIModel.allCases : AIModel.allCases.filter { $0.provider != .google } + liveGeminiModels
        return catalog.contains(selectedModel) ? catalog : catalog + [selectedModel]
    }
    static let defaultFreeCloudEndpoint = "https://text.pollinations.ai/openai"
    @Published var selectedModel: AIModel {
        didSet { UserDefaults.standard.set(selectedModel.storageKey, forKey: Keys.selectedModel) }
    }
    @Published var connectionMode: ConnectionMode {
        didSet { UserDefaults.standard.set(connectionMode.rawValue, forKey: Keys.connectionMode) }
    }
    @Published var gatewayURL: String {
        didSet { UserDefaults.standard.set(gatewayURL, forKey: Keys.gatewayURL) }
    }
    @Published private(set) var credentialRevision = 0
    @Published var fallbackEnabled: Bool {
        didSet { UserDefaults.standard.set(fallbackEnabled, forKey: Keys.fallbackEnabled) }
    }
    @Published var voiceInputMode: VoiceInputMode {
        didSet { UserDefaults.standard.set(voiceInputMode.rawValue, forKey: Keys.voiceInputMode) }
    }

    @Published var replyLength: ReplyLength {
        didSet { UserDefaults.standard.set(replyLength.rawValue, forKey: Keys.replyLength) }
    }

    @Published var readAloud: Bool {
        didSet { UserDefaults.standard.set(readAloud, forKey: Keys.readAloud) }
    }

    /// Which voice slot reads answers aloud ("female-1", "male-1", ...). See VoiceCatalog.
    @Published var voiceSlot: String {
        didSet { UserDefaults.standard.set(voiceSlot, forKey: Keys.voiceSlot) }
    }

    @Published var speechSpeed: SpeechSpeed {
        didSet { UserDefaults.standard.set(speechSpeed.rawValue, forKey: Keys.speechSpeed) }
    }

    private enum Keys {
        static let selectedModel = "selectedModel"
        static let connectionMode = "connectionMode"
        static let gatewayURL = "freeCloudGatewayURL"
        static let fallbackEnabled = "fallbackEnabled"
        static let voiceInputMode = "voiceInputMode"
        static let readAloud = "readAloud"
        static let replyLength = "replyLength"
        static let voiceSlot = "voiceSlot"
        static let speechSpeed = "speechSpeed"
        static let liveGeminiModels = "liveGeminiModels"
    }

    init() {
        replyLength = ReplyLength(rawValue: UserDefaults.standard.string(forKey: Keys.replyLength) ?? "") ?? .balanced
        readAloud = UserDefaults.standard.object(forKey: Keys.readAloud) as? Bool ?? true
        voiceSlot = UserDefaults.standard.string(forKey: Keys.voiceSlot) ?? VoiceCatalog.defaultSlot
        speechSpeed = SpeechSpeed(rawValue: UserDefaults.standard.string(forKey: Keys.speechSpeed) ?? "") ?? .normal
        let modelKey = UserDefaults.standard.string(forKey: Keys.selectedModel)
        selectedModel = modelKey.flatMap(AIModel.init(rawValue:)) ?? AIModel.geminiFlashLite
        let mode = UserDefaults.standard.string(forKey: Keys.connectionMode)
        connectionMode = ConnectionMode(rawValue: mode ?? "") ?? .bringYourOwnKey
        fallbackEnabled = UserDefaults.standard.object(forKey: Keys.fallbackEnabled) as? Bool ?? false
        voiceInputMode = VoiceInputMode(rawValue: UserDefaults.standard.string(forKey: Keys.voiceInputMode) ?? "") ?? .audio
        let savedGateway = UserDefaults.standard.string(forKey: Keys.gatewayURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        gatewayURL = savedGateway?.isEmpty == false ? savedGateway! : Self.defaultFreeCloudEndpoint
        if let data = UserDefaults.standard.data(forKey: Keys.liveGeminiModels),
           let models = try? JSONDecoder().decode([AIModel].self, from: data) {
            liveGeminiModels = models.filter { $0.provider == .google && !$0.isFreeCloudModel && AIModel.isValidModelID($0.rawValue) }
            if let restored = liveGeminiModels.first(where: { $0.storageKey == modelKey }) { selectedModel = restored }
        }
        normalizePreferredModel()
        companion.receiveSetup = { [weak self] setup in self?.applyCompanionSetup(setup) == true }
    }

    private func applyCompanionSetup(_ setup: CompanionSetup) -> Bool {
        guard setup.isValid else { return false }
        // Do not acknowledge until Keychain reports a successful write.
        guard KeychainStore.save(setup.apiKey, account: AIProvider.google.rawValue) else { return false }
        liveGeminiModels = setup.models
        if let data = try? JSONEncoder().encode(setup.models) {
            UserDefaults.standard.set(data, forKey: Keys.liveGeminiModels)
        }
        selectedModel = setup.selectedModel
        connectionMode = .bringYourOwnKey
        credentialRevision += 1
        return true
    }

    func apiKey(for provider: AIProvider) -> String {
        KeychainStore.read(account: provider.rawValue) ?? ""
    }

    func setAPIKey(_ value: String, for provider: AIProvider) {
        if value.isEmpty {
            KeychainStore.delete(account: provider.rawValue)
        } else {
            KeychainStore.save(value, account: provider.rawValue)
        }
        credentialRevision += 1
        if !value.isEmpty, let preferred = AIModel.preferredModel(for: provider) {
            selectedModel = preferred
            connectionMode = .bringYourOwnKey
        } else {
            normalizePreferredModel()
        }
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    var isReady: Bool {
        preferredModel != nil
    }

    /// The app only sends through a model whose provider has a key on this watch.
    /// Gemini wins when restoring older installs that still point at a free/Qwen model.
    var preferredModel: AIModel? {
        if hasAPIKey(for: selectedModel.provider), !selectedModel.isFreeCloudModel {
            return selectedModel
        }
        if hasAPIKey(for: .google) { return .geminiFlashLite }
        return AIProvider.allCases
            .first(where: hasAPIKey(for:))
            .flatMap(AIModel.preferredModel(for:))
    }

    func selectPreferredModel(_ model: AIModel) {
        guard hasAPIKey(for: model.provider), !model.isFreeCloudModel else { return }
        selectedModel = model
        connectionMode = .bringYourOwnKey
    }

    private func normalizePreferredModel() {
        if hasAPIKey(for: .google),
           connectionMode == .freeCloud || !hasAPIKey(for: selectedModel.provider) || selectedModel.isFreeCloudModel {
            selectedModel = .geminiFlashLite
            connectionMode = .bringYourOwnKey
        } else if let model = preferredModel {
            selectedModel = model
            connectionMode = .bringYourOwnKey
        }
    }

}

private enum KeychainStore {
    private static let service = "com.claudewatch.credentials"

    static func read(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ value: String, account: String) -> Bool {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let update = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if update == errSecSuccess { return true }
        guard update == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}
