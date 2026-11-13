import XCTest
@testable import GlanceCore

final class RequestBuilderTests: XCTestCase {
    private func body(_ request: BuiltRequest) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
    }

    func testOpenAIStyleRequest() throws {
        let config = ServicePresets.preset(id: "gemini-lite").config
        let request = try RequestBuilder.analysis(config: config, apiKey: "k", imageBase64JPEG: "AAAA", instructions: "What is this?", structuredOutput: true)
        XCTAssertEqual(request.url.absoluteString, "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        XCTAssertEqual(request.headers["Authorization"], "Bearer k")
        let json = try body(request)
        XCTAssertEqual(json["model"] as? String, "gemini-flash-lite-latest")
        XCTAssertNotNil(json["response_format"])
        XCTAssertNil(json["reasoning_effort"], "blank effort must not be sent")
        let messages = try XCTUnwrap(json["messages"] as? [[String: Any]])
        let parts = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        let image = try XCTUnwrap(parts[1]["image_url"] as? [String: Any])
        XCTAssertEqual(image["url"] as? String, "data:image/jpeg;base64,AAAA")
    }

    func testRetryWithoutStructuredOutputDropsTheOption() throws {
        let config = ServicePresets.preset(id: "groq").config
        let request = try RequestBuilder.analysis(config: config, apiKey: "k", imageBase64JPEG: "AAAA", instructions: "", structuredOutput: false)
        XCTAssertNil(try body(request)["response_format"])
    }

    func testClaudeRequest() throws {
        let config = ServicePresets.preset(id: "anthropic").config
        let request = try RequestBuilder.analysis(config: config, apiKey: "k", imageBase64JPEG: "AAAA", instructions: "Q", structuredOutput: true)
        XCTAssertEqual(request.url.absoluteString, "https://api.anthropic.com/v1/messages")
        XCTAssertEqual(request.headers["x-api-key"], "k")
        XCTAssertEqual(request.headers["anthropic-version"], RequestBuilder.anthropicVersion)
        XCTAssertEqual(request.headers["anthropic-beta"], RequestBuilder.fallbackBeta)
        let json = try body(request)
        XCTAssertEqual(json["fallbacks"] as? String, "default")
        XCTAssertNil(json["thinking"])
        XCTAssertNil(json["temperature"])
        let output = try XCTUnwrap(json["output_config"] as? [String: Any])
        XCTAssertEqual(output["effort"] as? String, "low")
        XCTAssertNotNil(output["format"])
    }

    func testClaudeModelWithoutFallbackSupportSendsNoFallbackParameter() throws {
        var config = ServicePresets.preset(id: "anthropic").config
        config.model = "claude-haiku-5-5"
        let request = try RequestBuilder.analysis(config: config, apiKey: "k", imageBase64JPEG: "AAAA", instructions: "Q", structuredOutput: true)
        XCTAssertNil(request.headers["anthropic-beta"])
        XCTAssertNil(try body(request)["fallbacks"])
    }

    func testTrailingSlashAndBadAddress() throws {
        var config = ServicePresets.preset(id: "openai").config
        config.baseURL = "https://api.openai.com/v1///"
        XCTAssertEqual(try RequestBuilder.analysis(config: config, apiKey: "k", imageBase64JPEG: "A", instructions: "", structuredOutput: false).url.absoluteString,
                       "https://api.openai.com/v1/chat/completions")
        config.baseURL = "not a url"
        XCTAssertThrowsError(try RequestBuilder.analysis(config: config, apiKey: "k", imageBase64JPEG: "A", instructions: "", structuredOutput: false))
    }

    func testMissingModel() {
        var config = ServicePresets.preset(id: "custom").config
        config.baseURL = "http://localhost:11434/v1"
        XCTAssertThrowsError(try RequestBuilder.analysis(config: config, apiKey: "", imageBase64JPEG: "A", instructions: "", structuredOutput: false)) { error in
            XCTAssertEqual(error as? RequestBuildError, .missingModel)
        }
    }

    func testExtractOpenAIText() throws {
        let data = Data(#"{"choices":[{"message":{"role":"assistant","content":"{\"text\":\"hi\"}"}}]}"#.utf8)
        XCTAssertEqual(try RequestBuilder.extractText(format: .openAI, from: data), #"{"text":"hi"}"#)
    }

    func testExtractClaudeTextSkipsThinkingBlocks() throws {
        let data = Data(#"{"stop_reason":"end_turn","content":[{"type":"thinking","thinking":""},{"type":"text","text":"answer"}]}"#.utf8)
        XCTAssertEqual(try RequestBuilder.extractText(format: .anthropic, from: data), "answer")
    }

    func testClaudeRefusal() {
        let data = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        XCTAssertThrowsError(try RequestBuilder.extractText(format: .anthropic, from: data)) { error in
            XCTAssertEqual(error as? ResponseError, .refused(nil))
        }
    }

    func testErrorMessageShapes() {
        XCTAssertEqual(RequestBuilder.errorMessage(from: Data(#"{"error":{"message":"bad key"}}"#.utf8)), "bad key")
        XCTAssertEqual(RequestBuilder.errorMessage(from: Data(#"[{"error":{"message":"gemini style"}}]"#.utf8)), "gemini style")
        XCTAssertEqual(RequestBuilder.errorMessage(from: Data("Bad Gateway".utf8)), "Bad Gateway")
    }

    func testModelIDs() {
        let data = Data(#"{"data":[{"id":"models/gemini-b"},{"id":"a-model"}]}"#.utf8)
        XCTAssertEqual(RequestBuilder.extractModelIDs(from: data), ["a-model", "gemini-b"])
    }
}
