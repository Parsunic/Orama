import XCTest
@testable import GlanceCore

final class AnswerParserTests: XCTestCase {
    func testPlainJSONWithTarget() {
        let answer = AnswerParser.parse(#"{"text":"Click Save.","has_target":true,"x":500,"y":250,"label":"Save"}"#)
        XCTAssertEqual(answer.text, "Click Save.")
        XCTAssertEqual(answer.target, ScreenTarget(x: 0.5, y: 0.25, label: "Save"))
    }

    func testCodeFenceAndPreambleAreIgnored() {
        let raw = """
        Sure, here you go:
        ```json
        {"text": "Looks fine.", "has_target": false, "x": 0, "y": 0, "label": ""}
        ```
        """
        let answer = AnswerParser.parse(raw)
        XCTAssertEqual(answer.text, "Looks fine.")
        XCTAssertNil(answer.target)
    }

    func testNotJSONFallsBackToPlainText() {
        let answer = AnswerParser.parse("  The button is greyed out because the form is invalid.  ")
        XCTAssertEqual(answer.text, "The button is greyed out because the form is invalid.")
        XCTAssertNil(answer.target)
    }

    func testFractionalCoordinatesAreAccepted() {
        let answer = AnswerParser.parse(#"{"text":"Here","has_target":true,"x":0.25,"y":0.75,"label":""}"#)
        XCTAssertEqual(answer.target?.x ?? -1, 0.25, accuracy: 1e-9)
        XCTAssertEqual(answer.target?.y ?? -1, 0.75, accuracy: 1e-9)
    }

    func testCoordinatesAreClampedToTheScreen() {
        let answer = AnswerParser.parse(#"{"text":"Edge","has_target":true,"x":1400,"y":-20,"label":""}"#)
        XCTAssertEqual(answer.target?.x, 1)
        XCTAssertEqual(answer.target?.y, 0)
    }

    func testStringNumbersAndBoolean() {
        let answer = AnswerParser.parse(#"{"text":"t","has_target":"true","x":"100","y":"900","label":"OK"}"#)
        XCTAssertEqual(answer.target?.x ?? -1, 0.1, accuracy: 1e-9)
        XCTAssertEqual(answer.target?.y ?? -1, 0.9, accuracy: 1e-9)
    }

    func testHasTargetFalseDropsCoordinates() {
        let answer = AnswerParser.parse(#"{"text":"No spot.","has_target":false,"x":300,"y":300,"label":"Save"}"#)
        XCTAssertNil(answer.target)
    }

    func testEmptyTextFallsBackToLabel() {
        let answer = AnswerParser.parse(#"{"text":"","has_target":true,"x":10,"y":10,"label":"Export"}"#)
        XCTAssertEqual(answer.text, "Export")
    }
}
