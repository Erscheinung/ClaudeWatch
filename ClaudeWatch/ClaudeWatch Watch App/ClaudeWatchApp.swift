import SwiftUI

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

class AppSettings: ObservableObject {
    @Published var selectedModel: ClaudeModel {
        didSet {
            UserDefaults.standard.set(selectedModel.rawValue, forKey: "selectedModel")
        }
    }
    
    @Published var apiKey: String {
        didSet {
            // Store in Keychain in production - using UserDefaults for simplicity
            UserDefaults.standard.set(apiKey, forKey: "claudeAPIKey")
        }
    }
    
    init() {
        let savedModel = UserDefaults.standard.string(forKey: "selectedModel") ?? ClaudeModel.sonnet.rawValue
        self.selectedModel = ClaudeModel(rawValue: savedModel) ?? .sonnet
        self.apiKey = UserDefaults.standard.string(forKey: "claudeAPIKey") ?? ""
    }
}
