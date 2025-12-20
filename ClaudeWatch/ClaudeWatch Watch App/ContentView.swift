import SwiftUI

struct ContentView: View {
    @EnvironmentObject var settings: AppSettings
    
    var body: some View {
        NavigationStack {
            if settings.apiKey.isEmpty {
                SetupView()
            } else {
                ChatView()
            }
        }
    }
}

struct SetupView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var tempAPIKey: String = ""
    
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "sparkles")
                    .font(.system(size: 40))
                    .foregroundStyle(.purple)
                
                Text("Claude Watch")
                    .font(.headline)
                
                Text("Enter your Anthropic API key to get started")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                
                TextField("API Key", text: $tempAPIKey)
                    .textContentType(.password)
                
                Button("Save") {
                    settings.apiKey = tempAPIKey
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(tempAPIKey.isEmpty)
            }
            .padding()
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppSettings())
}
