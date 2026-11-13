import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// One spot on the captured screenshot. `x` and `y` are fractions of the
/// image (0...1) measured from the TOP-LEFT corner, so they do not depend on
/// Retina scale, image size or which display was captured.
public struct ScreenTarget: Equatable, Sendable {
    public var x: Double
    public var y: Double
    /// The exact visible text at that spot, as the model copied it ("" if none).
    public var label: String

    public init(x: Double, y: Double, label: String) {
        self.x = x
        self.y = y
        self.label = label
    }
}

/// What the model told us about the screen.
public struct Answer: Equatable, Sendable {
    public var text: String
    public var target: ScreenTarget?

    public init(text: String, target: ScreenTarget?) {
        self.text = text
        self.target = target
    }
}

/// Turns the model's raw reply into an `Answer`.
///
/// We ask for strict JSON, but some services ignore that option, wrap the JSON
/// in a ```json fence, or add a sentence before it. So this parser is lenient:
/// it finds the outermost `{ ... }`, and if there is no usable JSON at all it
/// shows the whole reply as plain text rather than failing.
public enum AnswerParser {
    public static func parse(_ raw: String) -> Answer {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let json = jsonObject(in: trimmed) else {
            return Answer(text: trimmed, target: nil)
        }

        let text = (json["text"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var target: ScreenTarget?
        if bool(json["has_target"]) == true, let x = double(json["x"]), let y = double(json["y"]) {
            let point = normalizedPoint(x: x, y: y)
            let label = (json["label"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            target = ScreenTarget(x: point.x, y: point.y, label: label)
        }

        let finalText: String
        if !text.isEmpty {
            finalText = text
        } else if let label = target?.label, !label.isEmpty {
            finalText = label
        } else {
            finalText = trimmed
        }
        return Answer(text: finalText, target: target)
    }

    /// The prompt asks for integers on a 0...1000 grid. Some models answer in
    /// fractions (0...1) anyway, so accept both: values that are all <= 1 and
    /// not whole numbers are fractions; everything else is the 0...1000 grid.
    public static func normalizedPoint(x: Double, y: Double) -> (x: Double, y: Double) {
        let looksFractional = x <= 1 && y <= 1 && (x != x.rounded() || y != y.rounded())
        let scale = looksFractional ? 1.0 : 1000.0
        return (clamp01(x / scale), clamp01(y / scale))
    }

    static func jsonObject(in text: String) -> [String: Any]? {
        guard let start = text.firstIndex(of: "{"),
              let end = text.lastIndex(of: "}"),
              start < end
        else { return nil }
        let slice = String(text[start...end])
        guard let data = slice.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        return object
    }

    static func double(_ value: Any?) -> Double? {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let n = value as? NSNumber { return n.doubleValue }
        if let s = value as? String { return Double(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }

    static func bool(_ value: Any?) -> Bool? {
        if let b = value as? Bool { return b }
        if let s = value as? String { return s.lowercased() == "true" }
        return nil
    }

    static func clamp01(_ v: Double) -> Double {
        guard v.isFinite else { return 0 }
        return min(1, max(0, v))
    }
}
