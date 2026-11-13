import XCTest
@testable import GlanceCore

/// The hotkey behaviour, exactly as described: one key captures, the other is
/// an on/off switch for what is drawn.
final class OverlayModelTests: XCTestCase {
    let answer = Answer(text: "Hi", target: nil)

    func testCaptureShowsNothingWhileTheScreenshotIsTaken() {
        var model = OverlayModel()
        let id = model.beginCapture()
        XCTAssertEqual(model.visible, .nothing)
        model.captured(id: id)
        XCTAssertEqual(model.visible, .working)
        model.finish(id: id, answer: answer)
        XCTAssertEqual(model.visible, .answer(answer))
    }

    func testNewCaptureRemovesTheOldAnswerImmediately() {
        var model = OverlayModel()
        let first = model.beginCapture()
        model.captured(id: first)
        model.finish(id: first, answer: answer)
        _ = model.beginCapture()
        XCTAssertEqual(model.visible, .nothing)
        XCTAssertNil(model.currentAnswer)
    }

    func testSwitchOffHidesEverythingAndAnswerArrivesHidden() {
        var model = OverlayModel()
        let id = model.beginCapture()
        model.captured(id: id)
        model.toggleSwitch() // off while waiting
        XCTAssertEqual(model.visible, .nothing)
        model.finish(id: id, answer: answer)
        XCTAssertEqual(model.visible, .nothing, "an answer must not appear while the switch is off")
        model.toggleSwitch() // back on later
        XCTAssertEqual(model.visible, .answer(answer))
    }

    func testCaptureWhileSwitchIsOffStaysHidden() {
        var model = OverlayModel(switchOn: false)
        let id = model.beginCapture()
        model.captured(id: id)
        model.finish(id: id, answer: answer)
        XCTAssertEqual(model.visible, .nothing)
        model.setSwitch(true)
        XCTAssertEqual(model.visible, .answer(answer))
    }

    func testLateReplyToAnOldCaptureIsIgnored() {
        var model = OverlayModel()
        let old = model.beginCapture()
        model.captured(id: old)
        let new = model.beginCapture()
        XCTAssertFalse(model.finish(id: old, answer: Answer(text: "stale", target: nil)))
        XCTAssertFalse(model.fail(id: old, message: "stale"))
        XCTAssertEqual(model.phase, .capturing(id: new))
    }

    func testFailureIsShownLikeAnAnswer() {
        var model = OverlayModel()
        let id = model.beginCapture()
        model.fail(id: id, message: "Offline")
        XCTAssertEqual(model.visible, .error("Offline"))
        model.toggleSwitch()
        XCTAssertEqual(model.visible, .nothing)
    }
}
