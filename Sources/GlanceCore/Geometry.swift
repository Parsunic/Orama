import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

public enum Corner: String, CaseIterable, Codable, Sendable {
    case topLeft, topRight, bottomLeft, bottomRight

    public var title: String {
        switch self {
        case .topLeft: return "Top left"
        case .topRight: return "Top right"
        case .bottomLeft: return "Bottom left"
        case .bottomRight: return "Bottom right"
        }
    }
}

/// Coordinate conversions. There are three conventions in play:
///
/// * NORMALIZED: fractions 0...1 of the screenshot, origin TOP-left. This is
///   what the model and our text boxes use, and it makes Retina scale vanish:
///   a full-display capture maps 1:1 onto that display's frame in points.
/// * COCOA: AppKit's global screen space in points, origin BOTTOM-left of the
///   primary display, y pointing up. NSScreen.frame and NSWindow frames use it.
/// * VISION: the text recogniser's normalized space, origin BOTTOM-left.
public enum Geometry {
    /// A rectangle from the Vision framework (origin bottom-left) to normalized
    /// top-left coordinates.
    public static func topLeftRect(fromVision r: CGRect) -> CGRect {
        CGRect(x: r.minX, y: 1 - r.maxY, width: r.width, height: r.height)
    }

    /// A normalized point to a position inside a non-flipped view of `size`
    /// (origin bottom-left), e.g. the full-screen dot view.
    public static func viewPoint(normalized p: CGPoint, in size: CGSize) -> CGPoint {
        CGPoint(x: p.x * size.width, y: (1 - p.y) * size.height)
    }

    /// A normalized point on a captured display to global Cocoa coordinates.
    public static func screenPoint(normalized p: CGPoint, screenFrame f: CGRect) -> CGPoint {
        CGPoint(x: f.minX + p.x * f.width, y: f.maxY - p.y * f.height)
    }

    /// The inverse of `screenPoint`.
    public static func normalized(screenPoint p: CGPoint, screenFrame f: CGRect) -> CGPoint {
        guard f.width > 0, f.height > 0 else { return CGPoint(x: 0.5, y: 0.5) }
        return CGPoint(x: (p.x - f.minX) / f.width, y: (f.maxY - p.y) / f.height)
    }

    public static func center(of r: CGRect) -> CGPoint {
        CGPoint(x: r.midX, y: r.midY)
    }

    /// Size to shrink a screenshot to before upload, keeping its shape.
    public static func fittedPixelSize(width: Int, height: Int, maxLongEdge: Int) -> (width: Int, height: Int) {
        let longEdge = max(width, height)
        guard maxLongEdge > 0, longEdge > maxLongEdge else { return (width, height) }
        let scale = Double(maxLongEdge) / Double(longEdge)
        let w = max(1, Int((Double(width) * scale).rounded()))
        let h = max(1, Int((Double(height) * scale).rounded()))
        return (w, h)
    }

    /// Bottom-left origin for the answer box, `margin` points in from the
    /// chosen corner of `visibleFrame` (the screen minus menu bar and Dock).
    public static func panelOrigin(corner: Corner, panelSize s: CGSize, visibleFrame v: CGRect, margin m: CGFloat) -> CGPoint {
        switch corner {
        case .topLeft: return CGPoint(x: v.minX + m, y: v.maxY - m - s.height)
        case .topRight: return CGPoint(x: v.maxX - m - s.width, y: v.maxY - m - s.height)
        case .bottomLeft: return CGPoint(x: v.minX + m, y: v.minY + m)
        case .bottomRight: return CGPoint(x: v.maxX - m - s.width, y: v.minY + m)
        }
    }
}
