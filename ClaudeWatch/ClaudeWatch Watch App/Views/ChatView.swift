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
    @State private var pendingQuery: String?
    @State private var retryAudio: Data?
    @State private var requestTask: Task<Void, Never>?
    @State private var requestID: UUID?
    private let apiService = ChatAPIService()

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
                if showsVoiceStage { voiceStage } else { conversation }
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
                guard value.translation.width > 50,
                      abs(value.translation.width) > abs(value.translation.height) * 2 else { return }
                openSettings()
            }
        )
        .sheet(isPresented: $showSettings) { SettingsView() }
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
    }

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
                } else if errorMessage == nil {
                    Text("Swipe right for settings")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 8) {
                    if let last = messages.last {
                        Button {
                            if speech.isSpeaking { speech.stop() }
                            else { speech.speak(AnswerFormatting.plainText(last.content)) }
                        } label: {
                            Image(systemName: speech.isSpeaking ? "stop.fill" : "speaker.wave.2.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(speech.isSpeaking ? Color.cyan : Color.secondary)
                        .accessibilityLabel(speech.isSpeaking ? "Stop reading" : "Read answer aloud")
                    }
                    Button(action: handleOrbTap) {
                        Label("Ask", systemImage: "mic.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.cyan.opacity(0.18), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.cyan)
                    .accessibilityLabel("Ask a new question")
                    .accessibilityHint("Starts recording immediately")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 2)
                .background(.ultraThinMaterial)
            }
        }
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
        let transcriptionKey = settings.apiKey(for: .google)
        let gatewayURL = settings.gatewayURL
        requestTask = Task { @MainActor in
            do {
                let response: String
                if inputMode == .text {
                    let query = try await apiService.transcribeAudio(audioData: audioData, model: .geminiFlashLite, apiKey: transcriptionKey)
                    try Task.checkCancellation()
                    guard requestID == id else { return }
                    pendingQuery = query
                    response = try await apiService.sendMessage(messages: [Message(role: .user, content: query)], model: model, connectionMode: .bringYourOwnKey, apiKey: key, gatewayURL: gatewayURL)
                } else {
                    response = try await apiService.sendAudioMessage(audioData: audioData, model: model, apiKey: key)
                }
                try Task.checkCancellation()
                guard requestID == id else { return }
                messages.append(Message(role: .assistant, content: response, model: model.displayName))
                retryAudio = nil
                WKInterfaceDevice.current().play(.success)
                if settings.readAloud, !showSettings, scenePhase == .active {
                    speech.speak(AnswerFormatting.plainText(response))
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
        preparationID = nil
        timer?.invalidate()
        timer = nil
        recorder?.stop()
        recorder = nil
        if let recordingURL { try? FileManager.default.removeItem(at: recordingURL) }
        recordingURL = nil
        isPreparing = false
        isRecording = false
        AudioSessionController.deactivate()
    }

    private func fail(_ message: String) {
        cancel()
        errorMessage = message
    }

    private func startRecorder(id: UUID) {
        guard preparationID == id else { return }
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .spokenAudio)
            AudioSessionController.activate { [weak self] activated in
                guard let self, self.preparationID == id else {
                    if activated { AudioSessionController.deactivate() }
                    return
                }
                guard activated else {
                    self.fail("Couldn’t start the microphone. Please try again.")
                    return
                }
                self.createRecorder(id: id)
            }
        } catch { fail("Couldn’t start the microphone: \(error.localizedDescription)") }
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

@MainActor
private enum AudioSessionController {
    static func activate(completion: @escaping (Bool) -> Void) {
        AVAudioSession.sharedInstance().activate(options: []) { activated, _ in
            Task { @MainActor in completion(activated) }
        }
    }

    static func deactivate() {
        AVAudioSession.sharedInstance().deactivate(options: .notifyOthersOnDeactivation) { _, _ in }
    }
}

@MainActor
private final class SpeechOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    private var currentUtterance: AVSpeechUtterance?
    private var activationID: UUID?

    override init() {
        super.init()
        synthesizer.delegate = self
    }
    func speak(_ text: String) {
        stop()
        guard !text.isEmpty else { return }
        let activationID = UUID()
        self.activationID = activationID
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .spokenAudio)
        } catch {
            self.activationID = nil
            return
        }
        AudioSessionController.activate { [weak self] activated in
            guard let self, self.activationID == activationID else {
                if activated { AudioSessionController.deactivate() }
                return
            }
            guard activated else {
                self.activationID = nil
                return
            }
            self.startSpeaking(text)
        }
    }

    private func startSpeaking(_ text: String) {
        guard activationID != nil else { return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: Locale.current.identifier)
        utterance.rate = 0.48
        currentUtterance = utterance
        isSpeaking = true
        synthesizer.speak(utterance)
    }
    func stop() {
        activationID = nil
        currentUtterance = nil
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        if isSpeaking { AudioSessionController.deactivate() }
        isSpeaking = false
    }
    private func finished(_ utterance: AVSpeechUtterance) {
        guard currentUtterance === utterance else { return }
        currentUtterance = nil
        isSpeaking = false
        AudioSessionController.deactivate()
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in finished(utterance) }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in finished(utterance) }
    }
}

struct ModelPickerView: View {
    @EnvironmentObject private var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    private var models: [AIModel] { AIModel.allCases.filter { !$0.isFreeCloudModel && settings.hasAPIKey(for: $0.provider) } }
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
