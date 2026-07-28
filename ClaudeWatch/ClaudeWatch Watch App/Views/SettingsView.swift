import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    @State private var editingProvider: AIProvider?
    @State private var showGatewayEditor = false

    var body: some View {
        NavigationStack {
            List {
                Section("Connection") {
                    Picker("Mode", selection: $settings.connectionMode) {
                        ForEach(ConnectionMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .onChange(of: settings.connectionMode) { _, mode in
                        if mode == .freeCloud, !settings.selectedModel.isFreeCloudModel {
                            settings.selectedModel = AIModel.defaultFreeCloudModel
                        }
                    }

                    if settings.connectionMode == .freeCloud {
                        Button { showGatewayEditor = true } label: {
                            Label(settings.gatewayURL.isEmpty ? "Add Gateway URL" : "Gateway Connected", systemImage: settings.gatewayURL.isEmpty ? "exclamationmark.triangle" : "checkmark.icloud")
                                .foregroundStyle(settings.gatewayURL.isEmpty ? .orange : .primary)
                        }
                    }
                }

                Section("Model") {
                    NavigationLink {
                        ModelPickerView()
                    } label: {
                        HStack {
                            Image(systemName: settings.selectedModel.icon).foregroundStyle(.cyan)
                            Text(settings.selectedModel.displayName)
                            Spacer()
                            Text(settings.selectedModel.provider.displayName).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }

                if settings.connectionMode == .bringYourOwnKey {
                    Section("API Keys") {
                        ForEach(AIProvider.allCases) { provider in
                            Button { editingProvider = provider } label: {
                                HStack {
                                    Image(systemName: "key.fill").foregroundStyle(settings.hasAPIKey(for: provider) ? .green : .secondary)
                                    Text(provider.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    Text(settings.hasAPIKey(for: provider) ? "Added" : "Add")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }

                Section("About") {
                    HStack {
                        Text("Response limit")
                        Spacer()
                        Text("180 tokens").foregroundStyle(.secondary)
                    }
                    Link(destination: URL(string: "https://github.com")!) {
                        Label("Setup guide", systemImage: "book.closed")
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .sheet(item: $editingProvider) { provider in
                APIKeyEditorView(provider: provider)
            }
            .sheet(isPresented: $showGatewayEditor) {
                GatewayEditorView()
            }
        }
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
                Image(systemName: "key.fill").font(.title2).foregroundStyle(.cyan)
                Text(provider.displayName).font(.headline)
                SecureField(provider.apiKeyPlaceholder, text: $apiKey)
                Button("Save") {
                    settings.setAPIKey(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: provider)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
                Button("Remove Key", role: .destructive) {
                    settings.setAPIKey("", for: provider)
                    dismiss()
                }
                .font(.caption)
            }
            .padding()
            .onAppear { apiKey = settings.apiKey(for: provider) }
            .navigationTitle("API Key")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
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
                Image(systemName: "cloud.fill").font(.title2).foregroundStyle(.cyan)
                Text("Free Cloud Gateway").font(.headline)
                TextField("https://your-worker.workers.dev", text: $url)
                    .textInputAutocapitalization(.never)
                Button("Save") {
                    settings.gatewayURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.cyan)
            }
            .padding()
            .onAppear { url = settings.gatewayURL }
            .navigationTitle("Gateway")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
    }
}

#Preview {
    SettingsView().environmentObject(AppSettings())
}
