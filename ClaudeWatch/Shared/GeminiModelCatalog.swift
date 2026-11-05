import Foundation

/// Only model metadata is cached. API keys never enter the catalog or its URLs.
enum GeminiModelCatalog {
    struct Page: Decodable {
        struct Model: Decodable {
            let name: String
            let displayName: String?
            let supportedGenerationMethods: [String]?
        }
        let models: [Model]?
        let nextPageToken: String?
    }

    enum CatalogError: LocalizedError {
        case rejected(Int), invalidResponse, noModels
        var errorDescription: String? {
            switch self {
            case .rejected(let code):
                if code == 400 || code == 401 || code == 403 {
                    return "Google could not verify this key. Check the key and its API restrictions."
                }
                if code == 429 { return "Google's request limit was reached. Try again later." }
                return "Google could not list models (HTTP \(code)). Try again later."
            case .invalidResponse: return "Google returned an unreadable model list."
            case .noModels: return "No compatible Gemini chat models were returned for this key."
            }
        }
    }

    static func fetch(apiKey: String, session: URLSession = .shared) async throws -> [AIModel] {
        var models: [AIModel] = []
        var pageToken: String?
        var visited = Set<String>()
        repeat {
            try Task.checkCancellation()
            var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models")!
            components.queryItems = [URLQueryItem(name: "pageSize", value: "100")]
            if let pageToken { components.queryItems?.append(URLQueryItem(name: "pageToken", value: pageToken)) }
            var request = URLRequest(url: components.url!)
            request.timeoutInterval = 30
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CatalogError.invalidResponse }
            guard (200..<300).contains(response.statusCode) else { throw CatalogError.rejected(response.statusCode) }
            let page = try JSONDecoder().decode(Page.self, from: data)
            models.append(contentsOf: compatibleModels(in: page))
            pageToken = page.nextPageToken.flatMap { $0.isEmpty ? nil : $0 }
            if let pageToken, !visited.insert(pageToken).inserted { throw CatalogError.invalidResponse }
        } while pageToken != nil
        try Task.checkCancellation()
        guard !models.isEmpty else { throw CatalogError.noModels }
        return Array(Set(models)).sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    static func compatibleModels(in page: Page) -> [AIModel] {
        (page.models ?? []).compactMap { item in
            guard item.name.hasPrefix("models/gemini-"),
                  item.supportedGenerationMethods?.contains("generateContent") == true else { return nil }
            let id = String(item.name.dropFirst("models/".count))
            guard AIModel.isValidModelID(id),
                  !["image", "tts", "robotics", "embedding"].contains(where: id.contains) else { return nil }
            return AIModel(rawValue: id, provider: .google, displayName: item.displayName ?? id,
                           family: "Google AI", icon: "sparkles", isFreeCloudModel: false)
        }
    }
}

/// Sent only through a reachable paired WatchConnectivity session, never a URL or defaults.
struct CompanionSetup: Codable {
    let version: Int
    let apiKey: String
    let selectedModel: AIModel
    let models: [AIModel]

    var isValid: Bool {
        version == 1 && !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && apiKey.count <= 1024 && models.count <= 1000 && !models.isEmpty
            && selectedModel.provider == .google && !selectedModel.isFreeCloudModel
            && models.contains(selectedModel)
            && models.allSatisfy { $0.provider == .google && !$0.isFreeCloudModel && AIModel.isValidModelID($0.rawValue) }
    }
}
