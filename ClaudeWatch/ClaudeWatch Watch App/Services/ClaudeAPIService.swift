import Foundation

actor ChatAPIService {
    enum APIError: LocalizedError {
        case configuration(String)
        case invalidURL
        case invalidResponse
        case httpError(Int, String)
        case decodingError
        case networkError(Error)

        var errorDescription: String? {
            switch self {
            case .configuration(let message): return message
            case .invalidURL: return "Invalid server address"
            case .invalidResponse: return "The model returned an invalid response"
            case .httpError(let code, let message): return "Error \(code): \(message)"
            case .decodingError: return "Could not read the model response"
            case .networkError(let error): return "Network error: \(error.localizedDescription)"
            }
        }
    }

    private let systemPrompt = "You are a fast, helpful assistant on Apple Watch. Answer directly in 1-4 short sentences. Use concise lists only when they improve clarity."

    func sendMessage(
        messages: [Message],
        model: AIModel,
        connectionMode: ConnectionMode,
        apiKey: String,
        gatewayURL: String,
        allowFallback: Bool = false
    ) async throws -> String {
        if connectionMode == .freeCloud {
            guard model.isFreeCloudModel else {
                throw APIError.configuration("Choose a Free Cloud model or switch to Your Key.")
            }
            return try await sendOpenAICompatible(
                endpoint: gatewayEndpoint(from: gatewayURL),
                model: model.rawValue,
                apiKey: nil,
                messages: messages
            )
        }

        guard !apiKey.isEmpty else {
            throw APIError.configuration("Add a \(model.provider.displayName) API key in Settings.")
        }

        switch model.provider {
        case .anthropic:
            return try await sendAnthropic(messages: messages, model: model.rawValue, apiKey: apiKey)
        case .google:
            do {
                return try await sendGemini(messages: messages, model: model.rawValue, apiKey: apiKey)
            } catch {
                guard allowFallback else { throw error }
                return try await sendOpenAICompatible(
                    endpoint: gatewayEndpoint(from: gatewayURL),
                    model: AIModel.pollinationsFast.rawValue,
                    apiKey: nil,
                    messages: messages
                )
            }
        case .openRouter:
            return try await sendOpenAICompatible(endpoint: URL(string: "https://openrouter.ai/api/v1/chat/completions")!, model: model.rawValue, apiKey: apiKey, messages: messages)
        case .groq:
            return try await sendOpenAICompatible(endpoint: URL(string: "https://api.groq.com/openai/v1/chat/completions")!, model: model.rawValue, apiKey: apiKey, messages: messages)
        case .openAI:
            return try await sendOpenAICompatible(endpoint: URL(string: "https://api.openai.com/v1/chat/completions")!, model: model.rawValue, apiKey: apiKey, messages: messages)
        case .perplexity:
            return try await sendOpenAICompatible(endpoint: URL(string: "https://api.perplexity.ai/chat/completions")!, model: model.rawValue, apiKey: apiKey, messages: messages)
        case .pollinations:
            return try await sendOpenAICompatible(endpoint: URL(string: "https://gen.pollinations.ai/v1/chat/completions")!, model: model.rawValue, apiKey: apiKey, messages: messages)
        }
    }

    func sendAudioMessage(audioData: Data, model: AIModel, apiKey: String) async throws -> String {
        guard model.provider == .google else {
            throw APIError.configuration("Voice queries require Gemini.")
        }
        guard !apiKey.isEmpty else {
            throw APIError.configuration("Add a Google AI API key in Settings.")
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 45
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            systemInstruction: .init(role: "system", parts: [.init(text: systemPrompt)]),
            contents: [.init(role: "user", parts: [.init(audioData: audioData, mimeType: "audio/wav")])],
            generationConfig: .init(maxOutputTokens: 180)
        ))
        let data = try await perform(request)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = response.candidates?.first?.content.parts.compactMap(\.text).joined() ?? ""
        guard !text.isEmpty else { throw APIError.decodingError }
        return text
    }

    func transcribeAudio(audioData: Data, model: AIModel, apiKey: String) async throws -> String {
        guard model.provider == .google else {
            throw APIError.configuration("Background transcription requires a Gemini model.")
        }
        guard !apiKey.isEmpty else {
            throw APIError.configuration("Add a Google AI API key in Settings.")
        }
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model.rawValue):generateContent") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            systemInstruction: .init(role: "system", parts: [.init(text: "Transcribe the user's speech exactly. Return only the transcript, without a label or answer.")]),
            contents: [.init(role: "user", parts: [.init(audioData: audioData, mimeType: "audio/wav")])],
            generationConfig: .init(maxOutputTokens: 160)
        ))
        let data = try await perform(request)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = response.candidates?.first?.content.parts.compactMap(\.text).joined()
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !text.isEmpty else { throw APIError.decodingError }
        return text
    }

    private func gatewayEndpoint(from value: String) throws -> URL {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw APIError.configuration("Add your Free Cloud gateway URL in Settings.")
        }
        guard let suppliedURL = URL(string: trimmed) else { throw APIError.invalidURL }
        let endpoint: String
        if suppliedURL.path.isEmpty || suppliedURL.path == "/" {
            endpoint = "\(trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")))/v1/chat/completions"
        } else {
            endpoint = trimmed
        }
        guard let url = URL(string: endpoint) else { throw APIError.invalidURL }
        return url
    }

    private func sendOpenAICompatible(endpoint: URL, model: String, apiKey: String?, messages: [Message]) async throws -> String {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        let body = OpenAIChatRequest(
            model: model,
            messages: [OpenAIChatRequest.APIMessage(role: "system", content: systemPrompt)] + messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            max_tokens: 180,
            temperature: 0.4
        )
        request.httpBody = try JSONEncoder().encode(body)
        let data = try await perform(request)
        guard let text = try? JSONDecoder().decode(OpenAIChatResponse.self, from: data).choices.first?.message.content,
              !text.isEmpty else { throw APIError.decodingError }
        return text
    }

    private func sendAnthropic(messages: [Message], model: String, apiKey: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONEncoder().encode(AnthropicRequest(
            model: model,
            max_tokens: 180,
            messages: messages.map { .init(role: $0.role.rawValue, content: $0.content) },
            system: systemPrompt
        ))
        let data = try await perform(request)
        let response = try JSONDecoder().decode(AnthropicResponse.self, from: data)
        let text = response.content.compactMap(\.text).joined()
        guard !text.isEmpty else { throw APIError.decodingError }
        return text
    }

    private func sendGemini(messages: [Message], model: String, apiKey: String) async throws -> String {
        guard let url = URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent") else {
            throw APIError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 35
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        request.httpBody = try JSONEncoder().encode(GeminiRequest(
            systemInstruction: .init(role: "system", parts: [.init(text: systemPrompt)]),
            contents: messages.map { .init(role: $0.role == .assistant ? "model" : "user", parts: [.init(text: $0.content)]) },
            generationConfig: .init(maxOutputTokens: 180)
        ))
        let data = try await perform(request)
        let response = try JSONDecoder().decode(GeminiResponse.self, from: data)
        let text = response.candidates?.first?.content.parts.compactMap(\.text).joined() ?? ""
        guard !text.isEmpty else { throw APIError.decodingError }
        return text
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
            guard (200...299).contains(http.statusCode) else {
                throw APIError.httpError(http.statusCode, apiErrorMessage(from: data))
            }
            return data
        } catch let error as APIError {
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func apiErrorMessage(from data: Data) -> String {
        if let error = try? JSONDecoder().decode(ProviderError.self, from: data) {
            return error.error?.message ?? error.message ?? "Request failed"
        }
        return "Request failed"
    }
}

