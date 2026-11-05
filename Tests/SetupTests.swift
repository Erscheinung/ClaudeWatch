import Foundation

private final class MockModelAPI: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
private enum SetupTests {
    static var checks = 0
    static func check(_ condition: Bool, _ label: String) {
        guard condition else { fatalError("FAIL: \(label)") }
        checks += 1
        print("PASS: \(label)")
    }
    static func main() async throws {
        let fixture = """
        {"models":[
          {"name":"models/gemini-future-flash-lite","displayName":"Future Flash Lite","supportedGenerationMethods":["generateContent"]},
          {"name":"models/gemini-future-image","supportedGenerationMethods":["generateContent"]},
          {"name":"models/embedding-other","supportedGenerationMethods":["embedContent"]},
          {"name":"models/gemini-no-chat","supportedGenerationMethods":["embedContent"]},
          {"name":"models/gemini-../../bad?key=secret","supportedGenerationMethods":["generateContent"]}
        ]}
        """
        let page = try JSONDecoder().decode(GeminiModelCatalog.Page.self, from: Data(fixture.utf8))
        let compatible = GeminiModelCatalog.compatibleModels(in: page)
        check(compatible.count == 1 && compatible[0].rawValue == "gemini-future-flash-lite", "Filter incompatible and malformed model IDs")
        let model = compatible[0]
        let roundTrip = try JSONDecoder().decode([AIModel].self, from: JSONEncoder().encode(compatible))
        check(roundTrip == compatible, "Live model metadata survives persisted catalog round trip")
        let restored = AIModel(rawValue: model.storageKey)
        check(restored?.rawValue == model.rawValue && restored?.provider == .google, "Unknown future model restores from saved selection")
        let payload = CompanionSetup(version: 1, apiKey: "test-key", selectedModel: model, models: compatible)
        check(payload.isValid, "Valid paired setup accepted")
        let decoded = try JSONDecoder().decode(CompanionSetup.self, from: JSONEncoder().encode(payload))
        check(decoded.isValid && decoded.selectedModel == model, "Transfer preserves selected live model metadata")
        check(!CompanionSetup(version: 2, apiKey: "test-key", selectedModel: model, models: compatible).isValid,
              "Reject unsupported transfer versions")
        check(!CompanionSetup(version: 1, apiKey: " ", selectedModel: model, models: compatible).isValid,
              "Reject empty credentials")
        check(!CompanionSetup(version: 1, apiKey: "test-key", selectedModel: .geminiFlashLite, models: compatible).isValid,
              "Reject selection outside verified catalog")
        check(!CompanionSetup(version: 1, apiKey: "test-key", selectedModel: .gptMini, models: [.gptMini]).isValid,
              "Reject other-provider payloads")

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockModelAPI.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        var calls = 0
        MockModelAPI.handler = { request in
            calls += 1
            check(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key"
                  && request.url?.absoluteString.contains("test-key") == false, "Key sent in header, never in URL")
            if calls == 1 {
                return (200, Data("{\"models\":[],\"nextPageToken\":\"page 2\"}".utf8))
            }
            check(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.contains(URLQueryItem(name: "pageToken", value: "page 2")) == true,
                  "Paginated request carries encoded page token")
            return (200, Data(fixture.utf8))
        }
        let fetched = try await GeminiModelCatalog.fetch(apiKey: "test-key", session: session)
        check(calls == 2 && fetched == compatible, "Fetch follows pages and filters response")

        MockModelAPI.handler = { _ in (403, Data("private provider response test-key".utf8)) }
        do {
            _ = try await GeminiModelCatalog.fetch(apiKey: "test-key", session: session)
            fatalError("Expected verification failure")
        } catch let error as GeminiModelCatalog.CatalogError {
            check(error.errorDescription?.contains("test-key") == false, "HTTP rejection does not reflect credential or provider response")
        }
        MockModelAPI.handler = { _ in (200, Data("{\"models\":[]}".utf8)) }
        do {
            _ = try await GeminiModelCatalog.fetch(apiKey: "test-key", session: session)
            fatalError("Expected empty catalog failure")
        } catch GeminiModelCatalog.CatalogError.noModels {
            check(true, "Empty catalog cannot verify usable setup")
        }
        MockModelAPI.handler = { _ in (200, Data("{\"models\":[],\"nextPageToken\":\"repeat\"}".utf8)) }
        do {
            _ = try await GeminiModelCatalog.fetch(apiKey: "test-key", session: session)
            fatalError("Expected repeated-page failure")
        } catch GeminiModelCatalog.CatalogError.invalidResponse {
            check(true, "Repeated page token cannot loop indefinitely")
        }
        let cancelled = Task { () throws -> [AIModel] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await GeminiModelCatalog.fetch(apiKey: "test-key", session: session)
        }
        do {
            _ = try await cancelled.value
            fatalError("Expected cancellation")
        } catch is CancellationError {
            check(true, "Cancelled verification stops before network request")
        }
        print("\(checks) checks passed")
    }
}
