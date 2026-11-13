import Foundation

/// The two wire formats Glance speaks.
///
/// `openAI` is the "chat completions" format that OpenAI, Google Gemini (via
/// its compatibility address), Groq, OpenRouter, LM Studio and Ollama all
/// accept, so one client covers almost every service. `anthropic` is Claude's
/// own Messages API.
public enum APIFormat: String, Codable, CaseIterable, Sendable {
    case openAI
    case anthropic
}

/// Everything needed to talk to one service except the key.
public struct ServiceConfig: Equatable, Sendable {
    public var format: APIFormat
    public var baseURL: String
    public var model: String
    /// Sent as `reasoning_effort` (OpenAI format) or `output_config.effort`
    /// (Claude). Blank means "do not send it" for the OpenAI format and "low"
    /// for Claude, the fastest setting there.
    public var reasoningEffort: String
    /// Tried instead when the main model is overloaded or over its limit
    /// (HTTP 429/5xx). Blank means "wait a moment and retry the main model".
    public var backupModel: String

    public init(format: APIFormat, baseURL: String, model: String, reasoningEffort: String, backupModel: String = "") {
        self.format = format
        self.baseURL = baseURL
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.backupModel = backupModel
    }
}

public struct ServicePreset: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let format: APIFormat
    public let baseURL: String
    public let model: String
    public let reasoningEffort: String
    public let backupModel: String
    public let note: String

    public init(id: String, name: String, format: APIFormat, baseURL: String, model: String,
                reasoningEffort: String, backupModel: String = "", note: String) {
        self.id = id
        self.name = name
        self.format = format
        self.baseURL = baseURL
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.backupModel = backupModel
        self.note = note
    }

    public var config: ServiceConfig {
        ServiceConfig(format: format, baseURL: baseURL, model: model, reasoningEffort: reasoningEffort, backupModel: backupModel)
    }
}

/// Starting points. Every field stays editable, and "List" in the menu fetches
/// the service's real model names, because model names change often.
public enum ServicePresets {
    public static let defaultID = "gemini-lite"

    public static let all: [ServicePreset] = [
        ServicePreset(
            id: "gemini-lite",
            name: "Google Gemini",
            format: .openAI,
            baseURL: "https://generativelanguage.googleapis.com/v1beta/openai",
            model: "gemini-flash-lite-latest",
            reasoningEffort: "",
            backupModel: "gemini-flash-lite-latest",
            note: "Fast and reads images well. Free keys at aistudio.google.com; free-tier requests are the first turned away when a model is busy, so keep a backup model set."
        ),
        ServicePreset(
            id: "groq",
            name: "Groq",
            format: .openAI,
            baseURL: "https://api.groq.com/openai/v1",
            model: "meta-llama/llama-4-scout-17b-16e-instruct",
            reasoningEffort: "",
            note: "Very fast servers. Pick a model that accepts images (use List)."
        ),
        ServicePreset(
            id: "openai",
            name: "OpenAI",
            format: .openAI,
            baseURL: "https://api.openai.com/v1",
            model: "gpt-4.1-mini",
            reasoningEffort: "",
            note: "Use List to see the models your key can use."
        ),
        ServicePreset(
            id: "openrouter",
            name: "OpenRouter",
            format: .openAI,
            baseURL: "https://openrouter.ai/api/v1",
            model: "google/gemini-2.5-flash-lite",
            reasoningEffort: "",
            note: "One key for many providers. Use List to pick a model."
        ),
        ServicePreset(
            id: "anthropic",
            name: "Anthropic Claude",
            format: .anthropic,
            baseURL: "https://api.anthropic.com/v1",
            model: "claude-opus-5-5",
            reasoningEffort: "low",
            note: "Claude's own API. \"low\" thinking keeps it as quick as it gets."
        ),
        ServicePreset(
            id: "custom",
            name: "Custom (OpenAI-style)",
            format: .openAI,
            baseURL: "",
            model: "",
            reasoningEffort: "",
            note: "Any service with an OpenAI-style address, e.g. http://localhost:11434/v1 for Ollama."
        ),
    ]

    public static func preset(id: String) -> ServicePreset {
        all.first { $0.id == id } ?? all[0]
    }
}
