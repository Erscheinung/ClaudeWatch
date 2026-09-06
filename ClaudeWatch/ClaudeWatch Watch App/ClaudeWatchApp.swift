import SwiftUI
import Security

@main
struct ClaudeWatchApp: App {
    @StateObject private var settings = AppSettings()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
        }
    }
}
 
final class AppSettings: ObservableObject {
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

    @Published var readAloud: Bool {
        didSet { UserDefaults.standard.set(readAloud, forKey: Keys.readAloud) }
    }

    private enum Keys {
        static let selectedModel = "selectedModel"
        static let connectionMode = "connectionMode"
        static let gatewayURL = "freeCloudGatewayURL"
        static let fallbackEnabled = "fallbackEnabled"
        static let voiceInputMode = "voiceInputMode"
        static let readAloud = "readAloud"
    }

    init() {
        readAloud = UserDefaults.standard.object(forKey: Keys.readAloud) as? Bool ?? true
        let modelKey = UserDefaults.standard.string(forKey: Keys.selectedModel)
        selectedModel = modelKey.flatMap(AIModel.init(rawValue:)) ?? AIModel.geminiFlashLite
        let mode = UserDefaults.standard.string(forKey: Keys.connectionMode)
        connectionMode = ConnectionMode(rawValue: mode ?? "") ?? .bringYourOwnKey
        fallbackEnabled = UserDefaults.standard.object(forKey: Keys.fallbackEnabled) as? Bool ?? false
        voiceInputMode = VoiceInputMode(rawValue: UserDefaults.standard.string(forKey: Keys.voiceInputMode) ?? "") ?? .audio
        let savedGateway = UserDefaults.standard.string(forKey: Keys.gatewayURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        gatewayURL = savedGateway?.isEmpty == false ? savedGateway! : Self.defaultFreeCloudEndpoint
        normalizePreferredModel()
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

    static func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData as String] = data
        SecItemAdd(item as CFDictionary, nil)
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
