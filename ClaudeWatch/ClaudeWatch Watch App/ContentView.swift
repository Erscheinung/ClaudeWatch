import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        if settings.isReady {
            ChatView()
        } else {
            WelcomeView()
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.cyan)
            Text("Set up Gemini").font(.headline)
            Text("Add your Gemini API key once, then start chatting and dictating.")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            Button { showSettings = true } label: {
                Label("Add Gemini Key", systemImage: "key.fill")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cyan)
        }
        .padding(.horizontal, 12)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    ContentView().environmentObject(AppSettings())
}
