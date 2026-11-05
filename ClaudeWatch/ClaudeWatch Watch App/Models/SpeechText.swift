import Foundation

/// Prepares an answer for text-to-speech: skips code, strips what synthesizers read badly,
/// and splits into sentences so playback starts quickly and Stop reacts immediately.
enum SpeechText {
    static let previewSentences = ["Hi, this is how I sound."]

    /// `content` is the raw answer (markdown). Reuses AnswerFormatting so display and speech agree on structure.
    static func sentences(fromAnswer content: String) -> [String] {
        let spoken = AnswerFormatting.blocks(content).map { block -> String in
            block.kind == .code ? "Code block omitted." : String(AnswerFormatting.inline(block.text).characters)
        }.joined(separator: "\n")
        return split(clean(spoken))
    }

    // MARK: Cleanup

    static func clean(_ text: String) -> String {
        var s = text
        s = replace(#"https?://\S+"#, in: s, with: "link")
        s = s.replacingOccurrences(of: "—", with: ", ")
        s = s.replacingOccurrences(of: " – ", with: ", ")
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "→", with: " to ")
        s = s.replacingOccurrences(of: "…", with: "...")

        // Emoji are read out as long descriptions ("smiling face with...").
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter {
            !$0.properties.isEmojiPresentation && $0.value != 0xFE0F && $0.value != 0x200D
        }))

        // Give every line a terminal pause so list items don't run together.
        let lines = s.components(separatedBy: .newlines).compactMap { raw -> String? in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { return nil }
            if let last = line.last, ".!?:;,".contains(last) { return line }
            return line + "."
        }
        s = lines.joined(separator: "\n")
        s = replace(#"[ \t]{2,}"#, in: s, with: " ")
        s = replace(#" +([,.!?;:])"#, in: s, with: "$1")
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func split(_ text: String) -> [String] {
        var result: [String] = []
        text.enumerateSubstrings(in: text.startIndex..., options: [.bySentences, .substringNotRequired]) { _, range, _, _ in
            let sentence = text[range].trimmingCharacters(in: .whitespacesAndNewlines)
            if sentence.isEmpty { return }
            // Keep list numbers ("1.") attached to their item instead of speaking them alone.
            if let last = result.last, last.range(of: #"^\d+[.)]$"#, options: .regularExpression) != nil {
                result[result.count - 1] = last + " " + sentence
            } else {
                result.append(sentence)
            }
        }
        return result.isEmpty && !text.isEmpty ? [text] : result
    }

    private static func replace(_ pattern: String, in text: String, with template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        return regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}
