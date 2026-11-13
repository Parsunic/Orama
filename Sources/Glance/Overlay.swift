import AppKit
import QuartzCore
import SwiftUI
import GlanceCore

/// Where to draw the faint dot.
struct DotPlacement {
    /// Fractions of the captured display, origin top-left.
    let normalized: CGPoint
    /// Dark dot on a light background, light dot on a dark one.
    let darkTone: Bool
    let snapped: Bool
}

/// A borderless, transparent, click-through window that floats above normal
/// windows on every Space (including full-screen apps) and never takes focus.
final class OverlayPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        ignoresMouseEvents = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

/// Draws the answer box and the dot. Showing fades in quickly (unless Reduce
/// Motion is on); hiding is always instant, so a hide shortcut leaves nothing
/// half-visible in a screenshot or a screen share.
@MainActor
final class OverlayController {
    private let bubbleHost = NSHostingView(rootView: AnswerBubble(content: .working))
    private lazy var bubblePanel: OverlayPanel = makeBubblePanel()
    private let dotView = DotView(frame: .zero)
    private lazy var dotPanel: OverlayPanel = makeDotPanel()

    func showBubble(_ content: BubbleContent, on screen: NSScreen?, corner: Corner) {
        guard let screen else { return }
        let panel = bubblePanel
        bubbleHost.rootView = AnswerBubble(content: content)
        let size = bubbleHost.fittingSize
        let origin = Geometry.panelOrigin(corner: corner, panelSize: size, visibleFrame: screen.visibleFrame, margin: 16)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        bubbleHost.frame = NSRect(origin: .zero, size: size)
        reveal(panel)
    }

    func showDot(_ dot: DotPlacement, on screen: NSScreen, opacity: Double, diameter: Double) {
        let panel = dotPanel
        panel.setFrame(screen.frame, display: false)
        dotView.frame = NSRect(origin: .zero, size: screen.frame.size)
        let center = Geometry.viewPoint(normalized: dot.normalized, in: screen.frame.size)
        dotView.place(
            center: center,
            diameter: CGFloat(diameter),
            color: dot.darkTone ? .black : .white,
            opacity: CGFloat(opacity)
        )
        reveal(panel)
    }

    func hideBubble() { bubblePanel.orderOut(nil) }
    func hideDot() { dotPanel.orderOut(nil) }

    func hideAll() {
        hideBubble()
        hideDot()
    }

    private func reveal(_ panel: NSPanel) {
        if panel.isVisible {
            panel.alphaValue = 1
            return
        }
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = animate ? 0 : 1
        panel.orderFrontRegardless()
        if animate {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.15
                panel.animator().alphaValue = 1
            }
        }
    }

    private func makeBubblePanel() -> OverlayPanel {
        let frame = NSRect(x: 0, y: 0, width: 200, height: 40)
        let panel = OverlayPanel(contentRect: frame)
        panel.hasShadow = true

        let background = NSVisualEffectView(frame: frame)
        background.material = .popover
        background.blendingMode = .behindWindow
        background.state = .active
        background.maskImage = Self.roundedMask(radius: 12)
        background.autoresizingMask = [.width, .height]

        bubbleHost.sizingOptions = []
        bubbleHost.frame = background.bounds
        bubbleHost.autoresizingMask = [.width, .height]
        background.addSubview(bubbleHost)
        panel.contentView = background
        return panel
    }

    private func makeDotPanel() -> OverlayPanel {
        let panel = OverlayPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
        panel.contentView = dotView
        return panel
    }

    /// A stretchable rounded-rectangle mask; the reliable way to round an NSVisualEffectView.
    private static func roundedMask(radius: CGFloat) -> NSImage {
        let edge = radius * 2 + 1
        let image = NSImage(size: NSSize(width: edge, height: edge), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
            return true
        }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

/// A soft round glow that fades to nothing at its edge, so there is no hard
/// ring to catch the eye and the pixels underneath stay readable.
final class DotView: NSView {
    private let glow = CAGradientLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        layer = CALayer()
        wantsLayer = true
        glow.type = .radial
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.locations = [0, 0.55, 1]
        layer?.addSublayer(glow)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    func place(center: CGPoint, diameter: CGFloat, color: NSColor, opacity: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        glow.frame = CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2, width: diameter, height: diameter)
        glow.colors = [
            color.withAlphaComponent(opacity).cgColor,
            color.withAlphaComponent(opacity * 0.6).cgColor,
            color.withAlphaComponent(0).cgColor,
        ]
        CATransaction.commit()
    }
}

enum BubbleContent: Equatable {
    case working
    case answer(String)
    case error(String)
}

struct AnswerBubble: View {
    let content: BubbleContent

    var body: some View {
        Group {
            switch content {
            case .working:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Looking…")
                }
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            case .answer(let text):
                Text(Self.rich(text))
                    .font(.system(size: 13))
                    .lineSpacing(2)
                    .lineLimit(20)
                    .frame(width: 320, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

            case .error(let message):
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(width: 280, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Supports **bold** and *italics* from the model; anything else stays plain.
    static func rich(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

extension NSScreen {
    var displayID: CGDirectDisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
    }

    static func withDisplayID(_ id: CGDirectDisplayID) -> NSScreen? {
        screens.first { $0.displayID == id }
    }

    /// The display the pointer is on: the one you are most likely looking at.
    static var underMouse: NSScreen? {
        let location = NSEvent.mouseLocation
        return screens.first { NSMouseInRect(location, $0.frame, false) } ?? main
    }
}
