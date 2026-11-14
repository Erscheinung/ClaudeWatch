import AVFoundation
import SwiftUI
import WatchKit

struct ChatView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var speech = SpeechOutput()
    @StateObject private var recorder = VoiceRecorder()
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var showModelPicker = false
    @State private var pendingQuery: String?
    @State private var retryAudio: Data?
    @State private var requestTask: Task<Void, Never>?
    @State private var requestID: UUID?
    #if DEBUG
    @State private var didApplyUIDemo = false
    #endif
    private let apiService = ChatAPIService()
    private let briefingService = DayBriefingService()
    /// The last answer was a day briefing, so a short follow-up needs less evidence to stay on the day.
    @State private var lastAnswerWasDay = false

    private var state: OrbState {
        if recorder.isPreparing { return .preparing }
        if recorder.isRecording { return .listening }
        if isLoading { return .thinking }
        return .ready
    }
    private var showsVoiceStage: Bool { messages.isEmpty || state != .ready }

    var body: some View {
        ZStack(alignment: .leading) {
            LinearGradient(colors: [Color(red: 0.035, green: 0.055, blue: 0.15), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            VStack(spacing: 0) {
                if showsVoiceStage { voiceStage } else {
                    conversation
                        .ignoresSafeArea(.container, edges: .bottom)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            Button(action: openSettings) {
                HStack(spacing: 2) {
                    Capsule().frame(width: 2, height: 20)
                    Image(systemName: "chevron.right").font(.system(size: 7, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: 24, height: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Settings")
            .accessibilityHint("Tap or swipe right to open settings")
        }
        .contentShape(Rectangle())
        .simultaneousGesture(
            DragGesture(minimumDistance: 25).onEnded { value in
                guard abs(value.translation.width) > 50,
                      abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                if value.translation.width > 0 { openSettings() }
                else { startNewChat() }
            }
        )
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showModelPicker) { ModelPickerView() }
        .onChange(of: settings.readAloud) { _, enabled in
            if !enabled { speech.stop() }
        }
        .onChange(of: recorder.errorMessage) { _, message in
            if let message { errorMessage = message; WKInterfaceDevice.current().play(.failure) }
        }
        .onChange(of: recorder.isRecording) { _, recording in
            if recording { WKInterfaceDevice.current().play(.start) }
        }
        .onChange(of: recorder.reachedLimit) { _, reached in
            if reached { finishAndSend() }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { cancelActivity() }
        }
        .onDisappear { cancelActivity() }
        #if DEBUG
        .onAppear { applyUIDemoIfRequested() }
        #endif
    }

    #if DEBUG
    private func applyUIDemoIfRequested() {
        guard !didApplyUIDemo else { return }
        didApplyUIDemo = true
        let arguments = ProcessInfo.processInfo.arguments
        guard arguments.contains("--ui-demo-answer") else { return }
        let sample = """
        **Sample answer for UI testing**

        This is synthetic demonstration text, not a response from an AI provider. No question was recorded or sent.

        - Scroll to read the sample at your preferred text size.
        - The controls below remain separate from the answer.
        - Tap Stop to end this sample's narration, or use the speaker to read it again.

        This extra paragraph provides enough content to check reading and scrolling on a small watch display. The sample uses the same formatting and playback controls as an ordinary answer. It does not change your saved model, voice, speed, or API keys.
        """
        messages = [Message(role: .assistant, content: sample, model: "UI demo · Sample")]
        if arguments.contains("--ui-demo-speaking") {
            speech.speak(answer: sample, voiceSlot: settings.voiceSlot, speed: settings.speechSpeed)
        }
    }
    #endif

    private var voiceStage: some View {
        GeometryReader { geometry in
            let orbSize = min(110.0, max(64.0, geometry.size.height - 112))
            ScrollView {
            VStack(spacing: 5) {
                Text(state.title)
                    .font(.headline)
                    .accessibilityAddTraits(.updatesFrequently)
                Button(action: handleOrbTap) {
                    VoiceOrb(state: state)
                        .scaleEffect(orbSize / 110)
                        .frame(width: 112, height: orbSize)
                }
                .buttonStyle(.plain)
                .disabled(state == .preparing || state == .thinking)
                .accessibilityLabel(state == .listening ? "Send recording" : "Start recording")
                .accessibilityHint(state == .listening ? "Ends recording and sends your question" : "Tap once, then speak")
                Text(state == .listening ? "Tap to send · \(recorder.elapsed)s" : state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                if state != .ready {
                    Button("Cancel", action: cancelActivity)
                        .font(.caption)
                        .buttonStyle(.plain)
                        .frame(minHeight: 44)
                } else {
                    modelChip
                        .padding(.horizontal, -12)
                    if errorMessage == nil {
                        Text("Swipe right for settings")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
                if let pendingQuery {
                    Text(pendingQuery).font(.caption).foregroundStyle(.secondary)
                }
                errorCard
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24)
            .padding(.vertical, 4)
            }
        }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            // Reserve the footer's actual height instead of stacking a bottom
            // safe-area inset above watchOS's already generous bottom margin.
            VStack(spacing: 0) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        ForEach(messages) { message in
                            VStack(alignment: .leading, spacing: 7) {
                                Text(message.model ?? "Answer")
                                    .font(.caption2).foregroundStyle(.secondary)
                                AnswerText(content: message.content)
                            }
                            .id(message.id)
                            if message.id != messages.last?.id { Divider() }
                        }
                        errorCard
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .onAppear {
                    if let last = messages.last { proxy.scrollTo(last.id, anchor: .top) }
                }
                conversationControls
            }
        }
    }

    private var modelChip: some View {
        Button {
            cancelActivity()
            showModelPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: settings.preferredModel?.icon ?? "key.fill")
                    .foregroundStyle(.cyan)
                Text(settings.preferredModel?.displayName ?? "Choose a model")
                    .font(.caption2.weight(.medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(settings.preferredModel == nil ? "Add a key in Settings" : "Key saved")
        .accessibilityHint("Opens the model picker")
    }

    private var conversationControls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                newChatButton
                playbackButton
                askButton
            }
            VStack(spacing: 4) {
                HStack(spacing: 4) {
                    newChatButton
                    playbackButton
                }
                askButton
            }
        }
        // Reserve the controls' actual height, including the compact two-row
        // layout on narrow displays or at larger Dynamic Type sizes.
        .padding(.horizontal, 12)
        .padding(.top, 2)
        .padding(.bottom, 8)
        .background(.ultraThinMaterial)
    }

    private var newChatButton: some View {
        Button(action: startNewChat) {
            Image(systemName: "square.and.pencil")
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.cyan)
        .accessibilityLabel("New chat")
        .accessibilityHint("Clears answers and returns to the microphone. You can also swipe left.")
    }

    @ViewBuilder private var playbackButton: some View {
        if let last = messages.last {
            Button {
                if speech.isSpeaking { speech.stop() }
                else { speech.speak(answer: last.content, voiceSlot: settings.voiceSlot, speed: settings.speechSpeed) }
            } label: {
                Group {
                    if speech.isSpeaking {
                        Text("Stop")
                            .font(.caption.weight(.semibold))
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, 10)
                    } else {
                        Image(systemName: "speaker.wave.2.fill")
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .background(speech.isSpeaking ? Color.cyan : Color.clear, in: Capsule())
                .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .foregroundStyle(speech.isSpeaking ? Color.black : Color.secondary)
            .accessibilityLabel(speech.isSpeaking ? "Stop reading" : "Read answer aloud")
        }
    }

    private var askButton: some View {
        Button(action: handleOrbTap) {
            Text("Ask")
                .font(.caption.weight(.semibold))
                .fixedSize(horizontal: true, vertical: false)
                .padding(.horizontal, 8)
                .frame(minWidth: 44, maxWidth: .infinity, minHeight: 44)
                .background(Color.cyan.opacity(0.18), in: Capsule())
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.cyan)
        .accessibilityLabel("Ask a new question")
        .accessibilityHint("Starts recording immediately")
    }

    @ViewBuilder private var errorCard: some View {
        if let errorMessage {
            VStack(alignment: .leading, spacing: 6) {
                Label("Something went wrong", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.semibold))
                Text(errorMessage).font(.caption2).foregroundStyle(.secondary)
                if let retryAudio {
                    Button("Retry question") { send(retryAudio) }
                        .font(.caption).frame(minHeight: 44)
                }
                Button("Dismiss") { self.errorMessage = nil; retryAudio = nil }
                    .font(.caption).frame(minHeight: 44)
            }
            .padding(10)
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func startNewChat() {
        cancelActivity()
        messages.removeAll()
        WKInterfaceDevice.current().play(.click)
    }

    private func openSettings() {
        cancelActivity()
        showSettings = true
    }

    private func cancelActivity() {
        requestID = nil
        requestTask?.cancel()
        requestTask = nil
        recorder.cancel()
        speech.stop()
        isLoading = false
        pendingQuery = nil
        retryAudio = nil
        errorMessage = nil
    }

    private func handleOrbTap() {
        guard !isLoading, !recorder.isPreparing else { return }
        if recorder.isRecording { finishAndSend(); return }
        speech.stop()
        errorMessage = nil
        retryAudio = nil
        pendingQuery = nil
        guard let model = settings.preferredModel else {
            errorMessage = "Add an API key in Settings."
            return
        }
        guard settings.voiceInputMode != .audio || model.provider == .google else {
            errorMessage = "Choose Text in Settings → Voice to use this model."
            return
        }
        guard settings.voiceInputMode != .text || settings.hasAPIKey(for: .google) else {
            errorMessage = "Add a Gemini key in Settings to transcribe your question."
            return
        }
        recorder.beginRecording()
    }

    private func finishAndSend() {
        guard let audio = recorder.finishRecording() else { return }
        WKInterfaceDevice.current().play(.stop)
        send(audio)
    }

    private func send(_ audioData: Data) {
        guard !audioData.isEmpty, !isLoading, let model = settings.preferredModel else { return }
        errorMessage = nil
        retryAudio = audioData
        isLoading = true
        let id = UUID()
        requestID = id
        let key = settings.apiKey(for: model.provider)
        let inputMode = settings.voiceInputMode
        let replyLength = settings.replyLength
        let transcriptionKey = settings.apiKey(for: .google)
        let gatewayURL = settings.gatewayURL
        // Day briefing is opt-in and Gemini-only. When it is off, the request path below is unchanged.
        let briefingAvailable = settings.canUseDayBriefing
        let todoistToken = briefingAvailable ? settings.todoistReadToken : ""
        let weekDigest = briefingAvailable ? settings.weekDigestConfig : nil
        let timeZone = TimeZone.current
        requestTask = Task { @MainActor in
            do {
                let response: String
                var query: String?
                if inputMode == .text || briefingAvailable {
                    let transcript = try await apiService.transcribeAudio(audioData: audioData, model: .geminiFlashLite, apiKey: transcriptionKey)
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    query = transcript
                }
                var isDay = false
                if briefingAvailable, let query, DayIntent.matches(query, followUp: lastAnswerWasDay) {
                    pendingQuery = query
                    isDay = true
                    // One ordinary chat call with a compact Todoist digest in the prompt (no tool loop).
                    response = try await briefingService.run(question: query, todoistToken: todoistToken, timeZone: timeZone, weekDigestConfig: weekDigest) { prompt in
                        try await apiService.sendMessage(messages: [Message(role: .user, content: prompt)], model: model, connectionMode: .bringYourOwnKey, apiKey: key, gatewayURL: gatewayURL, replyLength: replyLength)
                    }
                } else if inputMode == .text, let query {
                    pendingQuery = query
                    response = try await apiService.sendMessage(messages: [Message(role: .user, content: query)], model: model, connectionMode: .bringYourOwnKey, apiKey: key, gatewayURL: gatewayURL, replyLength: replyLength)
                } else {
                    response = try await apiService.sendAudioMessage(audioData: audioData, model: model, apiKey: key, replyLength: replyLength)
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                lastAnswerWasDay = isDay
                messages.append(Message(role: .assistant, content: response, model: model.displayName))
                retryAudio = nil
                WKInterfaceDevice.current().play(.success)
                if settings.readAloud, !showSettings, scenePhase == .active {
                    speech.speak(answer: response, voiceSlot: settings.voiceSlot, speed: settings.speechSpeed)
                }
            } catch {
                guard requestID == id, !Task.isCancelled else { return }
                errorMessage = error.localizedDescription
                WKInterfaceDevice.current().play(.failure)
            }
            guard requestID == id else { return }
            pendingQuery = nil
            isLoading = false
            requestTask = nil
            requestID = nil
        }
    }
}

private enum OrbState {
    case ready, preparing, listening, thinking
    var title: String {
        switch self {
        case .ready: return "Ask anything"
        case .preparing: return "Opening mic…"
        case .listening: return "Listening"
        case .thinking: return "Thinking…"
        }
    }
    var detail: String {
        switch self {
        case .ready: return "Tap to speak"
        case .preparing: return "One moment"
        case .listening: return "Tap to send"
        case .thinking: return "Finding your answer"
        }
    }
    var color: Color { self == .thinking ? .purple : .cyan }
    var symbol: String {
        switch self {
        case .ready: return "mic.fill"
        case .preparing: return "mic"
        case .listening: return "arrow.up"
        case .thinking: return "sparkles"
        }
    }
}

private struct VoiceOrb: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let state: OrbState

    private var animate: Bool {
        !reduceMotion && !isLuminanceReduced && (state == .listening || state == .thinking || state == .preparing)
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animate)) { context in
            let time = animate ? context.date.timeIntervalSinceReferenceDate : 0
            let angle = time * (state == .listening ? 2.6 : 1.4)
            let pulse = animate ? 1 + 0.045 * sin(time * 3) : 1
            ZStack {
                Circle().fill(state.color.opacity(0.10))
                    .frame(width: 96, height: 96).scaleEffect(pulse)
                Circle()
                    .fill(LinearGradient(colors: [state.color.opacity(0.9), .blue.opacity(0.7), .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 70, height: 70)
                    .overlay(Circle().stroke(.white.opacity(0.22), lineWidth: 0.5))
                    .shadow(color: state.color.opacity(0.3), radius: 10)
                    .scaleEffect(pulse)
                if state == .listening {
                    ForEach(0..<2) { index in
                        let rotation = Double(index) * 65 - 30
                        ZStack {
                            Ellipse().stroke(.cyan.opacity(0.32), lineWidth: 1)
                            Circle().fill(.white).frame(width: 5, height: 5)
                                .shadow(color: .cyan, radius: 4)
                                .offset(x: 49 * cos(angle + Double(index) * .pi), y: 24 * sin(angle + Double(index) * .pi))
                        }
                        .frame(width: 98, height: 48)
                        .rotationEffect(.degrees(rotation))
                    }
                } else if state == .thinking || state == .preparing {
                    Circle().trim(from: 0.05, to: 0.72)
                        .stroke(AngularGradient(colors: [state.color.opacity(0.1), .white], center: .center), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                        .frame(width: 90, height: 90)
                        .rotationEffect(.radians(angle))
                }
                Image(systemName: state.symbol)
                    .font(.system(size: 25, weight: .semibold))
                    .foregroundStyle(.white)
            }
            .frame(width: 112, height: 110)
        }
        .accessibilityHidden(true)
    }
}

@MainActor
private final class VoiceRecorder: NSObject, ObservableObject, AVAudioRecorderDelegate {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var elapsed = 0
    @Published private(set) var reachedLimit = false
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var preparationID: UUID?
    private var timer: Timer?

    func beginRecording() {
        guard !isPreparing, !isRecording else { return }
        errorMessage = nil
        elapsed = 0
        reachedLimit = false
        let id = UUID()
        preparationID = id
        isPreparing = true
        switch AVAudioApplication.shared.recordPermission {
        case .granted: startRecorder(id: id)
        case .denied: fail("Microphone access is off. Enable it for Claude Watch in Settings.")
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard let self, self.preparationID == id else { return }
                    if granted { self.startRecorder(id: id) }
                    else { self.fail("Microphone access is required for voice questions.") }
                }
            }
        @unknown default: fail("Microphone permission is unavailable.")
        }
    }

    func finishRecording() -> Data? {
        guard let recorder, let url = recordingURL else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        let data = try? Data(contentsOf: url)
        cancel()
        guard duration >= 0.4 else {
            errorMessage = "Tap the mic, speak your question, then tap the arrow to send."
            return nil
        }
        guard let data, !data.isEmpty else {
            errorMessage = "Couldn’t save the recording. Please try again."
            return nil
        }
        return data
    }

    func cancel() {
        let sessionID = preparationID
        preparationID = nil
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        isPreparing = false
        isRecording = false
        if let sessionID { AudioSessionController.release(sessionID) }
    }

    private func fail(_ message: String) {
        cancel()
        errorMessage = message
    }

    private func startRecorder(id: UUID) {
        guard preparationID == id else { return }
        AudioSessionController.activate(id: id, category: .playAndRecord) { [weak self] activated in
            guard let self, self.preparationID == id else { return }
            guard activated else {
                self.fail("Couldn’t start the microphone. Please try again.")
                return
            }
            self.createRecorder(id: id)
        }
    }

    private func createRecorder(id: UUID) {
        guard preparationID == id else { return }
        do {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("voice-\(UUID().uuidString).wav")
            recordingURL = url
            let recorder = try AVAudioRecorder(url: url, settings: [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVSampleRateKey: 16_000,
                AVNumberOfChannelsKey: 1,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsBigEndianKey: false
            ])
            self.recorder = recorder
            recorder.delegate = self
            guard recorder.prepareToRecord(), recorder.record() else {
                fail("Couldn’t start the microphone. Please try again.")
                return
            }
            isPreparing = false
            isRecording = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isRecording else { return }
                    self.elapsed = Int(self.recorder?.currentTime ?? 0)
                    if self.elapsed >= 60 { self.reachedLimit = true }
                }
            }
        } catch { fail("Couldn’t start the microphone: \(error.localizedDescription)") }
    }

    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            guard self.recorder === recorder else { return }
            fail("Recording was interrupted. Please try again.")
        }
    }

    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        Task { @MainActor in
            guard self.recorder === recorder, isRecording else { return }
            fail("Recording stopped. Please try your question again.")
        }
    }
}

// One owner and an ordered operation chain prevent a cancelled activation from
// releasing a newer recording/playback session. The main actor only owns state;
// synchronous audio-service work runs on a dedicated queue.
@MainActor
enum AudioSessionController {
    private static let queue = DispatchQueue(label: "ClaudeWatch.audio-session", qos: .userInitiated)
    private static var owner: UUID?
    private static var isActive = false
    private static var pendingOperation: Task<Void, Never>?

    private static func enqueue(_ operation: @escaping @MainActor () async -> Void) {
        let previous = pendingOperation
        pendingOperation = Task {
            await previous?.value
            await operation()
        }
    }

    static func activate(id: UUID, category: AVAudioSession.Category,
                         completion: @escaping @MainActor (Bool) -> Void) {
        owner = id
        enqueue {
            guard owner == id else { completion(false); return }
            await deactivateIfNeeded()
            guard owner == id else { completion(false); return }
            let configured = await withCheckedContinuation { continuation in
                queue.async {
                    do {
                        try AVAudioSession.sharedInstance().setCategory(category, mode: .spokenAudio)
                        continuation.resume(returning: true)
                    } catch { continuation.resume(returning: false) }
                }
            }
            guard configured, owner == id else { completion(false); return }
            let activated = await withCheckedContinuation { continuation in
                queue.async {
                    AVAudioSession.sharedInstance().activate(options: []) { activated, _ in
                        continuation.resume(returning: activated)
                    }
                }
            }
            isActive = activated
            guard owner == id else {
                await deactivateIfNeeded()
                completion(false)
                return
            }
            completion(activated)
        }
    }

    static func release(_ id: UUID, after stopping: Task<Void, Never>? = nil) {
        guard owner == id else { return }
        owner = nil
        enqueue {
            await stopping?.value
            await deactivateIfNeeded()
        }
    }

    private static func deactivateIfNeeded() async {
        guard isActive else { return }
        let deactivated = await withCheckedContinuation { continuation in
            queue.async {
                AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { success, _ in
                    continuation.resume(returning: success)
                }
            }
        }
        if deactivated { isActive = false }
    }
}

@MainActor
final class SpeechOutput: ObservableObject {
    @Published private(set) var isSpeaking = false
    private let playback = SpeechPlayback()
    private var activationID: UUID?

    /// Reads a raw (markdown) answer in the chosen voice. Code blocks are skipped, symbols cleaned up.
    func speak(answer: String, voiceSlot: String, speed: SpeechSpeed) {
        speak(sentences: SpeechText.sentences(fromAnswer: answer), voiceSlot: voiceSlot, speed: speed)
    }

    func speak(sentences: [String], voiceSlot: String, speed: SpeechSpeed) {
        stop()
        guard !sentences.isEmpty else { return }
        let id = UUID()
        activationID = id
        // Stop is available while activation or voice preparation is pending too.
        isSpeaking = true
        AudioSessionController.activate(id: id, category: .playback) { [weak self] activated in
            guard let self, self.activationID == id else { return }
            guard activated else { self.stop(); return }
            self.playback.speak(sentences, voiceSlot: voiceSlot, rate: speed.rate, id: id) { [weak self] finishedID in
                Task { @MainActor in
                    guard let self, self.activationID == finishedID else { return }
                    self.activationID = nil
                    self.isSpeaking = false
                    AudioSessionController.release(finishedID)
                }
            }
        }
    }

    func stop() {
        guard let id = activationID else { return }
        activationID = nil
        isSpeaking = false
        let playback = playback
        let stopping = Task { await playback.stop() }
        AudioSessionController.release(id, after: stopping)
    }
}

// All synthesizer access, including first-use voice loading and its implicit
// audio-session calls, is confined to this queue rather than the UI thread.
final class SpeechPlayback: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    private let queue = DispatchQueue(label: "ClaudeWatch.speech", qos: .userInitiated)
    private var synthesizer: AVSpeechSynthesizer?
    private var pending: [AVSpeechUtterance] = []
    private var completion: (@Sendable (UUID) -> Void)?
    private var playbackID: UUID?

    /// One utterance per sentence: speech starts sooner and Stop cuts in at the next word.
    /// Voice lookup happens here, on the playback queue, never on the UI thread.
    func speak(_ sentences: [String], voiceSlot: String, rate: Float, id: UUID, completion: @escaping @Sendable (UUID) -> Void) {
        queue.async {
            if self.synthesizer == nil {
                self.synthesizer = AVSpeechSynthesizer()
                self.synthesizer?.delegate = self
            }
            let voice = VoiceCatalog.voice(forSlot: voiceSlot)
            let utterances = sentences.map { sentence -> AVSpeechUtterance in
                let utterance = AVSpeechUtterance(string: sentence)
                utterance.voice = voice
                utterance.rate = rate
                utterance.postUtteranceDelay = 0.05
                return utterance
            }
            guard !utterances.isEmpty else { completion(id); return }
            self.pending = utterances
            self.playbackID = id
            self.completion = completion
            utterances.forEach { self.synthesizer?.speak($0) }
        }
    }

    func stop() async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.pending = []
                self.playbackID = nil
                self.completion = nil
                // Also clears queued/paused speech; isSpeaking is not a reliable
                // guard while the synthesizer is preparing an utterance.
                self.synthesizer?.stopSpeaking(at: .immediate)
                continuation.resume()
            }
        }
    }

    private func finished(_ utterance: AVSpeechUtterance) {
        queue.async {
            // Ignore callbacks from a replaced/stopped playback, and only complete after the last sentence.
            guard let index = self.pending.firstIndex(where: { $0 === utterance }), let id = self.playbackID else { return }
            self.pending.remove(at: index)
            guard self.pending.isEmpty else { return }
            let completion = self.completion
            self.playbackID = nil
            self.completion = nil
            completion?(id)
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        finished(utterance)
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        finished(utterance)
    }
}

struct ModelPickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    private var models: [AIModel] { settings.availableModels.filter { !$0.isFreeCloudModel && settings.hasAPIKey(for: $0.provider) } }
    var body: some View {
        NavigationStack {
            List {
                if models.isEmpty { Text("Add an API key in Settings first.").foregroundStyle(Color.secondary) }
                ForEach(models) { model in
                    Button { settings.selectPreferredModel(model); dismiss() } label: {
                        HStack {
                            Image(systemName: model.icon).foregroundStyle(Color.cyan).frame(width: 18)
                            Text(model.displayName)
                            Spacer()
                            if model == settings.preferredModel { Image(systemName: "checkmark") }
                        }
                    }
                }
            }.navigationTitle("Model")
        }
    }
}
