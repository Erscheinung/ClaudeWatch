import Foundation

actor ClaudeAPIService {
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let apiVersion = "2023-06-01"
    
    enum APIError: LocalizedError {
        case invalidURL
        case invalidResponse
        case httpError(Int, String)
        case decodingError(Error)
        case networkError(Error)
        case noAPIKey
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid URL"
            case .invalidResponse:
                return "Invalid response"
            case .httpError(let code, let message):
                return "Error \(code): \(message)"
            case .decodingError:
                return "Failed to parse response"
            case .networkError(let error):
                return "Network error: \(error.localizedDescription)"
            case .noAPIKey:
                return "No API key configured"
            }
        }
    }
    
    func sendMessage(
        messages: [Message],
        model: ClaudeModel,
        apiKey: String,
        systemPrompt: String? = nil
    ) async throws -> String {
        guard !apiKey.isEmpty else {
            throw APIError.noAPIKey
        }
        
        guard let url = URL(string: baseURL) else {
            throw APIError.invalidURL
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.timeoutInterval = 60
        
        let apiMessages = messages.map { message in
            ClaudeRequest.APIMessage(
                role: message.role.rawValue,
                content: message.content
            )
        }
        
        let requestBody = ClaudeRequest(
            model: model.rawValue,
            max_tokens: 512, // Keep responses concise for watch
            messages: apiMessages,
            system: systemPrompt ?? "You are Claude, responding on an Apple Watch. Keep responses brief and concise - ideally under 100 words. Be helpful but succinct."
        )
        
        request.httpBody = try JSONEncoder().encode(requestBody)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw APIError.invalidResponse
            }
            
            if httpResponse.statusCode != 200 {
                if let errorResponse = try? JSONDecoder().decode(ClaudeError.self, from: data) {
                    throw APIError.httpError(httpResponse.statusCode, errorResponse.error.message)
                }
                throw APIError.httpError(httpResponse.statusCode, "Unknown error")
            }
            
            let claudeResponse = try JSONDecoder().decode(ClaudeResponse.self, from: data)
            return claudeResponse.textContent
            
        } catch let error as APIError {
            throw error
        } catch let error as DecodingError {
            throw APIError.decodingError(error)
        } catch {
            throw APIError.networkError(error)
        }
    }
}
