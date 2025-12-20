import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    @State private var showAPIKeyEditor = false
    @State private var tempAPIKey = ""
    @State private var showClearConfirm = false
    
    var body: some View {
        NavigationStack {
            List {
                // Model Selection
                Section("Model") {
                    ForEach(ClaudeModel.allCases) { model in
                        Button {
                            settings.selectedModel = model
                        } label: {
                            HStack {
                                Image(systemName: model.icon)
                                    .foregroundStyle(.purple)
                                    .frame(width: 24)
                                
                                VStack(alignment: .leading) {
                                    Text(model.displayName)
                                        .foregroundStyle(.primary)
                                }
                                
                                Spacer()
                                
                                if model == settings.selectedModel {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                    }
                }
                
                // API Key
                Section("API Key") {
                    Button {
                        tempAPIKey = settings.apiKey
                        showAPIKeyEditor = true
                    } label: {
                        HStack {
                            Image(systemName: "key")
                                .foregroundStyle(.purple)
                            Text(settings.apiKey.isEmpty ? "Not Set" : "••••••••")
                                .foregroundStyle(settings.apiKey.isEmpty ? .red : .secondary)
                            Spacer()
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                
                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }
                    
                    Link(destination: URL(string: "https://docs.anthropic.com")!) {
                        HStack {
                            Image(systemName: "book")
                                .foregroundStyle(.purple)
                            Text("API Docs")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .sheet(isPresented: $showAPIKeyEditor) {
                APIKeyEditorView(apiKey: $tempAPIKey) {
                    settings.apiKey = tempAPIKey
                    showAPIKeyEditor = false
                }
            }
        }
    }
}

struct APIKeyEditorView: View {
    @Binding var apiKey: String
    let onSave: () -> Void
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Text("Enter your Anthropic API key")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                
                TextField("sk-ant-...", text: $apiKey)
                    .textContentType(.password)
                
                Button("Save") {
                    onSave()
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
            }
            .padding()
            .navigationTitle("API Key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
}
