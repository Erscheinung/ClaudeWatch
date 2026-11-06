import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        if settings.isConfigured {
            NavigationStack { ChatView() }
        } else {
            SetupView()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
        .environmentObject(SpeechSynthesisService())
}
