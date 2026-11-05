import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var editingProvider: AIProvider?
    @State private var showGatewayEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { ModelPickerView() } label: {
                        HStack(spacing: 8) {
                            Image(systemName: settings.preferredModel?.icon ?? "key.fill")
                                .foregroundStyle(Color.cyan)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(settings.preferredModel?.displayName ?? "Choose a model")
                                    .font(.headline)
                                Text(settings.preferredModel.map { "Key saved · \($0.provider.displayName)" } ?? "Add a provider key below")
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                Section("Read aloud") {
                    Toggle("Read answers", isOn: $settings.readAloud)
                    NavigationLink { VoicePickerView() } label: {
                        HStack { Text("Voice"); Spacer(); Text(VoiceCatalog.label(forSlot: settings.voiceSlot)).font(.caption2).foregroundStyle(.secondary) }
                    }
                    Picker("Speed", selection: $settings.speechSpeed) {
                        ForEach(SpeechSpeed.allCases) { Text($0.title).tag($0) }
                    }
                }
                Section("Replies") {
                    Picker("Output length", selection: $settings.replyLength) {
                        ForEach(ReplyLength.allCases) { length in
                            Text(length.title).tag(length)
                        }
                    }
                }
                Section("Voice") {
                    Picker("Send as", selection: $settings.voiceInputMode) {
                        ForEach(VoiceInputMode.allCases) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    Text(settings.voiceInputMode == .text ? "Gemini transcribes your recording; your selected model answers. Requires a Gemini key." : "Sends your recording directly to Gemini. Requires a Gemini model and key.")
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Section("Gemini") {
                    Button { editingProvider = .google } label: {
                        HStack { Image(systemName: "key.fill").foregroundStyle(settings.hasAPIKey(for: .google) ? Color.green : Color.orange); Text(settings.hasAPIKey(for: .google) ? "Gemini key saved" : "Add Gemini key"); Spacer(); Image(systemName: "chevron.right").font(.caption2).foregroundStyle(Color.secondary) }
                    }
                    Text("Your key stays in this watch’s Keychain.").font(.caption2).foregroundStyle(Color.secondary)
                }
                Section("Usage & billing") {
                    NavigationLink { UsageView() } label: { Label("Usage on this watch", systemImage: "chart.bar.fill") }
                }
                Section("Other providers") {
                    ForEach(AIProvider.allCases.filter { $0 != .google }) { provider in
                        Button { editingProvider = provider } label: {
                            HStack { Text(provider.displayName); Spacer(); Text(settings.hasAPIKey(for: provider) ? "Key saved" : "Add").font(.caption2).foregroundStyle(Color.secondary) }
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

/// "Female 1", "Male 1", ... Tap a voice to hear it. Voices are read on a background task because the first
/// lookup can be slow on a watch.
private struct VoicePickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var preview = SpeechOutput()
    @State private var options: [VoiceOption] = []
    @State private var loaded = false

    var body: some View {
        List {
            if !loaded { ProgressView() }
            ForEach(options) { option in
                Button {
                    settings.voiceSlot = option.id
                    preview.speak(sentences: SpeechText.previewSentences, voiceSlot: option.id, speed: settings.speechSpeed)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                            Text([option.voiceName, option.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.id == settings.voiceSlot { Image(systemName: "checkmark").foregroundStyle(Color.cyan) }
                    }
                }
                .accessibilityHint("Plays a sample of this voice")
            }
            if loaded {
                Text("Tap a voice to hear it. Apple Watch includes standard-quality voices only.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Voice")
        .task {
            options = await Task.detached(priority: .userInitiated) { VoiceCatalog.options() }.value
            loaded = true
        }
        .onDisappear { preview.stop() }
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
                help("1", "Set up on iPhone", "Open the ClaudeWatch companion on your paired iPhone. Paste your Gemini key, tap Verify, choose a model, then tap Send to Watch.")
                help("2", "Or add a key here", "Settings → Gemini → Add Gemini key. Keys are stored in Keychain. Both Audio and Text voice input require a Gemini key.")
                help("3", "Talk", "Tap the mic once, speak, then tap the arrow to send. Cancel discards the recording. Questions send automatically at 60 seconds.")
                help("4", "Reply length", "Settings → Replies → Output length offers Light, Balanced, and Heavy. Balanced is the default; the model stays the same.")
                help("5", "Listen", "Read the answer and tap Ask for another independent question. Tap the new-chat icon or swipe left to clear answers and return to the mic. Turn off Settings → Read aloud → Read answers for text-only replies. Tap Stop to end narration. Tap the model chip on the home screen to switch models. Swipe right or tap the faint left-edge cue for Settings.")
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
