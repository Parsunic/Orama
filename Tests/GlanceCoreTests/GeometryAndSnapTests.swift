import XCTest
@testable import GlanceCore

final class GeometryTests: XCTestCase {
    func testVisionRectIsFlippedToTopLeft() {
        let r = Geometry.topLeftRect(fromVision: CGRect(x: 0.1, y: 0.7, width: 0.2, height: 0.1))
        XCTAssertEqual(r.minX, 0.1, accuracy: 1e-9)
        XCTAssertEqual(r.minY, 0.2, accuracy: 1e-9)
        XCTAssertEqual(r.width, 0.2, accuracy: 1e-9)
        XCTAssertEqual(r.height, 0.1, accuracy: 1e-9)
    }

    func testViewPointFlipsY() {
        let p = Geometry.viewPoint(normalized: CGPoint(x: 0.25, y: 0.1), in: CGSize(width: 1000, height: 500))
        XCTAssertEqual(p.x, 250, accuracy: 1e-9)
        XCTAssertEqual(p.y, 450, accuracy: 1e-9)
    }

    /// A second display placed LEFT of and lower than the main one has a
    /// negative origin in Cocoa space. Retina scale never appears here, because
    /// everything is in fractions and points.
    func testScreenPointOnASecondDisplayWithNegativeOrigin() {
        let frame = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let p = Geometry.screenPoint(normalized: CGPoint(x: 0.5, y: 0), screenFrame: frame)
        XCTAssertEqual(p.x, -960, accuracy: 1e-9)
        XCTAssertEqual(p.y, 780, accuracy: 1e-9) // top edge = maxY
        let back = Geometry.normalized(screenPoint: p, screenFrame: frame)
        XCTAssertEqual(back.x, 0.5, accuracy: 1e-9)
        XCTAssertEqual(back.y, 0, accuracy: 1e-9)
    }

    func testFittedPixelSizeKeepsShape() {
        let s = Geometry.fittedPixelSize(width: 5120, height: 2880, maxLongEdge: 1280)
        XCTAssertEqual(s.width, 1280)
        XCTAssertEqual(s.height, 720)
        let small = Geometry.fittedPixelSize(width: 800, height: 600, maxLongEdge: 1280)
        XCTAssertEqual(small.width, 800)
        XCTAssertEqual(small.height, 600)
    }

    func testPanelOriginCorners() {
        let visible = CGRect(x: 0, y: 80, width: 1440, height: 795)
        let size = CGSize(width: 300, height: 100)
        XCTAssertEqual(Geometry.panelOrigin(corner: .bottomRight, panelSize: size, visibleFrame: visible, margin: 16), CGPoint(x: 1124, y: 96))
        XCTAssertEqual(Geometry.panelOrigin(corner: .topLeft, panelSize: size, visibleFrame: visible, margin: 16), CGPoint(x: 16, y: 759))
    }
}

final class TextSnapTests: XCTestCase {
    private func box(_ text: String, x: Double, y: Double) -> TextBox {
        TextBox(text: text, rect: CGRect(x: x - 0.02, y: y - 0.01, width: 0.04, height: 0.02))
    }

    func testNormalizeIgnoresCaseAndPunctuation() {
        XCTAssertEqual(TextSnap.normalize("  Save As…  "), "save as")
        XCTAssertEqual(TextSnap.normalize("Export: PNG!"), "export png")
    }

    func testExactMatchSnapsEvenWhenTheGuessIsFarOff() {
        let target = ScreenTarget(x: 0.2, y: 0.2, label: "Export")
        let result = TextSnap.snap(target, boxes: [box("Cancel", x: 0.5, y: 0.5), box("Export", x: 0.8, y: 0.9)], aspect: 16.0 / 9.0)
        XCTAssertTrue(result.snapped)
        XCTAssertEqual(result.point.x, 0.8, accuracy: 1e-9)
        XCTAssertEqual(result.point.y, 0.9, accuracy: 1e-9)
    }

    func testRepeatedTextPicksTheOneNearestTheGuess() {
        let target = ScreenTarget(x: 0.7, y: 0.3, label: "OK")
        let result = TextSnap.snap(target, boxes: [box("OK", x: 0.1, y: 0.3), box("OK", x: 0.72, y: 0.31)], aspect: 1.6)
        XCTAssertEqual(result.point.x, 0.72, accuracy: 1e-9)
    }

    func testMisreadTextSnapsOnlyWhenNearby() {
        let near = ScreenTarget(x: 0.5, y: 0.5, label: "Settings")
        let misread = box("Setlings", x: 0.52, y: 0.5)
        XCTAssertTrue(TextSnap.snap(near, boxes: [misread], aspect: 1.6).snapped)

        let far = ScreenTarget(x: 0.1, y: 0.1, label: "Settings")
        XCTAssertFalse(TextSnap.snap(far, boxes: [misread], aspect: 1.6).snapped)
    }

    func testNoLabelKeepsTheGuess() {
        let target = ScreenTarget(x: 0.3, y: 0.4, label: "")
        let result = TextSnap.snap(target, boxes: [box("Anything", x: 0.3, y: 0.4)], aspect: 1.6)
        XCTAssertFalse(result.snapped)
        XCTAssertEqual(result.point, CGPoint(x: 0.3, y: 0.4))
    }
}
