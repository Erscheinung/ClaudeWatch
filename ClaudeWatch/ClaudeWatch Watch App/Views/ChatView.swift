import AVFoundation
import SwiftUI

struct ChatView: View {
    @EnvironmentObject private var settings: AppSettings
    @StateObject private var speech = SpeechOutput()
    @StateObject private var recorder = VoiceRecorder()
    @State private var messages: [Message] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showSettings = false
    @State private var orbVisible = true
    @State private var pendingQuery: String?
    @State private var requestTask: Task<Void, Never>?
    private let apiService = ChatAPIService()

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.24), .black], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
            conversation
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if orbVisible || recorder.isPreparing || recorder.isRecording || isLoading {
                VoiceOrb(state: recorder.isPreparing || recorder.isRecording ? .listening : (isLoading ? .thinking : .ready))
                    .onTapGesture { handleOrbTap() }
                    .transition(.scale(scale: 0.5).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .ignoresSafeArea(.container, edges: [.top, .bottom])
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 1.5, maximumDistance: 28)
                .onEnded { _ in
                    guard !orbVisible, !isLoading else { return }
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.68)) { orbVisible = true }
                }
        )
        .simultaneousGesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    guard value.startLocation.x < 28,
                          value.translation.width > 42,
                          abs(value.translation.height) < 36 else { return }
                    speech.stop()
                    showSettings = true
                }
        )
        .navigationBarBackButtonHidden()
        .sheet(isPresented: $showSettings) { SettingsView() }
        .alert("Couldn’t send", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK") { errorMessage = nil }
        } message: { Text(errorMessage ?? "Unknown error") }
        .onChange(of: recorder.errorMessage) { _, message in
            if let message { errorMessage = message }
        }
        .onDisappear { requestTask?.cancel() }
    }

    private var conversation: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(messages) { message in
                        ConversationMessage(message: message).id(message.id)
                    }
                    if let pendingQuery {
                        HStack {
                            Spacer(minLength: 28)
                            Text(pendingQuery)
                                .font(.caption)
                                .lineLimit(4)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .background(Color.pink.opacity(0.2), in: RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.pink.opacity(0.5)))
                        }
                    }
                }
                .padding(.horizontal, 10).padding(.top, 34).padding(.bottom, 8)
            }
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut(duration: 0.25)) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private func handleOrbTap() {
        guard !isLoading else { return }
        if recorder.isRecording {
            guard let audio = recorder.finishRecording() else { return }
            send(audio)
        } else if !recorder.isPreparing {
            speech.stop()
            pendingQuery = nil
            recorder.beginRecording()
        }
    }

    private func send(_ audioData: Data) {
        guard !audioData.isEmpty, !isLoading else { return }
        guard let model = settings.preferredModel else {
            errorMessage = "Add an API key in Settings."
            return
        }
        isLoading = true
        let key = settings.apiKey(for: model.provider)
        requestTask = Task {
            do {
                let response: String
                if settings.voiceInputMode == .text {
                    let transcriptionKey = settings.apiKey(for: .google)
                    let query = try await apiService.transcribeAudio(audioData: audioData, model: .geminiFlashLite, apiKey: transcriptionKey)
                    try Task.checkCancellation()
                    pendingQuery = query
                    let user = Message(role: .user, content: query)
                    response = try await apiService.sendMessage(messages: [user], model: model, connectionMode: .bringYourOwnKey, apiKey: key, gatewayURL: settings.gatewayURL)
                } else {
                    response = try await apiService.sendAudioMessage(audioData: audioData, model: model, apiKey: key)
                }
                try Task.checkCancellation()
                pendingQuery = nil
                messages.append(Message(role: .assistant, content: response, model: model.displayName))
                speech.speak(response)
                withAnimation(.easeOut(duration: 0.2)) { orbVisible = false }
            } catch is CancellationError {
            } catch { errorMessage = error.localizedDescription }
            isLoading = false
            requestTask = nil
        }
    }

}

