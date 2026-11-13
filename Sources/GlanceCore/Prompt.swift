import Foundation

public enum Prompt {
    /// What the user asks for by default. Editable in the menu bar.
    public static let defaultInstructions = """
    Look at my screen and tell me the single most useful thing about what I'm working on: \
    an answer, a fix, or the next step. If one specific spot on screen matters most \
    (a button, a field, an error, or a design's focal point), point to it.
    """

    /// The fixed part. It defines the reply format the app parses, so it is not editable.
    public static let system = """
    You look at a screenshot of the user's screen and reply briefly.

    Reply with ONLY a JSON object, no code fences, with exactly these keys:
    - "text": your answer in plain sentences, at most about 80 words. **Bold** and *italics* are allowed.
    - "has_target": true only if one specific spot on the screen is the answer or clearly helps; otherwise false.
    - "x", "y": integers from 0 to 1000 giving the CENTER of that spot. x is measured from the left edge \
    of the screenshot (0) to the right edge (1000); y from the top edge (0) to the bottom edge (1000). \
    Use 0 for both when has_target is false.
    - "label": the visible text at that spot, copied exactly as it appears on screen, or "" if the spot has no text.
    """

    /// The same shape, as a JSON Schema for services that can enforce it.
    public static var answerSchema: [String: Any] {
        let string: [String: Any] = ["type": "string"]
        let integer: [String: Any] = ["type": "integer"]
        let boolean: [String: Any] = ["type": "boolean"]
        let properties: [String: Any] = [
            "text": string,
            "has_target": boolean,
            "x": integer,
            "y": integer,
            "label": string,
        ]
        return [
            "type": "object",
            "properties": properties,
            "required": ["text", "has_target", "x", "y", "label"],
            "additionalProperties": false,
        ]
    }
}
