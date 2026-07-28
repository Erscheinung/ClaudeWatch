import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings

    var body: some View {
        NavigationStack {
            if settings.isReady {
                ChatView()
            } else {
                WelcomeView()
            }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var showSettings = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "bolt.chat.fill")
                    .font(.system(size: 38))
                    .foregroundStyle(.cyan)

                Text("Quick Chat")
                    .font(.headline)

                Picker("Connection", selection: $settings.connectionMode) {
                    ForEach(ConnectionMode.allCases) { mode in
                        Text(mode.title).tag(mode)
                    }
                }

                Text(settings.connectionMode == .freeCloud ? "Choose a gateway to use the free model pool." : "Choose a model, then add that provider's key.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Button {
                    showSettings = true
                } label: {
                    Label(settings.connectionMode == .freeCloud ? "Gateway Setup" : "Add API Key", systemImage: "slider.horizontal.3")
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding(.horizontal, 10)
        }
        .navigationTitle("Quick Chat")
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
    }
}

#Preview {
    ContentView().environmentObject(AppSettings())
}
