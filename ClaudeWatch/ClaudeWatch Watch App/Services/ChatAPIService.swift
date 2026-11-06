import Foundation

enum StreamEvent: Sendable {
    case text(String)
    /// `stopReason` is normalised across providers: "max_tokens", "refusal", or nil for a normal finish.
    case finished(stopReason: String?)
}

/// Streams chat replies from Anthropic or Gemini (server-sent events) with retry/backoff.
final class ChatAPIService: Sendable {
    private let anthropicURL: URL
    private let geminiBase: URL
    private let maxRetries = 2
    /// Only the most recent turns are sent, which keeps latency and token cost down on a watch.
    private let maxHistory = 20

    init(
        anthropicURL: URL = URL(string: "https://api.anthropic.com/v1/messages")!,
        geminiBase: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
    ) {
        self.anthropicURL = anthropicURL
        self.geminiBase = geminiBase
    }

    static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 45
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    enum APIError: LocalizedError {
        case invalidResponse
        case httpError(Int, String)
        case networkError(String)
        case noAPIKey
        case stream(String)

        var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Unexpected response from the server."
            case .noAPIKey: return "No API key configured."
            case .networkError(let message): return "Network problem: \(message)"
            case .stream(let message): return message
            case .httpError(let code, let message):
                let lower = message.lowercased()
                if code == 401 || code == 403 || ((code == 400) && (lower.contains("api key") || lower.contains("api_key"))) {
                    return "Your API key was rejected. Check it in Settings."
                }
                switch code {
                case 404: return "That model wasn't found. Pick another in Settings."
                case 429: return "Rate limited. Try again in a moment."
                case 503, 529: return "The service is busy right now. Try again shortly."
                default: return "Error \(code): \(message)"
                }
            }
        }
    }

    func stream(
        messages: [Message],
        provider: Provider,
        modelID: String,
        apiKey: String,
        systemPrompt: String,
        maxTokens: Int
    ) -> AsyncThrowingStream<StreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let request = try self.makeRequest(messages: messages, provider: provider, modelID: modelID,
                                                       apiKey: apiKey, systemPrompt: systemPrompt, maxTokens: maxTokens)
                    try await self.run(request, provider: provider, continuation: continuation)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    // MARK: - Requests

    private func makeRequest(
        messages: [Message], provider: Provider, modelID: String, apiKey: String, systemPrompt: String, maxTokens: Int
    ) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw APIError.noAPIKey }

        var history = messages.suffix(maxHistory).filter { !$0.content.isEmpty }
        while history.first?.role == .assistant { history.removeFirst() }

        var request: URLRequest
        switch provider {
        case .anthropic:
            request = URLRequest(url: anthropicURL)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            request.httpBody = try JSONEncoder().encode(ClaudeRequest(
                model: modelID,
                max_tokens: maxTokens,
                stream: true,
                messages: history.map { .init(role: $0.role.rawValue, content: $0.content) },
                system: systemPrompt,
                // Chat on a watch wants snappy answers, not deep reasoning. Only models that support it get the field.
                output_config: Self.supportsEffort(modelID) ? .init(effort: "low") : nil
            ))

        case .gemini:
            let url = geminiBase
                .appendingPathComponent("models")
                .appendingPathComponent("\(modelID):streamGenerateContent")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "alt", value: "sse")]
            request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            request.httpBody = try JSONEncoder().encode(GeminiRequest(
                systemInstruction: .init(role: nil, parts: [.init(text: systemPrompt)]),
                contents: history.map {
                    .init(role: $0.role == .user ? "user" : "model", parts: [.init(text: $0.content)])
                },
                generationConfig: .init(maxOutputTokens: maxTokens)
            ))
        }

        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    /// The `effort` control exists on the Claude 5 family and Fable; older models reject it.
    static func supportsEffort(_ modelID: String) -> Bool {
        ["claude-opus-5", "claude-sonnet-5", "claude-haiku-5", "claude-fable"].contains { modelID.hasPrefix($0) }
    }

    // MARK: - Transport

    private func run(
        _ request: URLRequest, provider: Provider, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation
    ) async throws {
        for attempt in 0...maxRetries {
            let bytes: URLSession.AsyncBytes
            let response: URLResponse
            do {
                (bytes, response) = try await Self.session.bytes(for: request)
            } catch let error as URLError where error.code == .cancelled {
                throw CancellationError()
            } catch {
                if attempt < maxRetries {
                    try await Task.sleep(for: .seconds(Double(1 << attempt)))
                    continue
                }
                throw APIError.networkError((error as? URLError)?.localizedDescription ?? error.localizedDescription)
            }

            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }

            if http.statusCode == 200 {
                switch provider {
                case .anthropic: try await parseAnthropic(bytes, continuation: continuation)
                case .gemini: try await parseGemini(bytes, continuation: continuation)
                }
                return
            }

            let message = await Self.errorMessage(from: bytes)
            if [429, 500, 502, 503, 529].contains(http.statusCode), attempt < maxRetries {
                let advised = http.value(forHTTPHeaderField: "retry-after").flatMap(Double.init)
                try await Task.sleep(for: .seconds(min(advised ?? Double(1 << attempt), 8)))
                continue
            }
            throw APIError.httpError(http.statusCode, message)
        }
    }

    private func parseAnthropic(_ bytes: URLSession.AsyncBytes, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let decoder = JSONDecoder()
        var stopReason: String?

        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let data = Self.sseData(line),
                      let event = try? decoder.decode(ClaudeStreamEvent.self, from: data) else { continue }

                switch event.type {
                case "content_block_delta":
                    if event.delta?.type == "text_delta", let text = event.delta?.text, !text.isEmpty {
                        continuation.yield(.text(text))
                    }
                case "message_delta":
                    if let reason = event.delta?.stop_reason { stopReason = reason }
                case "error":
                    throw APIError.stream(event.error?.message ?? "The stream was interrupted.")
                default:
                    break
                }
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
        continuation.yield(.finished(stopReason: (stopReason == "max_tokens" || stopReason == "refusal") ? stopReason : nil))
    }

    private func parseGemini(_ bytes: URLSession.AsyncBytes, continuation: AsyncThrowingStream<StreamEvent, Error>.Continuation) async throws {
        let decoder = JSONDecoder()
        var finishReason: String?
        var blocked = false

        do {
            for try await line in bytes.lines {
                try Task.checkCancellation()
                guard let data = Self.sseData(line),
                      let chunk = try? decoder.decode(GeminiChunk.self, from: data) else { continue }

                if let error = chunk.error { throw APIError.stream(error.message ?? "The stream was interrupted.") }
                if chunk.promptFeedback?.blockReason != nil { blocked = true }

                for candidate in chunk.candidates ?? [] {
                    for part in candidate.content?.parts ?? [] where part.thought != true {
                        if let text = part.text, !text.isEmpty { continuation.yield(.text(text)) }
                    }
                    if let reason = candidate.finishReason { finishReason = reason }
                }
            }
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }

        let normalised: String?
        if blocked { normalised = "refusal" }
        else {
            switch finishReason {
            case "MAX_TOKENS": normalised = "max_tokens"
            case "SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII", "RECITATION": normalised = "refusal"
            default: normalised = nil
            }
        }
        continuation.yield(.finished(stopReason: normalised))
    }

    // MARK: - Helpers

    private static func sseData(_ line: String) -> Data? {
        guard line.hasPrefix("data:") else { return nil }
        return line.dropFirst(5).trimmingCharacters(in: .whitespaces).data(using: .utf8)
    }

    /// Both providers return `{"error": {"message": "..."}}`.
    static func errorMessage(from bytes: URLSession.AsyncBytes) async -> String {
        var data = Data()
        do {
            for try await byte in bytes {
                data.append(byte)
                if data.count > 8_192 { break }
            }
        } catch {}
        return errorMessage(from: data)
    }

    static func errorMessage(from data: Data) -> String {
        struct Envelope: Decodable {
            struct Detail: Decodable { let message: String? }
            let error: Detail?
        }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.error?.message ?? "Unknown error"
    }
}

// MARK: - Gemini payloads

private struct GeminiRequest: Encodable {
    struct Part: Encodable { let text: String }
    struct Content: Encodable {
        let role: String?
        let parts: [Part]
    }
    struct GenerationConfig: Encodable { let maxOutputTokens: Int }

    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct GeminiChunk: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable { let parts: [Part]? }
        struct Part: Decodable {
            let text: String?
            let thought: Bool?
        }
        let content: Content?
        let finishReason: String?
    }
    struct PromptFeedback: Decodable { let blockReason: String? }
    struct ErrorDetail: Decodable { let message: String? }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
    let error: ErrorDetail?
}
