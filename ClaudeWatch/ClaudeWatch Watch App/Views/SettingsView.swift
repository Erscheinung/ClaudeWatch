import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var editingProvider: AIProvider?
    @State private var showGatewayEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("Replies") {
                    Toggle("Read aloud", isOn: $settings.readAloud)
                    Text(settings.readAloud ? "Answers appear as text and are read aloud." : "Answers appear as text only. Tap the speaker on an answer to listen.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("Voice") {
                    Picker("Send as", selection: $settings.voiceInputMode) {
                        ForEach(VoiceInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(settings.voiceInputMode.detail).font(.caption2).foregroundStyle(Color.secondary)
                    Text(settings.voiceInputMode == .text ? "Lowest cost · works with every model" : "Natural voice context · Gemini only")
                        .font(.caption2)
                        .foregroundStyle(settings.voiceInputMode == .text ? Color.green : Color.orange)
                }
                Section("Model") {
                    NavigationLink { ModelPickerView() } label: {
                        HStack { Image(systemName: (settings.preferredModel ?? .geminiFlashLite).icon).foregroundStyle(Color.cyan); Text(settings.preferredModel?.displayName ?? "Add a key"); Spacer(); Text(settings.preferredModel?.provider.displayName ?? "").font(.caption2).foregroundStyle(Color.secondary) }
                    }
                }
                Section("Gemini") {
                    Button { editingProvider = .google } label: {
                        HStack { Image(systemName: "key.fill").foregroundStyle(settings.hasAPIKey(for: .google) ? Color.green : Color.orange); Text(settings.hasAPIKey(for: .google) ? "Gemini key added" : "Add Gemini key"); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.secondary) }
                    }
                    Text("Your key stays in this watch’s Keychain.").font(.caption2).foregroundStyle(Color.secondary)
                }
                Section("Usage & billing") {
                    NavigationLink { UsageView() } label: { Label("Usage on this watch", systemImage: "chart.bar.fill") }
                }
                Section("Other providers") {
                    ForEach(AIProvider.allCases.filter { $0 != .google }) { provider in
                        Button { editingProvider = provider } label: {
                            HStack { Text(provider.displayName); Spacer(); Text(settings.hasAPIKey(for: provider) ? "Added" : "Add").font(.caption2).foregroundStyle(Color.secondary) }
                        }
                    }
                }
                Section("Help") {
                    NavigationLink { SetupHelpView() } label: { Label("Setup guide", systemImage: "book.closed.fill") }
                }
            }
            .navigationTitle("Settings")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(item: $editingProvider) { APIKeyEditorView(provider: $0) }
            .sheet(isPresented: $showGatewayEditor) { GatewayEditorView() }
        }
    }
}

private struct UsageView: View {
    @EnvironmentObject private var settings: AppSettings
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: "indianrupeesign.circle.fill").font(.title2).foregroundStyle(Color.yellow)
                Text("Gemini usage").font(.headline)
                Text("The Gemini API does not provide an account balance or remaining prepaid credit to watch apps. Showing a rupee amount here would be misleading.").font(.caption)
                Text("Check your actual balance and detailed usage in Google AI Studio or your Google Cloud billing account.").font(.caption).foregroundStyle(Color.secondary)
                Divider()
                Text("Voice input cost").font(.headline)
                Text("Gemini 3.5 Flash-Lite input is currently $0.30 per million tokens. A 10-second recording is about 320 audio tokens (~$0.000096); a 25-token transcript is about $0.0000075. Output pricing is the same in either mode.").font(.caption)
                Text("Current mode: \(settings.voiceInputMode.title)").font(.caption.bold()).foregroundStyle(Color.cyan)
            }.padding()
        }.navigationTitle("Usage")
    }
}

private struct SetupHelpView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 11) {
                Text("Quick setup").font(.headline)
                help("1", "Choose Gemini Flash-Lite", "It is the fast default for short voice replies.")
                help("2", "Add your Gemini API key", "Settings → Gemini → Add Gemini key. The key is saved only in Keychain.")
                help("3", "Talk", "Tap the mic once, speak, then tap the arrow to send. Cancel discards the recording. Questions send automatically at 60 seconds.")
                help("4", "Listen", "Read the answer and tap Ask for another question. Turn off Read aloud for text-only replies. Swipe right or tap the faint left-edge cue for Settings.")
            }.padding()
        }.navigationTitle("Setup")
    }
    private func help(_ number: String, _ title: String, _ copy: String) -> some View {
        HStack(alignment: .top, spacing: 8) { Text(number).font(.caption.bold()).frame(width: 20, height: 20).background(Color.cyan, in: Circle()); VStack(alignment: .leading) { Text(title).font(.caption.bold()); Text(copy).font(.caption2).foregroundStyle(Color.secondary) } }
    }
}

private struct APIKeyEditorView: View {
    @EnvironmentObject private var settings: AppSettings
    let provider: AIProvider
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "key.fill").font(.title2).foregroundStyle(Color.cyan)
                Text(provider.displayName).font(.headline)
                SecureField(provider.apiKeyPlaceholder, text: $apiKey).textInputAutocapitalization(.never)
                Button("Save") { settings.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider); dismiss() }.buttonStyle(.borderedProminent).tint(Color.cyan)
                if settings.hasAPIKey(for: provider) { Button("Remove Key", role: .destructive) { settings.setAPIKey("", for: provider); dismiss() }.font(.caption) }
            }.padding().onAppear { apiKey = settings.apiKey(for: provider) }.navigationTitle("API Key").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

private struct GatewayEditorView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var url = ""
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath").font(.title2).foregroundStyle(Color.cyan)
                Text("Fallback endpoint").font(.headline)
                TextField("https://example.com/v1/chat/completions", text: $url).textInputAutocapitalization(.never)
                Button("Save") { settings.gatewayURL = url.trimmingCharacters(in: .whitespacesAndNewlines); dismiss() }.buttonStyle(.borderedProminent).tint(Color.cyan)
            }.padding().onAppear { url = settings.gatewayURL }.navigationTitle("Fallback").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}