private struct OpenAIChatRequest: Codable {
    struct APIMessage: Codable { let role: String; let content: String }
    let model: String
    let messages: [APIMessage]
    let max_tokens: Int
    let temperature: Double
}

private struct OpenAIChatResponse: Codable {
    struct Choice: Codable { struct APIMessage: Codable { let content: String? }; let message: APIMessage }
    let choices: [Choice]
}

private struct AnthropicRequest: Codable {
    struct APIMessage: Codable { let role: String; let content: String }
    let model: String
    let max_tokens: Int
    let messages: [APIMessage]
    let system: String
}

private struct AnthropicResponse: Codable {
    struct Content: Codable { let text: String? }
    let content: [Content]
}

private struct GeminiRequest: Codable {
    struct Part: Codable {
        struct InlineData: Codable { let mimeType: String; let data: String }
        let text: String?
        let inlineData: InlineData?

        init(text: String) {
            self.text = text
            inlineData = nil
        }

        init(audioData: Data, mimeType: String) {
            text = nil
            inlineData = .init(mimeType: mimeType, data: audioData.base64EncodedString())
        }
    }
    struct Content: Codable { let role: String?; let parts: [Part] }
    struct GenerationConfig: Codable { let maxOutputTokens: Int }
    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig
}

private struct GeminiResponse: Codable {
    struct Candidate: Codable { struct Content: Codable { let parts: [Part] }; struct Part: Codable { let text: String? }; let content: Content }
    let candidates: [Candidate]?
}

private struct ProviderError: Codable {
    struct Detail: Codable { let message: String? }
    let error: Detail?
    let message: String?
}
