import SwiftUI

/// The three-step "who do you want to talk to?" flow used at first launch and when switching in Settings:
/// provider -> API key -> model.

// MARK: - Step 1: provider

struct ProviderListView: View {
    @EnvironmentObject var settings: AppSettings
    /// Called when a model has been chosen and the provider is active.
    var onFinished: () -> Void = {}

    var body: some View {
        List {
            ForEach(Provider.allCases) { provider in
                NavigationLink {
                    KeyEntryView(provider: provider, onFinished: onFinished)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: provider.icon)
                            .foregroundStyle(.purple)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.displayName)
                            if let model = settings.model(for: provider), !settings.key(for: provider).isEmpty {
                                Text(model.shortName)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 0)
                        if provider == settings.provider && settings.isConfigured {
                            Image(systemName: "checkmark").foregroundStyle(.purple)
                        }
                    }
                }
            }
        }
        .navigationTitle("Provider")
    }
}

/// First-launch screen.
struct SetupView: View {
    var body: some View {
        NavigationStack {
            List {
                VStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30))
                        .foregroundStyle(.purple)
                    Text("Welcome")
                        .font(.headline)
                    Text("Choose the AI you want to chat with.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)

                ProviderRows()
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private struct ProviderRows: View {
        var body: some View {
            ForEach(Provider.allCases) { provider in
                NavigationLink {
                    KeyEntryView(provider: provider, onFinished: {})
                } label: {
                    Label(provider.displayName, systemImage: provider.icon)
                }
            }
        }
    }
}

// MARK: - Step 2: API key

struct KeyEntryView: View {
    @EnvironmentObject var settings: AppSettings
    let provider: Provider
    var onFinished: () -> Void

    @State private var key = ""
    @State private var goToModels = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                Text("\(provider.displayName) API key")
                    .font(.footnote.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text(provider.keyHelp)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                TextField(provider.keyPlaceholder, text: $key)
                    .textContentType(.password)

                Button {
                    settings.setKey(key, for: provider)
                    goToModels = true
                } label: {
                    Text("Continue").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .disabled(key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 4)
        }
        .navigationTitle(provider.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(isPresented: $goToModels) {
            ModelPickerView(provider: provider, onFinished: onFinished)
        }
        .onAppear { if key.isEmpty { key = settings.key(for: provider) } }
    }
}

// MARK: - Step 3: model

struct ModelPickerView: View {
    @EnvironmentObject var settings: AppSettings
    let provider: Provider
    var onFinished: () -> Void

    @State private var models: [ModelInfo]
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var customID = ""

    init(provider: Provider, onFinished: @escaping () -> Void = {}) {
        self.provider = provider
        self.onFinished = onFinished
        var initial = ModelCatalogService.cached(provider)
        if initial.isEmpty && provider == .anthropic { initial = ModelInfo.anthropicFallback }
        _models = State(initialValue: initial)
    }

    private var activeID: String? {
        settings.provider == provider ? settings.model(for: provider)?.id : nil
    }

    var body: some View {
        List {
            if isLoading {
                HStack(spacing: 6) {
                    ProgressView().tint(.purple)
                    Text("Loading models…").font(.caption2).foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            if let errorText {
                VStack(alignment: .leading, spacing: 6) {
                    Text(errorText)
                        .font(.caption2)
                        .foregroundStyle(.red)
                    Button("Try again") { Task { await load() } }
                        .font(.caption2)
                }
            }

            ForEach(models) { model in
                Button { choose(model) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.icon)
                            .foregroundStyle(.purple)
                            .frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(model.shortName)
                            Text(model.id)
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer(minLength: 0)
                        if model.id == activeID {
                            Image(systemName: "checkmark").foregroundStyle(.purple)
                        }
                    }
                }
            }

            Section("Other") {
                TextField("Model ID", text: $customID)
                    .submitLabel(.done)
                    .onSubmit { useCustomID() }
                Button("Use this ID") { useCustomID() }
                    .disabled(customID.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .navigationTitle("Model")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorText = nil
        defer { isLoading = false }
        do {
            let fetched = try await ModelCatalogService.fetch(provider: provider, apiKey: settings.key(for: provider))
            models = fetched
            ModelCatalogService.cache(fetched, for: provider)
        } catch is CancellationError {
            // view went away
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func choose(_ model: ModelInfo) {
        settings.activate(provider, model: model)
        onFinished()
    }

    private func useCustomID() {
        let id = customID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        choose(ModelInfo(id: id, name: id))
    }
}
