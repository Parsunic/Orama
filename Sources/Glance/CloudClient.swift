import Foundation
import GlanceCore

struct CloudError: LocalizedError {
    let status: Int
    let message: String

    /// The service is overloaded or over a rate limit: worth trying a backup
    /// model or trying again, as opposed to a wrong key or a bad request.
    var isBusy: Bool {
        [429, 500, 502, 503, 504, 529].contains(status)
    }

    var errorDescription: String? {
        switch status {
        case 401, 403:
            return "The AI service rejected the API key (\(status)). \(message)"
        case 429:
            return "You've hit this model's request limit (429). Free-tier limits reset every minute and every day. Set a backup model in the menu so Glance can switch. \(message)"
        case 500, 502, 503, 504, 529:
            return "This model is overloaded right now (\(status)); free-tier requests are turned away first. Try again in a moment, or set a backup model in the menu."
        default:
            return "The AI service returned an error (\(status)): \(message)"
        }
    }
}

struct CloudReply: Sendable {
    let text: String
    /// The model that actually answered (the backup, if the main one was busy).
    let model: String
    let usedBackup: Bool
}

/// Sends what RequestBuilder builds. Uses the shared URLSession so the
/// connection to the service is reused between captures (no new handshake).
struct CloudClient: Sendable {
    let config: ServiceConfig
    let apiKey: String

    /// Asks the main model. If it is busy (overloaded or rate-limited), asks
    /// the backup model straight away; with no backup set, waits a second and
    /// asks the main model once more.
    func analyze(jpegBase64: String, instructions: String) async throws -> CloudReply {
        let main = config.model.trimmingCharacters(in: .whitespacesAndNewlines)
        let backup = config.backupModel.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let text = try await ask(model: main, jpegBase64: jpegBase64, instructions: instructions)
            return CloudReply(text: text, model: main, usedBackup: false)
        } catch let error as CloudError where error.isBusy {
            if !backup.isEmpty, backup != main {
                let text = try await ask(model: backup, jpegBase64: jpegBase64, instructions: instructions)
                return CloudReply(text: text, model: backup, usedBackup: true)
            }
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let text = try await ask(model: main, jpegBase64: jpegBase64, instructions: instructions)
            return CloudReply(text: text, model: main, usedBackup: false)
        }
    }

    private func ask(model: String, jpegBase64: String, instructions: String) async throws -> String {
        do {
            return try await send(model: model, jpegBase64: jpegBase64, instructions: instructions, structured: true)
        } catch let error as CloudError where error.status == 400 {
            // Some services reject the "enforce this JSON shape" option. The
            // prompt asks for the same JSON anyway, so retry without it once.
            return try await send(model: model, jpegBase64: jpegBase64, instructions: instructions, structured: false)
        }
    }

    func listModels() async throws -> [String] {
        let request = try RequestBuilder.listModels(config: config, apiKey: apiKey)
        return RequestBuilder.extractModelIDs(from: try await perform(request))
    }

    private func send(model: String, jpegBase64: String, instructions: String, structured: Bool) async throws -> String {
        var modelConfig = config
        modelConfig.model = model
        let request = try RequestBuilder.analysis(
            config: modelConfig,
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
