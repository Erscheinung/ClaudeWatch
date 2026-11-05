import AVFoundation

/// How fast answers are read aloud.
enum SpeechSpeed: String, CaseIterable, Identifiable {
    case slow, normal, fast
    var id: String { rawValue }
    var title: String { rawValue.capitalized }

    var rate: Float {
        switch self {
        case .slow: return 0.44
        case .normal: return AVSpeechUtteranceDefaultSpeechRate
        case .fast: return 0.57
        }
    }
}

/// One selectable voice slot, e.g. "Female 1". Plain strings only, so it can be built off the main
/// thread and passed freely; the playback queue resolves the actual voice by slot id.
struct VoiceOption: Identifiable, Equatable, Sendable {
    let id: String           // "female-1"
    let label: String        // "Female 1"
    let voiceName: String    // "Samantha"
    let detail: String       // "United States" (+ "Premium"/"Enhanced" when the device has one)
}

/// Simple voice choice: "Female 1", "Male 1", ... ranked best-first from the voices installed on the watch.
/// Measured on an Apple Watch Ultra 3: every voice is "Standard" quality (no Enhanced/Premium exist on
/// watchOS), so ranking falls back to region, then name. Novelty and Eloquence voices are excluded.
enum VoiceCatalog {
    static let defaultSlot = "female-1"
    private static let slotsPerGender = 3

    /// Cheap, no voice lookup: "female-1" -> "Female 1". Safe on the main thread.
    static func label(forSlot slot: String) -> String {
        let parts = slot.split(separator: "-")
        guard parts.count == 2 else { return "Female 1" }
        return "\(parts[0].capitalized) \(parts[1])"
    }

    /// Enumerates installed voices. First call can be slow, so call it off the main thread.
    static func options() -> [VoiceOption] {
        ranked().flatMap { entry in entry }.map { $0.option }
    }

    /// Resolves a saved slot; falls back to the best female voice, then anything installed.
    static func voice(forSlot slot: String) -> AVSpeechSynthesisVoice? {
        let all = ranked().flatMap { $0 }
        return all.first { $0.option.id == slot }?.voice
            ?? all.first { $0.option.id == defaultSlot }?.voice
            ?? all.first?.voice
            ?? AVSpeechSynthesisVoice(language: "en-US")
    }

    // MARK: ranking

    private struct Entry {
        let option: VoiceOption
        let voice: AVSpeechSynthesisVoice
    }

    private static func ranked() -> [[Entry]] {
        let language = Locale.current.language.languageCode?.identifier ?? "en"
        let all = AVSpeechSynthesisVoice.speechVoices()

        // Prefer the device language; fall back to English so there is always something to pick.
        var pool = all.filter { $0.language.hasPrefix(language) && isNatural($0) }
        if pool.isEmpty { pool = all.filter { $0.language.hasPrefix("en") && isNatural($0) } }
        if pool.isEmpty { pool = all }
        let sorted = pool.sorted(by: isBetter)

        var groups: [[Entry]] = []
        for (gender, name) in [(AVSpeechSynthesisVoiceGender.female, "Female"), (.male, "Male")] {
            let matching = sorted.filter { $0.gender == gender }.prefix(slotsPerGender)
            groups.append(matching.enumerated().map { index, voice in
                Entry(option: VoiceOption(id: "\(name.lowercased())-\(index + 1)",
                                          label: "\(name) \(index + 1)",
                                          voiceName: voice.name,
                                          detail: detail(for: voice)),
                      voice: voice)
            })
        }

        // Some devices don't report gender; make sure the list is never empty.
        if groups.allSatisfy({ $0.isEmpty }),
           let fallback = AVSpeechSynthesisVoice(language: Locale.current.identifier) ?? sorted.first {
            groups = [[Entry(option: VoiceOption(id: defaultSlot, label: "Default", voiceName: fallback.name,
                                                 detail: detail(for: fallback)), voice: fallback)]]
        }
        return groups
    }

    private static func detail(for voice: AVSpeechSynthesisVoice) -> String {
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

    /// Exact preferred language first (e.g. en-GB), then US English (the most natural-sounding set), then UK, AU.
    private static func regionRank(_ voice: AVSpeechSynthesisVoice) -> Int {
        // The user's language preference, not the regional-format setting (a UK-English watch can have an India region).
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
