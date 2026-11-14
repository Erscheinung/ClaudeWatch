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

    /// Gemini-only Todoist day briefing. Opt-in: existing installs and fresh installs start off.
    @Published var todoistBriefingEnabled: Bool {
        didSet { UserDefaults.standard.set(todoistBriefingEnabled, forKey: Keys.todoistBriefingEnabled) }
    }
    @Published private(set) var hasTodoistToken: Bool

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
        static let todoistBriefingEnabled = "todoistBriefingEnabled"
        static let todoistDevSeeded = "todoistDevTokenSeeded"
    }

    /// Keychain accounts for the week digest (Todoist-Apple-Calendar sync's Function URL): the host and
    /// its bearer secret. Both live only in the Keychain; never in UserDefaults, logs, prompts or footers.
    static let weekDigestTokenAccount = "week-digest-token"
    static let weekDigestHostAccount = "week-digest-host"

    /// Keychain account for the separately provisioned Todoist read credential. It is never an
    /// AIProvider account, so replacing or removing it cannot touch provider keys (and vice versa).
    static let todoistReadTokenAccount = "todoist-read-token"

    init() {
        replyLength = ReplyLength(rawValue: UserDefaults.standard.string(forKey: Keys.replyLength) ?? "") ?? .balanced
        readAloud = UserDefaults.standard.object(forKey: Keys.readAloud) as? Bool ?? true
        voiceSlot = UserDefaults.standard.string(forKey: Keys.voiceSlot) ?? VoiceCatalog.defaultSlot
        speechSpeed = SpeechSpeed(rawValue: UserDefaults.standard.string(forKey: Keys.speechSpeed) ?? "") ?? .normal
        #if DEBUG
        Self.seedDevTodoistTokenIfNeeded()
        Self.seedDevWeekDigestIfNeeded()
        #endif
        let savedTodoistToken = KeychainStore.read(account: Self.todoistReadTokenAccount)?.isEmpty == false
        hasTodoistToken = savedTodoistToken
        todoistBriefingEnabled = savedTodoistToken && (UserDefaults.standard.object(forKey: Keys.todoistBriefingEnabled) as? Bool ?? false)
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

    #if DEBUG
    /// Debug builds only: copies the developer's Todoist read token from the gitignored repo-root
    /// `.env` (via ClaudeWatch/Config/DebugLocalSecrets.xcconfig → Info.plist `CWDevTodoistToken`)
    /// into the Keychain, once per install and only when no token is saved. It also turns the day
    /// briefing on unless the owner already chose a setting. Removing the account in Settings is
    /// respected: the seed never runs again for this install. Release has no such value.
    private static func seedDevTodoistTokenIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Keys.todoistDevSeeded),
              KeychainStore.read(account: todoistReadTokenAccount)?.isEmpty != false,
              let raw = Bundle.main.object(forInfoDictionaryKey: "CWDevTodoistToken") as? String else { return }
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty, !token.hasPrefix("$("), KeychainStore.save(token, account: todoistReadTokenAccount) else { return }
        defaults.set(true, forKey: Keys.todoistDevSeeded)
        if defaults.object(forKey: Keys.todoistBriefingEnabled) == nil {
            defaults.set(true, forKey: Keys.todoistBriefingEnabled)
        }
    }
    #endif

    #if DEBUG
    /// Debug builds only: copies WEEK_DIGEST_HOST / WEEK_DIGEST_TOKEN from the gitignored `.env`
    /// (DebugLocalSecrets.xcconfig → Info.plist) when no digest is configured yet. Release has none.
    private static func seedDevWeekDigestIfNeeded() {
        guard KeychainStore.read(account: weekDigestHostAccount)?.isEmpty != false,
              let host = Bundle.main.object(forInfoDictionaryKey: "CWDevWeekDigestHost") as? String,
              let token = Bundle.main.object(forInfoDictionaryKey: "CWDevWeekDigestToken") as? String,
              WeekDigestConfig(host: host, token: token) != nil else { return }
        let t = token.trimmingCharacters(in: .whitespacesAndNewlines), h = host.trimmingCharacters(in: .whitespacesAndNewlines)
        guard KeychainStore.save(t, account: weekDigestTokenAccount) else { return }
        if !KeychainStore.save(h, account: weekDigestHostAccount) { KeychainStore.delete(account: weekDigestTokenAccount) }
    }
    #endif

    /// Optional week digest (tasks + calendar free/busy). Nil unless both host and secret are saved.
    var weekDigestConfig: WeekDigestConfig? {
        WeekDigestConfig(host: KeychainStore.read(account: Self.weekDigestHostAccount) ?? "",
                         token: KeychainStore.read(account: Self.weekDigestTokenAccount) ?? "")
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

    // MARK: Todoist read-only account

    var todoistReadToken: String {
        KeychainStore.read(account: Self.todoistReadTokenAccount) ?? ""
    }

    /// Returns false when Keychain did not store the token, so the UI never claims a saved account.
    @discardableResult
    func setTodoistReadToken(_ token: String) -> Bool {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            removeTodoistReadToken()
            return true
        }
        let saved = KeychainStore.save(trimmed, account: Self.todoistReadTokenAccount)
        hasTodoistToken = saved || hasTodoistToken
        return saved
    }

    /// Removing the Todoist account disables the briefing; provider keys are untouched.
    func removeTodoistReadToken() {
        KeychainStore.delete(account: Self.todoistReadTokenAccount)
        hasTodoistToken = false
        todoistBriefingEnabled = false
    }

    /// The briefing runs only for an enabled feature, a saved Todoist token and a Gemini model with a key.
    /// Task data goes only to Gemini (docs/SCOPE.md); other providers never see it.
    var canUseDayBriefing: Bool {
        guard todoistBriefingEnabled, hasTodoistToken, let model = preferredModel else { return false }
        return model.provider == .google && hasAPIKey(for: .google)
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
