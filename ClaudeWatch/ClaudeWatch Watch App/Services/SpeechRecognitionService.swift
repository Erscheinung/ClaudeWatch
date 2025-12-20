import Foundation
import Speech
import AVFoundation

@MainActor
class SpeechRecognitionService: ObservableObject {
    @Published var isRecording = false
    @Published var transcribedText = ""
    @Published var errorMessage: String?
    @Published var isAuthorized = false
    
    private var audioEngine: AVAudioEngine?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    
    init() {
        checkAuthorization()
    }
    
    func checkAuthorization() {
        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self?.isAuthorized = true
                case .denied, .restricted, .notDetermined:
                    self?.isAuthorized = false
                    self?.errorMessage = "Speech recognition not authorized"
                @unknown default:
                    self?.isAuthorized = false
                }
            }
        }
    }
    
    func startRecording() {
        guard isAuthorized else {
            errorMessage = "Speech recognition not authorized"
            return
        }
        
        guard let speechRecognizer = speechRecognizer, speechRecognizer.isAvailable else {
            errorMessage = "Speech recognizer not available"
            return
        }
        
        // Reset
        transcribedText = ""
        errorMessage = nil
        
        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            errorMessage = "Audio session error: \(error.localizedDescription)"
            return
        }
        
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else { return }
        
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        guard let recognitionRequest = recognitionRequest else { return }
        
        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.taskHint = .dictation
        
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }
            
            if let result = result {
                DispatchQueue.main.async {
                    self.transcribedText = result.bestTranscription.formattedString
                }
            }
            
            if error != nil || (result?.isFinal ?? false) {
                DispatchQueue.main.async {
                    self.stopRecording()
                }
            }
        }
        
        do {
            audioEngine.prepare()
            try audioEngine.start()
            isRecording = true
        } catch {
            errorMessage = "Audio engine error: \(error.localizedDescription)"
            stopRecording()
        }
    }
    
    func stopRecording() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        
        audioEngine = nil
        recognitionRequest = nil
        recognitionTask = nil
        
        isRecording = false
        
        // Deactivate audio session
        try? AVAudioSession.sharedInstance().setActive(false)
    }
    
    func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }
}
