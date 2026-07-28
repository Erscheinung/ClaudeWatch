import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var settings: AppSettings
    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showModelPicker = false

    private let apiService = ChatAPIService()

    var body: some View {
        VStack(spacing: 0) {
            header

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 9) {
                        if messages.isEmpty {
                            promptStarters
                        }
                        ForEach(messages) { message in
                            MessageBubble(message: message).id(message.id)
                        }
                        if isLoading {
                            HStack(spacing: 6) {
                                ProgressView().tint(.cyan)
                                Text("Thinking")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 8)
                        }
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 8)
                }
                .onChange(of: messages.count) { _, _ in
                    guard let last = messages.last else { return }
                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }

            Divider()
            composer
        }
        .navigationTitle("Quick Chat")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showModelPicker) { ModelPickerView() }
        .alert("Couldn’t send", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "Unknown error")
        }
    }

    private var header: some View {
        HStack(spacing: 6) {
            Button { showModelPicker = true } label: {
                HStack(spacing: 4) {
                    Image(systemName: settings.selectedModel.icon)
                    Text(settings.selectedModel.shortName)
                        .lineLimit(1)
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.cyan)
            }
            .buttonStyle(.plain)
            Spacer()
            Image(systemName: settings.connectionMode.icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Button { showSettings = true } label: {
                Image(systemName: "gearshape.fill").font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
    }

    private var promptStarters: some View {
        VStack(spacing: 7) {
            Image(systemName: "waveform")
                .font(.title2)
                .foregroundStyle(.cyan)
            Text("Ask anything")
                .font(.caption.weight(.semibold))
            HStack(spacing: 5) {
                starter("Summarize")
                starter("Ideas")
            }
        }
        .foregroundStyle(.secondary)
        .padding(.top, 18)
    }

    private func starter(_ text: String) -> some View {
        Button(text) { inputText = text + ": " }
            .buttonStyle(.bordered)
            .tint(.cyan)
            .font(.caption2)
    }

    private var composer: some View {
        VStack(spacing: 5) {
            HStack(spacing: 10) {
                TextField("Message", text: $inputText)
                    .font(.caption)

                Button {
                    if !inputText.isEmpty { sendMessage(inputText) }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.cyan)
                }
                .buttonStyle(.plain)
                .disabled(inputText.isEmpty || isLoading)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
    }

    private func sendMessage(_ text: String) {
        messages.append(Message(role: .user, content: text))
        inputText = ""
        isLoading = true
        let model = settings.selectedModel
        let mode = settings.connectionMode
        let key = settings.apiKey(for: model.provider)
        let gatewayURL = settings.gatewayURL

        Task {
            do {
                let response = try await apiService.sendMessage(messages: messages, model: model, connectionMode: mode, apiKey: key, gatewayURL: gatewayURL)
                messages.append(Message(role: .assistant, content: response, model: model.displayName))
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct ModelPickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss

    private var models: [AIModel] {
        settings.connectionMode == .freeCloud ? AIModel.allCases.filter(\.isFreeCloudModel) : AIModel.allCases
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Picker("Connection", selection: $settings.connectionMode) {
                        ForEach(ConnectionMode.allCases) { mode in Text(mode.title).tag(mode) }
                    }
                    .onChange(of: settings.connectionMode) { _, mode in
                        if mode == .freeCloud, !settings.selectedModel.isFreeCloudModel {
                            settings.selectedModel = AIModel.defaultFreeCloudModel
                        }
                    }
                }
                ForEach(groupedModels, id: \.0) { family, choices in
                    Section(family) {
                        ForEach(choices) { model in
                            Button {
                                settings.selectedModel = model
                                dismiss()
                            } label: {
                                HStack {
                                    Image(systemName: model.icon).foregroundStyle(.cyan).frame(width: 20)
                                    Text(model.displayName).foregroundStyle(.primary)
                                    Spacer()
                                    if model == settings.selectedModel { Image(systemName: "checkmark").foregroundStyle(.cyan) }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Models")
        }
    }

    private var groupedModels: [(String, [AIModel])] {
        Dictionary(grouping: models, by: \.family).keys.sorted().map { ($0, Dictionary(grouping: models, by: \.family)[$0] ?? []) }
    }
}

#Preview {
    NavigationStack { ChatView() }.environmentObject(AppSettings())
}
