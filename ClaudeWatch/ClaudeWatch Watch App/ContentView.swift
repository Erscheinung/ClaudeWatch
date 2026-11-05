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
    @EnvironmentObject private var companion: CompanionConnection
    @State private var showSettings = false
    @State private var showPhoneSetup = false

    var body: some View {
        ScrollView {
          VStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.cyan)
            Text("Connect an AI").font(.headline)
            Button { showPhoneSetup = true } label: {
                Label("Set up from iPhone", systemImage: "iphone")
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.cyan)
            Text("Paste your Gemini key on iPhone, then send it to this watch.")
                .font(.caption2)
                .foregroundStyle(Color.secondary)
                .multilineTextAlignment(.center)
            Button { showSettings = true } label: {
                Label("Enter a key here", systemImage: "key.fill")
            }
            .buttonStyle(.bordered)
          }
          .padding(.horizontal, 12)
        }
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showPhoneSetup) {
            NavigationStack {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Open the ClaudeWatch companion on your paired iPhone.")
                        Text("Paste a Gemini API key, tap Verify key, choose a model, then tap Send to Watch. Keep this app open during transfer.")
                            .font(.caption)
                        Text(companion.status).font(.caption2).foregroundStyle(.secondary)
                    }.padding()
                }
                .navigationTitle("iPhone setup")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showPhoneSetup = false } } }
            }
        }
    }
}

#Preview {
    let settings = AppSettings()
    ContentView().environmentObject(settings).environmentObject(settings.companion)
}
