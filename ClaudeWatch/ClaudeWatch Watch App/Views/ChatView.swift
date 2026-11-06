import SwiftUI
import WatchKit

struct ChatView: View {
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var speech: SpeechSynthesisService

    @State private var messages: [Message] = ConversationStore.load()
    @State private var inputText = ""
    @State private var isStreaming = false
    @State private var streamTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showModelPicker = false
    @State private var activeRequestID = UUID()

    private let apiService = ChatAPIService()
    private let briefingService = GeminiDayBriefingService()
    private let bottomID = "bottom"

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    if messages.isEmpty { emptyState }

                    ForEach(visibleMessages) { message in
                        MessageBubble(
                            message: message,
                            isSpeaking: speech.speakingMessageID == message.id,
                            onToggleSpeak: message.role == .assistant ? { toggleSpeech(for: message) } : nil
                        )
                        .id(message.id)
                    }

                    if isStreaming && streamingMessageIsEmpty { thinkingRow }
                    if let errorMessage { errorRow(errorMessage) }

                    composer.id(bottomID)
                }
                .padding(.horizontal, 4)
            }
            .onChange(of: messages.last?.content.count) { _, _ in
                if isStreaming, let id = messages.last?.id { proxy.scrollTo(id, anchor: .bottom) }
            }
            .onChange(of: messages.count) { _, _ in
                withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) }
            }
            .onChange(of: isStreaming) { _, streaming in
                if !streaming { withAnimation { proxy.scrollTo(bottomID, anchor: .bottom) } }
            }
            .onAppear { proxy.scrollTo(bottomID, anchor: .bottom) }
        }
        .navigationTitle(settings.provider.shortName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showSettings = true } label: { Image(systemName: "gearshape.fill") }
                    .accessibilityLabel("Settings")
            }
        }
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showModelPicker) {
            NavigationStack {
                ModelPickerView(provider: settings.provider, onFinished: { showModelPicker = false })
            }
        }
        .onChange(of: showSettings) { _, showing in
            if showing {
                speech.stop()
                streamTask?.cancel()
            }
        }
        .onDisappear {
            speech.stop()
            streamTask?.cancel()
        }
    }

    // MARK: - Pieces

    /// The assistant placeholder stays hidden until the first characters arrive.
    private var visibleMessages: [Message] {
        guard isStreaming, streamingMessageIsEmpty else { return messages }
        return Array(messages.dropLast())
    }

    private var streamingMessageIsEmpty: Bool {
        messages.last?.role == .assistant && messages.last?.content.isEmpty == true
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 28))
                .foregroundStyle(.purple)
            Text("Ask \(settings.provider.shortName) anything")
                .font(.headline)
            Text("Tap below, then dictate.")
                .font(.caption2)
                .foregroundStyle(.secondary)

            if canUseDayBriefing {
                Button {
                    startDayBriefing("What's due today, what's overdue, and what looks overloaded?")
                } label: {
                    Label("Day briefing", systemImage: "checklist")
                }
                .font(.caption2)
                .buttonStyle(.borderedProminent)
                .tint(.purple)
                .accessibilityHint("Reads today's and overdue Todoist tasks with Gemini.")
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private var thinkingRow: some View {
        HStack(spacing: 6) {
            ProgressView().tint(.purple)
            Text("Thinking…")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 8)
        .padding(.vertical, 4)
    }

    private func errorRow(_ text: String) -> some View {
        VStack(spacing: 6) {
            Text(text)
                .font(.caption2)
                .foregroundStyle(.red)
                .multilineTextAlignment(.center)
            if lastUserText != nil {
                Button("Retry") { retry() }
                    .font(.caption2)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private var composer: some View {
        VStack(spacing: 8) {
            if isStreaming {
                Button(role: .destructive) { cancelStreaming() } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
            } else {
                // Tapping the field opens watchOS dictation / Scribble; "Done" sends.
                TextField("Ask \(settings.provider.shortName)…", text: $inputText)
                    .submitLabel(.send)
                    .onSubmit { send(inputText) }
            }

            HStack(spacing: 6) {
                Button { showModelPicker = true } label: {
                    Label(settings.model?.shortName ?? "Model", systemImage: settings.model?.icon ?? "sparkles")
                        .font(.caption2)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity)
                }
                .accessibilityLabel("Model: \(settings.model?.name ?? "none")")

                if !messages.isEmpty && !isStreaming {
                    Button { newChat() } label: {
                        Label("New", systemImage: "square.and.pencil")
                            .font(.caption2)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity)
                    }
                    .accessibilityLabel("New chat")
                }
            }
        }
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    // MARK: - Actions

    private var lastUserText: String? {
        messages.last(where: { $0.role == .user })?.content
    }

    private func toggleSpeech(for message: Message) {
        haptic(.click)
        speech.toggle(message.content, messageID: message.id, settings: settings)
    }

    private func newChat() {
        speech.stop()
        messages = []
        errorMessage = nil
        inputText = ""
        ConversationStore.save([])
        haptic(.click)
    }

    private func retry() {
        guard let text = lastUserText else { return }
        // Drop the failed turn (user message plus any partial reply) so it isn't sent twice.
        if let index = messages.lastIndex(where: { $0.role == .user }) {
            messages.removeSubrange(index...)
        }
        send(text)
    }

    private func cancelStreaming() {
        streamTask?.cancel()
    }

    private func send(_ raw: String) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isStreaming, let model = settings.model else { return }

        if shouldUseDayBriefing(for: text) {
            startDayBriefing(text)
            return
        }

        speech.stop()
        haptic(.click)
        errorMessage = nil
        inputText = ""

        messages.append(Message(role: .user, content: text))
        let reply = Message(role: .assistant, content: "", model: settings.model?.shortName)
        messages.append(reply)
        isStreaming = true
        activeRequestID = UUID()

        let history = Array(messages.dropLast())
        let provider = settings.provider
        let apiKey = settings.apiKey
        let prompt = settings.systemPrompt
        let maxTokens = settings.responseLength.maxTokens
        let speakAlong = settings.autoSpeak

        if speakAlong { speech.beginStreaming(messageID: reply.id, settings: settings) }

        let requestID = activeRequestID
        streamTask = Task {
            await receive(
                apiService.stream(messages: history, provider: provider, modelID: model.id, apiKey: apiKey,
                                  systemPrompt: prompt, maxTokens: maxTokens),
                replyID: reply.id,
                speakAlong: speakAlong,
                requestID: requestID
            )
        }
    }

    @MainActor
    private func receive(
        _ stream: AsyncThrowingStream<StreamEvent, Error>,
        replyID: UUID,
        speakAlong: Bool,
        requestID: UUID
    ) async {
        var full = ""
        var shown = ""
        var lastFlush = Date.distantPast
        var stopReason: String?
        var failure: Error?

        do {
            for try await event in stream {
                switch event {
                case .text(let delta):
                    full += delta
                    if speakAlong { speech.feed(delta) }
                    // Batch UI updates: re-rendering on every token is wasteful on a watch.
                    if Date().timeIntervalSince(lastFlush) > 0.08 {
                        update(replyID, to: full)
                        shown = full
                        lastFlush = Date()
                    }
                case .finished(let reason):
                    stopReason = reason
                }
            }
        } catch is CancellationError {
            // user tapped Stop
        } catch {
            failure = Task.isCancelled ? nil : error
        }

        guard activeRequestID == requestID else { return }
        if stopReason == "refusal" && full.isEmpty { full = "I can't help with that request." }
        if stopReason == "max_tokens" { full += " …" }
        if full != shown { update(replyID, to: full) }

        if speakAlong { speech.finishStreaming() }

        if full.isEmpty {
            messages.removeAll { $0.id == replyID }
        }
        if let failure {
            errorMessage = failure.localizedDescription
            haptic(.failure)
        } else if !full.isEmpty && !Task.isCancelled {
            haptic(.success)
        }

        isStreaming = false
        streamTask = nil
        ConversationStore.save(messages)
    }

    private var canUseDayBriefing: Bool {
        settings.todoistBriefingEnabled
            && settings.hasTodoistToken
            && settings.provider == .gemini
            && settings.model != nil
    }

    private func shouldUseDayBriefing(for text: String) -> Bool {
        guard canUseDayBriefing else { return false }
        let lower = text.lowercased()
        if lower.trimmingCharacters(in: .whitespacesAndNewlines) == "day briefing" { return true }
        let dateSignal = lower.contains("today") || lower.contains("overdue") || lower.contains("on my plate")
        let workloadSignal = lower.contains("due") || lower.contains("overloaded") || lower.contains("workload")
        return dateSignal && workloadSignal
    }

    private func startDayBriefing(_ question: String) {
        guard !isStreaming, settings.provider == .gemini, let model = settings.model,
              settings.todoistBriefingEnabled, settings.hasTodoistToken else { return }

        speech.stop()
        haptic(.click)
        errorMessage = nil
        inputText = ""
        messages.append(Message(role: .user, content: question))
        let reply = Message(role: .assistant, content: "", model: model.shortName)
        messages.append(reply)
        isStreaming = true

        let requestID = UUID()
        activeRequestID = requestID
        let apiKey = settings.apiKey
        let todoistToken = settings.todoistReadToken
        let timeZone = TimeZone.current
        let speakWhenDone = settings.autoSpeak
        streamTask = Task {
            await receiveBriefing(
                question: question,
                modelID: model.id,
                apiKey: apiKey,
                todoistToken: todoistToken,
                timeZone: timeZone,
                replyID: reply.id,
                requestID: requestID,
                speakWhenDone: speakWhenDone
            )
        }
    }

    @MainActor
    private func receiveBriefing(
        question: String,
        modelID: String,
        apiKey: String,
        todoistToken: String,
        timeZone: TimeZone,
        replyID: UUID,
        requestID: UUID,
        speakWhenDone: Bool
    ) async {
        do {
            let answer = try await briefingService.run(
                question: question,
                modelID: modelID,
                apiKey: apiKey,
                todoistToken: todoistToken,
                timeZone: timeZone
            )
            guard activeRequestID == requestID else { return }
            update(replyID, to: answer)
            if speakWhenDone { speech.toggle(answer, messageID: replyID, settings: settings) }
            haptic(.success)
        } catch is CancellationError {
            guard activeRequestID == requestID else { return }
            messages.removeAll { $0.id == replyID }
        } catch {
            guard activeRequestID == requestID else { return }
            messages.removeAll { $0.id == replyID }
            errorMessage = error.localizedDescription
            haptic(.failure)
        }
        guard activeRequestID == requestID else { return }
        isStreaming = false
        streamTask = nil
        ConversationStore.save(messages)
    }

    private func update(_ id: UUID, to text: String) {
        guard let index = messages.lastIndex(where: { $0.id == id }) else { return }
        messages[index].content = text
    }

    private func haptic(_ type: WKHapticType) {
        guard settings.hapticsEnabled else { return }
        WKInterfaceDevice.current().play(type)
    }
}

#Preview {
    NavigationStack {
        ChatView()
            .environmentObject(AppSettings())
            .environmentObject(SpeechSynthesisService())
    }
}
