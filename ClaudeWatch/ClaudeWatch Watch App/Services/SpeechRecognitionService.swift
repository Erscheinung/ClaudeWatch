import Foundation

// Apple Watch presents system Dictation from a focused TextField. A custom
// Speech-framework recorder is unavailable to this standalone watchOS target.
enum SpeechRecognitionService {
    static let usesSystemDictation = true
}
