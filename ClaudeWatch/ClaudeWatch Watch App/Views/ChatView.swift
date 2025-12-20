import SwiftUI

struct ChatView: View {
    @EnvironmentObject var settings: AppSettings
    @StateObject private var speechService = SpeechRecognitionService()
    
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showModelPicker = false
    
    private let apiService = ClaudeAPIService()
    
    var body: some View {
        VStack(spacing: 0) {
            // Messages list
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(messages) { message in
                            MessageBubble(message: message)
                                .id(message.id)
                        }
                        
                        if isLoading {
                            HStack {
                                ProgressView()
                                    .tint(.purple)
                                Text("Thinking...")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.top, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    if let lastMessage = messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }
            
            Divider()
            
            // Input area
            VStack(spacing: 8) {
                // Speech-to-text display
                if speechService.isRecording || !speechService.transcribedText.isEmpty {
                    Text(speechService.transcribedText.isEmpty ? "Listening..." : speechService.transcribedText)
                        .font(.caption)
                        .foregroundStyle(speechService.isRecording ? .purple : .primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineLimit(2)
                }
                
                HStack(spacing: 8) {
                    // Mic button
                    Button {
                        speechService.toggleRecording()
                        if !speechService.isRecording && !speechService.transcribedText.isEmpty {
                            inputText = speechService.transcribedText
                        }
                    } label: {
                        Image(systemName: speechService.isRecording ? "mic.fill" : "mic")
                            .font(.title3)
                            .foregroundStyle(speechService.isRecording ? .red : .purple)
                    }
                    .buttonStyle(.plain)
                    
                    // Model indicator (tap to change)
                    Button {
                        showModelPicker = true
                    } label: {
                        Text(settings.selectedModel.shortName)
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.purple.opacity(0.2))
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    
                    Spacer()
                    
                    // Send button
                    Button {
                        let textToSend = inputText.isEmpty ? speechService.transcribedText : inputText
                        if !textToSend.isEmpty {
                            sendMessage(textToSend)
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.purple)
                    }
                    .buttonStyle(.plain)
                    .disabled(inputText.isEmpty && speechService.transcribedText.isEmpty || isLoading)
                    
                    // Settings
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .navigationTitle("Claude")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showModelPicker) {
            ModelPickerView(selectedModel: $settings.selectedModel)
        }
        .alert("Error", isPresented: .init(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }
    
    private func sendMessage(_ text: String) {
        let userMessage = Message(role: .user, content: text)
        messages.append(userMessage)
        
        // Clear inputs
        inputText = ""
        speechService.transcribedText = ""
        
        isLoading = true
        
        Task {
            do {
                let response = try await apiService.sendMessage(
                    messages: messages,
                    model: settings.selectedModel,
                    apiKey: settings.apiKey
                )
                
                let assistantMessage = Message(
                    role: .assistant,
                    content: response,
                    model: settings.selectedModel.displayName
                )
                messages.append(assistantMessage)
                
            } catch {
                errorMessage = error.localizedDescription
            }
            
            isLoading = false
        }
    }
}

struct ModelPickerView: View {
    @Binding var selectedModel: ClaudeModel
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        List {
            ForEach(ClaudeModel.allCases) { model in
                Button {
                    selectedModel = model
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: model.icon)
                            .foregroundStyle(.purple)
                        Text(model.displayName)
                        Spacer()
                        if model == selectedModel {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.purple)
                        }
                    }
                }
            }
        }
        .navigationTitle("Model")
    }
}

#Preview {
    NavigationStack {
        ChatView()
            .environmentObject(AppSettings())
    }
}
