import Foundation
import GlanceCore

struct CloudError: LocalizedError {
    let status: Int
    let message: String

    var errorDescription: String? {
        switch status {
        case 401, 403: return "The AI service rejected the API key (\(status)). \(message)"
        case 429: return "The AI service says you're sending too many requests (429). \(message)"
        default: return "The AI service returned an error (\(status)): \(message)"
        }
    }
}

/// Sends what RequestBuilder builds. Uses the shared URLSession so the
/// connection to the service is reused between captures (no new handshake).
struct CloudClient: Sendable {
    let config: ServiceConfig
    let apiKey: String

    func analyze(jpegBase64: String, instructions: String) async throws -> String {
        do {
            return try await send(jpegBase64: jpegBase64, instructions: instructions, structured: true)
        } catch let error as CloudError where error.status == 400 {
            // Some services reject the "enforce this JSON shape" option. The
            // prompt asks for the same JSON anyway, so retry without it once.
            return try await send(jpegBase64: jpegBase64, instructions: instructions, structured: false)
        }
    }

    func listModels() async throws -> [String] {
        let request = try RequestBuilder.listModels(config: config, apiKey: apiKey)
        return RequestBuilder.extractModelIDs(from: try await perform(request))
    }

    private func send(jpegBase64: String, instructions: String, structured: Bool) async throws -> String {
        let request = try RequestBuilder.analysis(
            config: config,
            apiKey: apiKey,
            imageBase64JPEG: jpegBase64,
            instructions: instructions,
            structuredOutput: structured
        )
        let data = try await perform(request)
        return try RequestBuilder.extractText(format: config.format, from: data)
    }

    private func perform(_ built: BuiltRequest) async throws -> Data {
        var request = URLRequest(url: built.url, timeoutInterval: 60)
        request.httpMethod = built.method
        for (name, value) in built.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        request.httpBody = built.body

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let message = RequestBuilder.errorMessage(from: data) ?? "No details."
            throw CloudError(status: status, message: String(message.prefix(240)))
        }
        return data
    }
}
