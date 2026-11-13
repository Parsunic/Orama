import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// A piece of text the Mac read off the screenshot, in normalized top-left coordinates.
public struct TextBox: Equatable, Sendable {
    public var text: String
    public var rect: CGRect

    public init(text: String, rect: CGRect) {
        self.text = text
        self.rect = rect
    }
}

public struct SnapResult: Equatable, Sendable {
    public var point: CGPoint
    public var snapped: Bool

    public init(point: CGPoint, snapped: Bool) {
        self.point = point
        self.snapped = snapped
    }
}

/// Vision models are good at saying WHAT to look at and only roughly right
/// about WHERE. The Mac's own text recogniser is exact about where words are.
/// So when the model names the visible text at its target, we move the dot
/// onto that text:
///
/// 1. An exact match (ignoring case and punctuation) wins. If the same text
///    appears several times, the one nearest the model's guess wins. Exact
///    matches are trusted at any distance: the label is usually right even
///    when the coordinates are off.
/// 2. Otherwise a close match (allowing for a misread letter or two) wins, but
///    only near the guess, because a loose match far away is more likely to be
///    a different element than a correction.
/// 3. Otherwise the model's own guess stands.
public enum TextSnap {
    public static let fuzzyThreshold = 0.8
    /// Measured in screen heights.
    public static let maxFuzzyDistance = 0.15

    /// - Parameter aspect: screenshot width / height, so distances are measured
    ///   in the same units horizontally and vertically.
    public static func snap(_ target: ScreenTarget, boxes: [TextBox], aspect: Double) -> SnapResult {
        let guess = CGPoint(x: target.x, y: target.y)
        let label = normalize(target.label)
        guard !label.isEmpty, !boxes.isEmpty else { return SnapResult(point: guess, snapped: false) }

        func distance(_ box: TextBox) -> Double {
            let c = Geometry.center(of: box.rect)
            let dx = (Double(c.x) - target.x) * aspect
            let dy = Double(c.y) - target.y
            return (dx * dx + dy * dy).squareRoot()
        }

        let exact = boxes.filter { normalize($0.text) == label }
        if let best = exact.min(by: { distance($0) < distance($1) }) {
            return SnapResult(point: Geometry.center(of: best.rect), snapped: true)
        }

        let labelLength = label.count
        let fuzzy = boxes.filter { box in
            let text = normalize(box.text)
            guard !text.isEmpty, abs(text.count - labelLength) <= max(2, labelLength / 3) else { return false }
            return similarity(text, label) >= fuzzyThreshold && distance(box) <= maxFuzzyDistance
        }
        if let best = fuzzy.min(by: { distance($0) < distance($1) }) {
            return SnapResult(point: Geometry.center(of: best.rect), snapped: true)
        }

        return SnapResult(point: guess, snapped: false)
    }

    /// Lowercase, letters and digits only, single spaces.
    public static func normalize(_ s: String) -> String {
        let mapped = s.lowercased().unicodeScalars.map { scalar -> Character in
            CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
        }
        return String(mapped).split(separator: " ").joined(separator: " ")
    }

    /// 1 means identical, 0 means nothing in common (edit distance based).
    public static func similarity(_ a: String, _ b: String) -> Double {
        let longest = max(a.count, b.count)
        guard longest > 0 else { return 1 }
        return 1 - Double(editDistance(Array(a), Array(b))) / Double(longest)
    }

    static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        if a.isEmpty { return b.count }
        if b.isEmpty { return a.count }
        var previous = Array(0...b.count)
        var current = [Int](repeating: 0, count: b.count + 1)
        for i in 1...a.count {
            current[0] = i
            for j in 1...b.count {
                let cost = a[i - 1] == b[j - 1] ? 0 : 1
                current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
            }
            swap(&previous, &current)
        }
        return previous[b.count]
    }
}
