import Foundation

/// Fetches the list of models a key can use straight from the provider, so the picker is always accurate.
/// A successful fetch also proves the key works.
enum ModelCatalogService {
    private static let maxModels = 60

    static func fetch(
        provider: Provider,
        apiKey: String,
        anthropicBase: URL = URL(string: "https://api.anthropic.com/v1/models")!,
        geminiBase: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta/models")!
    ) async throws -> [ModelInfo] {
        guard !apiKey.isEmpty else { throw ChatAPIService.APIError.noAPIKey }

        var request: URLRequest
        switch provider {
        case .anthropic:
            var components = URLComponents(url: anthropicBase, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "limit", value: "100")]
            request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .gemini:
            var components = URLComponents(url: geminiBase, resolvingAgainstBaseURL: false)!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "200")]
            request = URLRequest(url: components.url!)
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
        }
        request.timeoutInterval = 20

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await ChatAPIService.session.data(for: request)
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw ChatAPIService.APIError.networkError((error as? URLError)?.localizedDescription ?? error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else { throw ChatAPIService.APIError.invalidResponse }
        guard http.statusCode == 200 else {
            throw ChatAPIService.APIError.httpError(http.statusCode, ChatAPIService.errorMessage(from: data))
        }

        let models = try parse(provider: provider, data: data)
        if models.isEmpty { throw ChatAPIService.APIError.stream("No chat models are available for this key.") }
        return models
    }

    /// Exposed separately so it can be unit-tested without a network.
    static func parse(provider: Provider, data: Data) throws -> [ModelInfo] {
        switch provider {
        case .anthropic:
            struct List: Decodable {
                struct Item: Decodable { let id: String; let display_name: String? }
                let data: [Item]
            }
            let list = try JSONDecoder().decode(List.self, from: data)
            return list.data.prefix(maxModels).map { ModelInfo(id: $0.id, name: $0.display_name ?? $0.id) }

        case .gemini:
            struct List: Decodable {
                struct Item: Decodable {
                    let name: String
                    let displayName: String?
                    let supportedGenerationMethods: [String]?
                }
                let models: [Item]?
            }
            // Skip models that don't produce chat text (speech, images, embeddings, live/audio sessions).
            let excluded = ["tts", "image", "embedding", "imagen", "veo", "live", "audio", "aqa", "robotics", "computer-use",
                            "lyria", "banana", "transcribe", "deep-research", "antigravity", "customtools"]
            let list = try JSONDecoder().decode(List.self, from: data)
            return (list.models ?? [])
                .filter { $0.supportedGenerationMethods?.contains("generateContent") == true }
                .map { item -> ModelInfo in
                    let id = item.name.hasPrefix("models/") ? String(item.name.dropFirst(7)) : item.name
                    return ModelInfo(id: id, name: item.displayName ?? id)
                }
                .filter { model in !excluded.contains { model.id.lowercased().contains($0) } }
                .sorted { a, b in                  // Gemini family first, newest versions first
                    let aG = a.id.hasPrefix("gemini"), bG = b.id.hasPrefix("gemini")
                    return aG != bG ? aG : a.id > b.id
                }
                .prefix(maxModels)
                .map { $0 }
        }
    }

    // MARK: - Cache (so the picker opens instantly and works offline)

    static func cached(_ provider: Provider) -> [ModelInfo] {
        guard let data = UserDefaults.standard.data(forKey: "modelCache-\(provider.rawValue)") else { return [] }
        return (try? JSONDecoder().decode([ModelInfo].self, from: data)) ?? []
    }

    static func cache(_ models: [ModelInfo], for provider: Provider) {
        guard let data = try? JSONEncoder().encode(models) else { return }
        UserDefaults.standard.set(data, forKey: "modelCache-\(provider.rawValue)")
    }
}
