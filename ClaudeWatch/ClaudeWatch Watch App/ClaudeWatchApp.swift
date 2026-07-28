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

    private enum Keys {
        static let selectedModel = "selectedModel"
        static let connectionMode = "connectionMode"
        static let gatewayURL = "freeCloudGatewayURL"
    }

    init() {
        let modelKey = UserDefaults.standard.string(forKey: Keys.selectedModel)
        selectedModel = modelKey.flatMap(AIModel.init(rawValue:)) ?? AIModel.defaultFreeCloudModel
        let mode = UserDefaults.standard.string(forKey: Keys.connectionMode)
        connectionMode = ConnectionMode(rawValue: mode ?? "") ?? .freeCloud
        let savedGateway = UserDefaults.standard.string(forKey: Keys.gatewayURL)?.trimmingCharacters(in: .whitespacesAndNewlines)
        gatewayURL = savedGateway?.isEmpty == false ? savedGateway! : Self.defaultFreeCloudEndpoint
        if connectionMode == .freeCloud, !selectedModel.isFreeCloudModel {
            selectedModel = AIModel.defaultFreeCloudModel
        }
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
    }

    func hasAPIKey(for provider: AIProvider) -> Bool {
        !apiKey(for: provider).isEmpty
    }

    var isReady: Bool {
        switch connectionMode {
        case .freeCloud:
            return !gatewayURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .bringYourOwnKey:
            return hasAPIKey(for: selectedModel.provider)
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
