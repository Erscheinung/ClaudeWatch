import SwiftUI
import Security

@main
struct ClaudeWatchPhoneApp: App {
    @StateObject private var setup = PhoneSetupModel()
    @StateObject private var connection = CompanionConnection()

    var body: some Scene {
        WindowGroup {
            PhoneSetupView()
                .environmentObject(setup)
                .environmentObject(connection)
        }
    }
}

@MainActor
final class PhoneSetupModel: ObservableObject {
    @Published var apiKey = PhoneKeychain.read() {
        didSet {
            guard apiKey != oldValue else { return }
            cancelVerification()
            models = []
            selectedModel = nil
            verifiedKey = nil
            message = "Verify this key to fetch available Gemini models."
        }
    }
    @Published private(set) var models: [AIModel] = []
    @Published var selectedModel: AIModel?
    @Published private(set) var isVerifying = false
    @Published private(set) var message = "Your Gemini key is stored in Keychain on each device."
    private var verifiedKey: String?
    private var verification: Task<Void, Never>?
    private var requestID: UUID?

    var payload: CompanionSetup? {
        guard let verifiedKey, verifiedKey == apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
              let selectedModel else { return nil }
        return CompanionSetup(version: 1, apiKey: verifiedKey, selectedModel: selectedModel, models: models)
    }

    func verify() {
        cancelVerification()
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, key.count <= 1024 else {
            message = "Paste a Gemini API key first."
            return
        }
        let id = UUID()
        requestID = id
        isVerifying = true
        verifiedKey = nil
        models = []
        selectedModel = nil
        message = "Checking your key with Google…"
        verification = Task { [weak self] in
            do {
                let models = try await GeminiModelCatalog.fetch(apiKey: key)
                try Task.checkCancellation()
                guard let self, self.requestID == id else { return }
                guard PhoneKeychain.save(key) else {
                    self.message = "The key was verified, but iPhone Keychain could not save it. Try again."
                    self.isVerifying = false
                    self.requestID = nil
                    self.verification = nil
                    return
                }
                self.models = models
                self.selectedModel = models.first { $0.rawValue == AIModel.geminiFlashLite.rawValue }
                    ?? models.first { $0.rawValue.contains("flash-lite") } ?? models.first
                self.verifiedKey = key
                self.message = "Key verified. Google returned \(models.count) compatible models. Model access and quota can still vary."
            } catch {
                guard let self, self.requestID == id, !Task.isCancelled else { return }
                self.message = (error as? GeminiModelCatalog.CatalogError)?.errorDescription
                    ?? "Could not fetch models. Check your connection and try again."
            }
            guard let self, self.requestID == id else { return }
            self.isVerifying = false
            self.requestID = nil
            self.verification = nil
        }
    }

    func cancelVerification() {
        requestID = nil
        verification?.cancel()
        verification = nil
        if isVerifying { message = "Verification cancelled. Tap Verify key to try again." }
        isVerifying = false
    }

    func removeLocalKey() {
        guard PhoneKeychain.remove() else {
            message = "Could not remove the iPhone copy. Try again."
            return
        }
        apiKey = ""
        message = "iPhone copy removed. The key on your watch is unchanged."
    }
}

private struct PhoneSetupView: View {
    @EnvironmentObject private var setup: PhoneSetupModel
    @EnvironmentObject private var connection: CompanionConnection
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label("Set up your watch", systemImage: "applewatch")
                        .font(.title2.bold())
                    Text("Paste a Gemini key here, verify it with Google, then send your chosen model and key to your paired watch.")
                }
                Section("1 · Gemini API key") {
                    SecureField("Paste your API key", text: $setup.apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .privacySensitive()
                        .disabled(connection.isSending)
                    Link("Get a key from Google AI Studio", destination: URL(string: "https://aistudio.google.com/apikey")!)
                    if setup.isVerifying {
                        HStack { ProgressView(); Text("Verifying key…"); Spacer(); Button("Cancel") { setup.cancelVerification() } }
                    } else {
                        Button("Verify key") { setup.verify() }
                            .disabled(setup.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || connection.isSending)
                    }
                    Text(setup.message).font(.footnote).foregroundStyle(.secondary)
                }
                if !setup.models.isEmpty {
                    Section("2 · Choose a model") {
                        Picker("Model", selection: $setup.selectedModel) {
                            ForEach(setup.models) { model in
                                Text(model.displayName).tag(Optional(model))
                            }
                        }
                        .disabled(connection.isSending)
                        if let model = setup.selectedModel {
                            Text(model.rawValue).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                }
                Section("3 · Send to Watch") {
                    Button("Check watch connection") { connection.checkConnection() }
                        .disabled(connection.isSending)
                    Button {
                        if let payload = setup.payload { connection.send(payload) }
                    } label: {
                        Label(connection.isSending ? "Sending…" : "Send to Watch", systemImage: "applewatch.radiowaves.left.and.right")
                    }
                    .disabled(setup.payload == nil || connection.isSending)
                    Text(connection.status).font(.footnote).foregroundStyle(.secondary)
                    Text("Keep ClaudeWatch open on your watch. Success appears only after the watch saves your key. If the watch is offline, reconnect and send again.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Privacy") {
                    Text("Your key goes to Google for verification and directly to your paired watch through Apple WatchConnectivity. It is stored in Keychain, never in a web link or analytics. No ClaudeWatch server is involved.")
                        .font(.footnote)
                    Button("Remove iPhone copy", role: .destructive) { setup.removeLocalKey() }
                        .disabled(connection.isSending || setup.apiKey.isEmpty)
                }
            }
            .navigationTitle("ClaudeWatch")
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { setup.cancelVerification() }
        }
    }
}

private enum PhoneKeychain {
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: "com.claudewatch.companion.credentials",
         kSecAttrAccount as String: "google"]
    }
    static func read() -> String {
        var query = query
        query[kSecReturnData as String] = true
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }
    static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecSuccess { return true }
        guard status == errSecItemNotFound else { return false }
        var item = query
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }
    static func remove() -> Bool {
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
