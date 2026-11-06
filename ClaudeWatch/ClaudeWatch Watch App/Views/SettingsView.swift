import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    @State private var showAPIKeyEditor = false
    @State private var tempAPIKey = ""
    @State private var showTodoistTokenEditor = false
    @State private var tempTodoistToken = ""

    private var voiceSummary: String {
        VoiceCatalog.options().first { $0.id == settings.voiceSlot }?.label ?? "Female 1"
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Read Aloud") {
                    Toggle(isOn: $settings.autoSpeak) {
                        Label("Auto-speak", systemImage: "speaker.wave.2.fill")
                    }

                    NavigationLink {
                        VoicePickerView()
                    } label: {
                        HStack {
                            Label("Voice", systemImage: "person.wave.2.fill")
                            Spacer()
                            Text(voiceSummary).foregroundStyle(.secondary)
                        }
                    }

                    Picker(selection: $settings.speechSpeed) {
                        ForEach(SpeechSpeed.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Speed", systemImage: "gauge.with.dots.needle.33percent")
                    }
                }

                Section("AI") {
                    NavigationLink {
                        ProviderListView(onFinished: { dismiss() })
                    } label: {
                        HStack {
                            Label("Provider", systemImage: settings.provider.icon)
                            Spacer()
                            Text(settings.provider.shortName).foregroundStyle(.secondary)
                        }
                    }

                    NavigationLink {
                        ModelPickerView(provider: settings.provider, onFinished: { dismiss() })
                    } label: {
                        HStack {
                            Label("Model", systemImage: settings.model?.icon ?? "sparkles")
                            Spacer()
                            Text(settings.model?.shortName ?? "None")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Picker(selection: $settings.responseLength) {
                        ForEach(ResponseLength.allCases) { Text($0.label).tag($0) }
                    } label: {
                        Label("Length", systemImage: "text.alignleft")
                    }
                }

                Section("Todoist day briefing") {
                    Toggle(isOn: $settings.todoistBriefingEnabled) {
                        Label("Enable day briefing", systemImage: "checklist")
                    }
                    .disabled(!settings.hasTodoistToken)

                    Text(settings.hasTodoistToken
                         ? "Gemini can read today's and overdue tasks. It reports workload signals only; it does not schedule or change tasks."
                         : "Add a separate Todoist read credential to enable this Gemini-only feature.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    Button {
                        tempTodoistToken = ""
                        showTodoistTokenEditor = true
                    } label: {
                        Label(settings.hasTodoistToken ? "Replace Todoist account" : "Connect Todoist read account",
                              systemImage: "person.crop.circle.badge.plus")
                    }

                    if settings.hasTodoistToken {
                        Button(role: .destructive) {
                            settings.removeTodoistReadToken()
                        } label: {
                            Label("Remove Todoist account", systemImage: "person.crop.circle.badge.minus")
                        }
                    }

                    Text("Use a separately provisioned token with Todoist's narrowest available data:read scope. A broad token may still authorize writes on Todoist, but ClaudeWatch exposes GET-only reads and never reuses TodoistToday credentials.")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Section("Feedback") {
                    Toggle(isOn: $settings.hapticsEnabled) {
                        Label("Haptics", systemImage: "hand.tap.fill")
                    }
                }

                Section("\(settings.provider.shortName) key") {
                    Button {
                        tempAPIKey = settings.apiKey
                        showAPIKeyEditor = true
                    } label: {
                        HStack {
                            Label(settings.apiKey.isEmpty ? "Not set" : "••••••••", systemImage: "key.fill")
                                .foregroundStyle(settings.apiKey.isEmpty ? .red : .primary)
                            Spacer()
                            Image(systemName: "pencil").foregroundStyle(.secondary)
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.2.0").foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showAPIKeyEditor) {
                APIKeyEditorView(provider: settings.provider, apiKey: $tempAPIKey) {
                    settings.setKey(tempAPIKey, for: settings.provider)
                    showAPIKeyEditor = false
                }
            }
            .sheet(isPresented: $showTodoistTokenEditor) {
                TodoistTokenEditorView(token: $tempTodoistToken) {
                    settings.setTodoistReadToken(tempTodoistToken)
                    showTodoistTokenEditor = false
                }
            }
        }
    }
}

// MARK: - Voice picker

struct VoicePickerView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var speech: SpeechSynthesisService

    private let options = VoiceCatalog.options()

    var body: some View {
        List {
            ForEach(options) { option in
                Button {
                    settings.voiceSlot = option.id
                    speech.preview(voice: option.voice, settings: settings)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.label)
                            Text("\(option.voiceName) · \(option.detail)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if option.id == settings.voiceSlot {
                            Image(systemName: "checkmark").foregroundStyle(.purple)
                        }
                    }
                }
            }

            if options.count <= 1 {
                Text("Only one voice is installed on this watch.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Voice")
        .onDisappear { speech.stop() }
    }
}

// MARK: - API key

struct APIKeyEditorView: View {
    let provider: Provider
    @Binding var apiKey: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Enter your \(provider.displayName) API key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    TextField(provider.keyPlaceholder, text: $apiKey)
                        .textContentType(.password)

                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct TodoistTokenEditorView: View {
    @Binding var token: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 10) {
                    Text("Separate Todoist read credential")
                        .font(.footnote.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("Create or provision this credential for ClaudeWatch only. Prefer Todoist's data:read scope. Client-side read-only behavior cannot narrow a broad token's server permissions.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    SecureField("Todoist token", text: $token)
                        .textContentType(.password)

                    Button("Save", action: onSave)
                        .buttonStyle(.borderedProminent)
                        .tint(.purple)
                        .disabled(token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.horizontal, 4)
            }
            .navigationTitle("Todoist")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .environmentObject(SpeechSynthesisService())
}
