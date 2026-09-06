import SwiftUI

/// Shared rendering for answers and speech: block structure is laid out for the
/// wrist, while Foundation handles inline emphasis, links, and code spans.
enum AnswerFormatting {
    struct Block {
        enum Kind { case paragraph, heading, list, quote, code }
        let kind: Kind
        let text: String
        var marker: String? = nil
    }

    static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(
            interpretedSyntax: .inlineOnlyPreservingWhitespace,
            failurePolicy: .returnPartiallyParsedIfPossible
        ))) ?? AttributedString(text)
    }

    static func blocks(_ content: String) -> [Block] {
        var result: [Block] = []
        var paragraph: [String] = []
        var code: [String] = []
        var fence: String?
        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            result.append(Block(kind: .paragraph, text: paragraph.joined(separator: "\n")))
            paragraph.removeAll()
        }
        for raw in content.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if let delimiter = fence {
                if line.hasPrefix(delimiter) {
                    result.append(Block(kind: .code, text: code.joined(separator: "\n")))
                    code.removeAll()
                    fence = nil
                } else { code.append(raw) }
                continue
            }
            if line.hasPrefix("```") || line.hasPrefix("~~~") {
                flushParagraph()
                fence = String(line.prefix(3))
            } else if line.isEmpty {
                flushParagraph()
            } else if line.range(of: "^#{1,6}\\s+", options: .regularExpression) != nil {
                flushParagraph()
                let text = line.replacingOccurrences(of: "^#{1,6}\\s+|\\s+#+$", with: "", options: .regularExpression)
                result.append(Block(kind: .heading, text: text))
            } else if line.range(of: "^([-*_]\\s*){3,}$", options: .regularExpression) != nil {
                flushParagraph()
            } else if let range = line.range(of: "^(?:[-+*]|[0-9]+[.)])\\s+", options: .regularExpression) {
                flushParagraph()
                let prefix = String(line[range]).trimmingCharacters(in: .whitespaces)
                var text = String(line[range.upperBound...])
                var marker = prefix.first?.isNumber == true ? prefix : "•"
                if text.hasPrefix("[ ] ") { marker = "☐"; text = String(text.dropFirst(4)) }
                if text.hasPrefix("[x] ") || text.hasPrefix("[X] ") { marker = "☑"; text = String(text.dropFirst(4)) }
                result.append(Block(kind: .list, text: text, marker: marker))
            } else if line.hasPrefix(">") {
                flushParagraph()
                let text = line.replacingOccurrences(of: "^>+\\s*", with: "", options: .regularExpression)
                result.append(Block(kind: .quote, text: text))
            } else if line.contains("|"), line.range(of: "^[| :\\-]+$", options: .regularExpression) != nil {
                flushParagraph()
            } else if line.hasPrefix("|"), line.hasSuffix("|") {
                flushParagraph()
                let cells = line.dropFirst().dropLast().components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                result.append(Block(kind: .paragraph, text: cells.joined(separator: " · ")))
            } else {
                paragraph.append(line)
            }
        }
        flushParagraph()
        if !code.isEmpty { result.append(Block(kind: .code, text: code.joined(separator: "\n"))) }
        return result
    }

    static func plainText(_ content: String) -> String {
        blocks(content).map { block in
            block.kind == .code ? block.text : String(inline(block.text).characters)
        }.joined(separator: "\n\n")
    }
}

struct AnswerText: View {
    let content: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(AnswerFormatting.blocks(content).enumerated()), id: \.offset) { _, block in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let marker = block.marker {
                        Text(marker).foregroundStyle(.cyan)
                            .accessibilityHidden(true)
                    }
                    if block.kind == .code {
                        Text(block.text)
                            .font(.system(.caption, design: .monospaced))
                            .padding(8)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
                    } else {
                        Text(AnswerFormatting.inline(block.text))
                            .fontWeight(block.kind == .heading ? .semibold : .regular)
                            .foregroundStyle(block.kind == .quote ? Color.secondary : Color.primary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.body)
        .lineSpacing(3)
        .tint(.cyan)
    }
}

struct MessageBubble: View {
    let message: Message

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if message.role == .assistant {
                AnswerText(content: message.content)
            } else {
                Text(message.content).font(.body)
            }
            if let model = message.model {
                Text(model).font(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(9)
        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