private struct ConversationMessage: View {
    let message: Message
    var body: some View {
        if message.role == .user {
            HStack {
                Spacer(minLength: 30)
                Text(message.content)
                    .font(.caption).lineLimit(3).padding(.horizontal, 10).padding(.vertical, 7)
                    .background(Color.cyan.opacity(0.18), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.cyan.opacity(0.35)))
            }
        } else {
            Text(message.content)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private enum OrbState { case ready, listening, thinking }

private struct VoiceOrb: View {
    let state: OrbState

    private var orbColor: Color {
        state == .thinking ? .pink : .cyan
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(orbColor.opacity(0.18))
                .frame(width: 82, height: 82)
            Circle()
                .fill(LinearGradient(colors: state == .thinking ? [.pink, .purple] : [.cyan, .blue, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 62, height: 62)
                .shadow(color: orbColor.opacity(0.55), radius: 7)
            Image(systemName: state == .listening ? "waveform" : (state == .thinking ? "sparkles" : "mic.fill"))
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 100, height: 100)
        .contentShape(Circle())
        .accessibilityLabel(state == .listening ? "Stop and send" : "Start speaking")
    }
}

@MainActor
private final class VoiceRecorder: NSObject, ObservableObject {
    @Published private(set) var isRecording = false
    @Published private(set) var isPreparing = false
    @Published private(set) var errorMessage: String?
    private var recorder: AVAudioRecorder?
    private var recordingURL: URL?
    private var wantsToRecord = false

    func beginRecording() {
        errorMessage = nil
        wantsToRecord = true
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            startRecorderIfNeeded()
        case .denied:
            wantsToRecord = false
            errorMessage = "Microphone access is off. Enable it for Claude Watch in Settings."
        case .undetermined:
            AVAudioApplication.requestRecordPermission { [weak self] granted in
                Task { @MainActor in
                    guard let self else { return }
                    if granted, self.wantsToRecord { self.startRecorderIfNeeded() }
                    else if !granted { self.errorMessage = "Microphone access is required for voice questions." }
                }
            }
        @unknown default:
            wantsToRecord = false
            errorMessage = "Microphone permission is unavailable."
        }
    }

    func finishRecording() -> Data? {
        wantsToRecord = false
        guard let recorder, let url = recordingURL else { return nil }
        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        recordingURL = nil
        isRecording = false
        AudioSessionController.deactivate()
        defer { try? FileManager.default.removeItem(at: url) }
        guard duration >= 0.2 else {
            errorMessage = "Hold the bar while speaking, then release."
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func startRecorderIfNeeded() {
        guard wantsToRecord, recorder == nil, !isPreparing else { return }
        isPreparing = true
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result<(AVAudioRecorder, URL), Error> {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playAndRecord, mode: .spokenAudio)
                try session.setActive(true)
                let url = FileManager.default.temporaryDirectory
                    .appendingPathComponent("voice-\(UUID().uuidString).wav")
                let recordingSettings: [String: Any] = [
                    AVFormatIDKey: kAudioFormatLinearPCM,
                    AVSampleRateKey: 16_000,
                    AVNumberOfChannelsKey: 1,
                    AVLinearPCMBitDepthKey: 16,
                    AVLinearPCMIsFloatKey: false,
                    AVLinearPCMIsBigEndianKey: false
                ]
                let recorder = try AVAudioRecorder(url: url, settings: recordingSettings)
                recorder.prepareToRecord()
                guard recorder.record() else { throw RecorderError.couldNotStart }
                return (recorder, url)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isPreparing = false
                switch result {
                case let .success((recorder, url)) where self.wantsToRecord:
                    self.recorder = recorder
                    self.recordingURL = url
                    self.isRecording = true
                case let .success((recorder, url)):
                    recorder.stop()
                    AudioSessionController.deactivate()
                    try? FileManager.default.removeItem(at: url)
                case let .failure(error):
                    self.wantsToRecord = false
                    self.errorMessage = "Couldn’t start the microphone: \(error.localizedDescription)"
                }
            }
        }
    }

    private enum RecorderError: LocalizedError {
        case couldNotStart
        var errorDescription: String? { "Recording could not start" }
    }
}

private enum AudioSessionController {
    static func deactivate() {
        DispatchQueue.global(qos: .utility).async {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        }
    }
}

@MainActor
private final class SpeechOutput: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    @Published private(set) var isSpeaking = false
    private let synthesizer = AVSpeechSynthesizer()
    override init() {
        super.init()
        synthesizer.delegate = self
    }
    func speak(_ text: String) {
        stop()
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice.speechVoices().first {
            $0.language.hasPrefix("en") && $0.gender == .female
        } ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.48
        utterance.pitchMultiplier = 1.04
        utterance.volume = 1
        synthesizer.speak(utterance)
    }
    func stop() {
        if synthesizer.isSpeaking { synthesizer.stopSpeaking(at: .immediate) }
        isSpeaking = false
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            AudioSessionController.deactivate()
        }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            AudioSessionController.deactivate()
        }
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
