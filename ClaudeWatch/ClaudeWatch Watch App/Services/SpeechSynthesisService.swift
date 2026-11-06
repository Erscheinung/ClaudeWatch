import AVFoundation
import SwiftUI

/// Reads Claude's replies aloud with Apple's on-device voices (no network, no cost).
/// Supports speaking a finished message, or speaking sentence-by-sentence while a reply streams in.
@MainActor
final class SpeechSynthesisService: NSObject, ObservableObject {
    /// The message currently being spoken, if any (drives the speaker button state).
    @Published private(set) var speakingMessageID: UUID?

    private let synthesizer = AVSpeechSynthesizer()
    private var extractor = SentenceExtractor()
    private var active = Set<ObjectIdentifier>()
    private var feedingFinished = true
    private var voice: AVSpeechSynthesisVoice?
    private var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Public API

    /// Tap-to-speak a finished message. Tapping again while it is speaking stops it.
    func toggle(_ text: String, messageID: UUID, settings: AppSettings) {
        if speakingMessageID == messageID {
            stop()
        } else {
            begin(messageID: messageID, settings: settings)
            enqueue(extractor.feed(text) + extractor.flush())
            finishFeeding()
        }
    }

    /// Start speaking a reply that is still streaming in.
    func beginStreaming(messageID: UUID, settings: AppSettings) {
        begin(messageID: messageID, settings: settings)
        feedingFinished = false
    }

    func feed(_ delta: String) {
        guard !feedingFinished else { return }
        enqueue(extractor.feed(delta))
    }

    func finishStreaming() {
        guard !feedingFinished else { return }
        enqueue(extractor.flush())
        finishFeeding()
    }

    func stop() {
        active.removeAll()                       // ignore the delegate callbacks this triggers
        synthesizer.stopSpeaking(at: .immediate)
        endSession()
    }

    /// Plays a short sample for the voice picker.
    func preview(voice: AVSpeechSynthesisVoice, settings: AppSettings) {
        stop()
        speakingMessageID = UUID()
        self.voice = voice
        self.rate = settings.speechSpeed.rate
        activateAudioSession()
        feedingFinished = true
        enqueue(["Hi, I'm Claude. This is how I sound."])
        finishFeeding()
    }

    // MARK: Internals

    private func begin(messageID: UUID, settings: AppSettings) {
        stop()
        extractor = SentenceExtractor()
        speakingMessageID = messageID
        voice = VoiceCatalog.voice(forSlot: settings.voiceSlot)
        rate = settings.speechSpeed.rate
        feedingFinished = true
        activateAudioSession()
    }

    private func enqueue(_ sentences: [String]) {
        for sentence in sentences where !sentence.isEmpty {
            let utterance = AVSpeechUtterance(string: sentence)
            utterance.voice = voice
            utterance.rate = rate
            utterance.pitchMultiplier = 1.0
            utterance.postUtteranceDelay = 0.05
            active.insert(ObjectIdentifier(utterance))
            synthesizer.speak(utterance)
        }
    }

    private func finishFeeding() {
        feedingFinished = true
        if active.isEmpty { endSession() }
    }

    private func utteranceEnded(_ id: ObjectIdentifier) {
        guard active.remove(id) != nil else { return }
        if active.isEmpty && feedingFinished { endSession() }
    }

    private func endSession() {
        speakingMessageID = nil
        feedingFinished = true
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func activateAudioSession() {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? session.setActive(true)
    }
}

extension SpeechSynthesisService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor in self.utteranceEnded(id) }
    }
}
