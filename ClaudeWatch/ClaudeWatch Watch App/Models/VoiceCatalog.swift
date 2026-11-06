import AVFoundation

/// A simple, stable way to pick a voice: "Female 1", "Male 2", ...
/// Slots are ranked best-first from the voices actually installed on the watch
/// (Premium > Enhanced > Standard), so "Female 1" is always the nicest female voice available.
struct VoiceOption: Identifiable, Equatable {
    let id: String            // e.g. "female-1"
    let label: String         // e.g. "Female 1"
    let voice: AVSpeechSynthesisVoice

    var voiceName: String { voice.name }

    /// e.g. "United States" (plus "Premium"/"Enhanced" when the device has a higher-quality voice).
    var detail: String {
        var parts: [String] = []
        let region = voice.language.split(separator: "-").last.map(String.init) ?? ""
        if let name = Locale.current.localizedString(forRegionCode: region) { parts.append(name) }
        switch voice.quality {
        case .premium: parts.append("Premium")
        case .enhanced: parts.append("Enhanced")
        default: break
        }
        return parts.joined(separator: " · ")
    }

    static func == (lhs: VoiceOption, rhs: VoiceOption) -> Bool { lhs.id == rhs.id && lhs.voice.identifier == rhs.voice.identifier }
}

enum VoiceCatalog {
    static let defaultSlot = "female-1"
    private static let slotsPerGender = 3

    static func options() -> [VoiceOption] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()

        // Prefer the device language; fall back to English so there is always something to pick.
        var pool = all.filter { $0.language.hasPrefix(language) && isNatural($0) }
        if pool.isEmpty { pool = all.filter { $0.language.hasPrefix("en") && isNatural($0) } }
        if pool.isEmpty { pool = all }

        let ranked = pool.sorted(by: isBetter)

        var result: [VoiceOption] = []
        for (gender, name) in [(AVSpeechSynthesisVoiceGender.female, "Female"), (.male, "Male")] {
            let matching = ranked.filter { $0.gender == gender }.prefix(slotsPerGender)
            for (index, voice) in matching.enumerated() {
                result.append(VoiceOption(id: "\(name.lowercased())-\(index + 1)", label: "\(name) \(index + 1)", voice: voice))
            }
        }

        // Some devices don't report gender; make sure the list is never empty.
        if result.isEmpty, let fallback = AVSpeechSynthesisVoice(language: Locale.current.identifier) ?? ranked.first {
            result = [VoiceOption(id: defaultSlot, label: "Default", voice: fallback)]
        }
        return result
    }

    /// Resolves a saved slot id; falls back to the best female voice, then anything.
    static func voice(forSlot slot: String) -> AVSpeechSynthesisVoice? {
        let list = options()
        return list.first { $0.id == slot }?.voice
            ?? list.first { $0.id == defaultSlot }?.voice
            ?? list.first?.voice
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: ranking

    /// Skips novelty/robotic voices (Fred, Bad News, Zarvox, ...).
    private static func isNatural(_ voice: AVSpeechSynthesisVoice) -> Bool {
        !voice.identifier.contains(".speech.synthesis.voice.")
    }

    private static func isBetter(_ a: AVSpeechSynthesisVoice, _ b: AVSpeechSynthesisVoice) -> Bool {
        if a.quality.rawValue != b.quality.rawValue { return a.quality.rawValue > b.quality.rawValue }
        let aEloquence = a.identifier.contains("eloquence"), bEloquence = b.identifier.contains("eloquence")
        if aEloquence != bEloquence { return !aEloquence }          // Eloquence voices sound more synthetic
        let aRank = regionRank(a), bRank = regionRank(b)
        if aRank != bRank { return aRank < bRank }
        return a.name < b.name
    }

    /// Exact device locale first, then US English (the most natural-sounding set), then UK, AU, others.
    private static func regionRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        // The user's preferred language (e.g. "en-GB"), not the regional-format setting.
        let device = Locale.preferredLanguages.first.map { $0.split(separator: "-").prefix(2).joined(separator: "-") }
        if voice.language == device { return 0 }
        switch voice.language {
        case "en-US": return 1
        case "en-GB": return 2
        case "en-AU": return 3
        default: return 4
        }
    }
}
