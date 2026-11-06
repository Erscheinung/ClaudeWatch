import SwiftUI

@main
struct ClaudeWatchApp: App {
    @StateObject private var settings = AppSettings()
    @StateObject private var speech = SpeechSynthesisService()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(settings)
                .environmentObject(speech)
                .tint(.purple)
        }
    }
}
