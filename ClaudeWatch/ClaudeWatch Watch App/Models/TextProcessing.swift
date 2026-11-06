import Foundation

// MARK: - Speech text cleanup

/// Turns Claude's markdown-flavoured output into something that sounds natural when spoken.
enum SpeechTextCleaner {
    static func clean(_ text: String) -> String {
        var s = text

        // Inline code, images and links keep only their human-readable part.
        s = replace(#"`([^`]*)`"#, in: s, with: "$1")
        s = replace(#"!\[([^\]]*)\]\([^)]*\)"#, in: s, with: "$1")
        s = replace(#"\[([^\]]+)\]\([^)]*\)"#, in: s, with: "$1")
        s = replace(#"https?://\S+"#, in: s, with: "link")

        // Block-level markers.
        s = replace(#"(?m)^\s{0,3}#{1,6}\s*"#, in: s, with: "")
        s = replace(#"(?m)^\s*[-*•]\s+"#, in: s, with: "")
        s = replace(#"(?m)^\s*>\s?"#, in: s, with: "")
        s = replace(#"(?m)^\s*[-=_*]{3,}\s*$"#, in: s, with: "")
        s = replace(#"\|"#, in: s, with: ", ")

        // Emphasis markers.
        s = replace(#"\*\*(.+?)\*\*"#, in: s, with: "$1")
        s = replace(#"__(.+?)__"#, in: s, with: "$1")
        s = replace(#"\*(.+?)\*"#, in: s, with: "$1")
        s = replace(#"(?<!\w)_(.+?)_(?!\w)"#, in: s, with: "$1")
        s = s.replacingOccurrences(of: "*", with: "")

        // Symbols that synthesizers read badly.
        s = s.replacingOccurrences(of: "—", with: ", ")
        s = s.replacingOccurrences(of: " – ", with: ", ")
        s = s.replacingOccurrences(of: "&", with: " and ")
        s = s.replacingOccurrences(of: "→", with: " to ")
        s = s.replacingOccurrences(of: "…", with: "...")

        // Emoji are read out as long descriptions ("smiling face with...").
        s = String(String.UnicodeScalarView(s.unicodeScalars.filter {
            !$0.properties.isEmojiPresentation && $0.value != 0xFE0F && $0.value != 0x200D
        }))

        // Give every line a terminal pause so bullet items don't run together.
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

    /// Splits cleaned text into sentences so playback can start quickly and be interrupted cleanly.
    static func sentences(in text: String) -> [String] {
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
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }
}

// MARK: - Incremental sentence extraction (for speaking while streaming)

/// Accepts streamed text deltas and emits complete, speakable sentences as soon as they exist.
struct SentenceExtractor {
    private var buffer = ""
    private var inCodeFence = false

    /// Feed a new piece of text; returns any sentences that are now complete.
    mutating func feed(_ delta: String) -> [String] {
        buffer += delta
        guard let cut = lastBoundary(in: buffer) else { return [] }
        let ready = String(buffer[..<cut])
        buffer = String(buffer[cut...])
        return speakable(ready)
    }

    /// Call when the stream ends to emit whatever is left.
    mutating func flush() -> [String] {
        let rest = buffer
        buffer = ""
        return speakable(rest)
    }

    private func lastBoundary(in text: String) -> String.Index? {
        var index = text.endIndex
        while index > text.startIndex {
            let prev = text.index(before: index)
            let ch = text[prev]
            if ch == "\n" { return index }
            if ".!?".contains(ch), index < text.endIndex, text[index].isWhitespace {
                if ch == "." && isListNumber(before: prev, in: text) {
                    index = prev
                    continue
                }
                return index
            }
            index = prev
        }
        return nil
    }

    /// "1. Item" must not be split after the "1.".
    private func isListNumber(before dot: String.Index, in text: String) -> Bool {
        var i = dot
        var sawDigit = false
        while i > text.startIndex {
            let p = text.index(before: i)
            if text[p].isNumber { sawDigit = true; i = p } else { break }
        }
        guard sawDigit else { return false }
        return i == text.startIndex || text[text.index(before: i)] == "\n"
    }

    /// Removes fenced code (tracking fences that span several chunks), then cleans and splits.
    private mutating func speakable(_ raw: String) -> [String] {
        var spoken = ""
        let parts = raw.components(separatedBy: "```")
        for (i, part) in parts.enumerated() {
            if i > 0 {
                inCodeFence.toggle()
                if inCodeFence { spoken += "\nCode block omitted.\n" }
            }
            if !inCodeFence { spoken += part }
        }
        return SpeechTextCleaner.sentences(in: SpeechTextCleaner.clean(spoken))
    }
}

// MARK: - Markdown for display

enum MarkdownLite {
    /// Renders inline markdown (bold, italic, code, links) and turns block syntax
    /// SwiftUI can't render (headings, bullets, fences) into plain-text equivalents.
    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .inlineOnlyPreservingWhitespace
        )
        return (try? AttributedString(markdown: prepare(text), options: options)) ?? AttributedString(text)
    }

    static func prepare(_ text: String) -> String {
        var lines: [String] = []
        for raw in text.components(separatedBy: "\n") {
            let trimmed = raw.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("```") { continue }

            if let match = trimmed.range(of: #"^#{1,6}\s+"#, options: .regularExpression) {
                lines.append("**" + trimmed[match.upperBound...] + "**")
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let indent = raw.prefix { $0 == " " || $0 == "\t" }
                lines.append(indent + "• " + trimmed.dropFirst(2))
            } else {
                lines.append(raw)
            }
        }
        return lines.joined(separator: "\n")
    }
}
