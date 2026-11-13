import Foundation

public struct BuiltRequest: Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?

    public init(method: String, url: URL, headers: [String: String], body: Data?) {
        self.method = method
        self.url = url
        self.headers = headers
        self.body = body
    }
}

public enum RequestBuildError: LocalizedError, Equatable {
    case badBaseURL(String)
    case missingModel

    public var errorDescription: String? {
        switch self {
        case .badBaseURL(let s): return "The service address “\(s)” isn't a valid web address."
        case .missingModel: return "Choose a model name in the menu bar."
        }
    }
}

public enum ResponseError: LocalizedError, Equatable {
    case unreadable
    case empty
    case refused(String?)

    public var errorDescription: String? {
        switch self {
        case .unreadable: return "The AI service sent a reply Glance couldn't read."
        case .empty: return "The AI service sent an empty reply."
        case .refused(let why):
            if let why, !why.isEmpty { return "The model declined: \(why)" }
            return "The model declined to answer this one."
        }
    }
}

/// Builds the HTTP requests and reads the replies, for both wire formats.
/// Pure Foundation, so it is unit-tested; the app only sends what this builds.
public enum RequestBuilder {
    public static let anthropicVersion = "2026-10-21"
    public static let fallbackBeta = "server-side-fallback-2026-07-01"
    /// Claude models that accept `fallbacks: "default"`: if the model declines a
    /// request, Anthropic re-runs it on a suitable model in the same call.
    public static let fallbackModels: Set<String> = [
        "claude-opus-5-5", "claude-opus-5", "claude-sonnet-5-5",
        "claude-fable-5-2", "claude-fable-5-1", "claude-mythos-5-2", "claude-mythos-5-1",
    ]

    public static func analysis(
        config: ServiceConfig,
        apiKey: String,
        imageBase64JPEG: String,
        instructions: String,
        structuredOutput: Bool
    ) throws -> BuiltRequest {
        let model = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !model.isEmpty else { throw RequestBuildError.missingModel }
        let trimmedInstructions = instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let userText = trimmedInstructions.isEmpty ? Prompt.defaultInstructions : trimmedInstructions
        let effort = config.reasoningEffort.trimmingCharacters(in: .whitespacesAndNewlines)

        switch config.format {
        case .openAI:
            let system: [String: Any] = ["role": "system", "content": Prompt.system]
            let textPart: [String: Any] = ["type": "text", "text": userText]
            let imageURL: [String: Any] = ["url": "data:image/jpeg;base64,\(imageBase64JPEG)"]
            let imagePart: [String: Any] = ["type": "image_url", "image_url": imageURL]
            let user: [String: Any] = ["role": "user", "content": [textPart, imagePart] as [Any]]
            var body: [String: Any] = ["model": model, "messages": [system, user] as [Any]]
            if structuredOutput {
                let schema: [String: Any] = ["name": "screen_answer", "strict": true, "schema": Prompt.answerSchema]
                body["response_format"] = ["type": "json_schema", "json_schema": schema] as [String: Any]
            }
            if !effort.isEmpty {
                body["reasoning_effort"] = effort
            }
            return BuiltRequest(
                method: "POST",
                url: try endpoint(config.baseURL, "/chat/completions"),
                headers: ["Authorization": "Bearer \(apiKey)", "Content-Type": "application/json"],
                body: try json(body)
            )

        case .anthropic:
            let source: [String: Any] = ["type": "base64", "media_type": "image/jpeg", "data": imageBase64JPEG]
            let imagePart: [String: Any] = ["type": "image", "source": source]
            let textPart: [String: Any] = ["type": "text", "text": userText]
            let user: [String: Any] = ["role": "user", "content": [imagePart, textPart] as [Any]]
            var outputConfig: [String: Any] = ["effort": effort.isEmpty ? "low" : effort]
            if structuredOutput {
                outputConfig["format"] = ["type": "json_schema", "schema": Prompt.answerSchema] as [String: Any]
            }
            var body: [String: Any] = [
                "model": model,
                "max_tokens": 16000,
                "system": Prompt.system,
                "messages": [user] as [Any],
                "output_config": outputConfig,
            ]
            var headers = [
                "x-api-key": apiKey,
                "anthropic-version": anthropicVersion,
                "content-type": "application/json",
            ]
            if fallbackModels.contains(model) {
                body["fallbacks"] = "default"
                headers["anthropic-beta"] = fallbackBeta
            }
            return BuiltRequest(
                method: "POST",
                url: try endpoint(config.baseURL, "/messages"),
                headers: headers,
                body: try json(body)
            )
        }
    }

    public static func listModels(config: ServiceConfig, apiKey: String) throws -> BuiltRequest {
        switch config.format {
        case .openAI:
            return BuiltRequest(
                method: "GET",
                url: try endpoint(config.baseURL, "/models"),
                headers: ["Authorization": "Bearer \(apiKey)"],
                body: nil
            )
        case .anthropic:
            return BuiltRequest(
                method: "GET",
                url: try endpoint(config.baseURL, "/models?limit=100"),
                headers: ["x-api-key": apiKey, "anthropic-version": anthropicVersion],
                body: nil
            )
        }
    }

    /// The model's reply text from a successful response body.
    public static func extractText(format: APIFormat, from data: Data) throws -> String {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            throw ResponseError.unreadable
        }
        switch format {
        case .openAI:
            guard let choices = object["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any]
            else { throw ResponseError.unreadable }
            if let content = message["content"] as? String,
               !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return content
            }
            if let parts = message["content"] as? [[String: Any]] {
                let text = parts.compactMap { $0["text"] as? String }.joined()
                if !text.isEmpty { return text }
            }
            if let refusal = message["refusal"] as? String, !refusal.isEmpty {
                throw ResponseError.refused(refusal)
            }
            throw ResponseError.empty

        case .anthropic:
            if (object["stop_reason"] as? String) == "refusal" {
                throw ResponseError.refused(nil)
            }
            let blocks = object["content"] as? [[String: Any]] ?? []
            let text = blocks
                .filter { ($0["type"] as? String) == "text" }
                .compactMap { $0["text"] as? String }
                .joined()
            guard !text.isEmpty else { throw ResponseError.empty }
            return text
        }
    }

    /// Model ids from a `/models` response. Both formats use `{"data": [{"id": ...}]}`.
    public static func extractModelIDs(from data: Data) -> [String] {
        guard let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let list = object["data"] as? [[String: Any]]
        else { return [] }
        return list
            .compactMap { $0["id"] as? String }
            .map { $0.hasPrefix("models/") ? String($0.dropFirst("models/".count)) : $0 }
            .sorted()
    }

    /// A readable message from an error response, whichever shape the service uses.
    public static func errorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            let text = String(decoding: data.prefix(300), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
        let dict = (object as? [String: Any]) ?? ((object as? [Any])?.first as? [String: Any])
        if let error = dict?["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        if let message = dict?["error"] as? String { return message }
        if let message = dict?["message"] as? String { return message }
        return nil
    }

    static func endpoint(_ base: String, _ path: String) throws -> URL {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard let url = URL(string: trimmed + path),
              let scheme = url.scheme?.lowercased(),
              scheme == "https" || scheme == "http",
              url.host != nil
        else { throw RequestBuildError.badBaseURL(base) }
        return url
    }

    static func json(_ object: [String: Any]) throws -> Data {
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}
