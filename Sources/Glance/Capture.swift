import AppKit
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers
import GlanceCore

struct Screenshot {
    /// Full resolution, used for reading on-screen text and for the dot's tone.
    let image: CGImage
    /// Shrunk JPEG for upload.
    let jpegBase64: String
    /// Width / height.
    let aspect: Double
}

enum CaptureError: LocalizedError {
    case noPermission
    case displayGone
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "Glance needs Screen Recording permission. Open the menu bar icon to turn it on."
        case .displayGone:
            return "That display was disconnected."
        case .encodeFailed:
            return "Couldn't prepare the screenshot."
        }
    }
}

enum CaptureService {
    /// One still frame of a whole display, with Glance's own windows left out
    /// so it never analyses its own answer box.
    static func capture(displayID: CGDirectDisplayID, maxLongEdge: Int) async throws -> Screenshot {
        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            if !CGPreflightScreenCaptureAccess() {
                _ = CGRequestScreenCaptureAccess() // shows the system prompt the first time
                throw CaptureError.noPermission
            }
            throw error
        }

        guard let display = content.displays.first(where: { $0.displayID == displayID }) else {
            throw CaptureError.displayGone
        }
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let ownApp = content.applications.filter { $0.processID == ownPID }
        let filter = SCContentFilter(display: display, excludingApplications: ownApp, exceptingWindows: [])

        let config = SCStreamConfiguration()
        let scale = CGFloat(filter.pointPixelScale)
        config.width = max(1, Int(filter.contentRect.width * scale))
        config.height = max(1, Int(filter.contentRect.height * scale))
        config.showsCursor = false

        let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
        guard let jpeg = ImageTools.jpegBase64(image, maxLongEdge: maxLongEdge, quality: 0.72) else {
            throw CaptureError.encodeFailed
        }
        return Screenshot(image: image, jpegBase64: jpeg, aspect: Double(image.width) / Double(max(1, image.height)))
    }
}

enum ImageTools {
    /// Shrinks to `maxLongEdge` pixels on the longer side and encodes as JPEG.
    /// Smaller images upload faster; too small and tiny UI text becomes unreadable.
    static func jpegBase64(_ image: CGImage, maxLongEdge: Int, quality: Double) -> String? {
        let size = Geometry.fittedPixelSize(width: image.width, height: image.height, maxLongEdge: maxLongEdge)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: size.width, height: size.height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: size.width, height: size.height))
        guard let scaled = context.makeImage() else { return nil }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, UTType.jpeg.identifier as CFString, 1, nil) else {
            return nil
        }
        let options = [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary
        CGImageDestinationAddImage(destination, scaled, options)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return (data as Data).base64EncodedString()
    }

    /// Average brightness (0 dark ... 1 light) of a small patch around a
    /// normalized point. The overlay cannot blend with other apps' pixels, so
    /// the dot picks a dark or light tone from the screenshot instead.
    static func brightness(of image: CGImage, around point: CGPoint) -> Double? {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)
        let radius = max(4, 0.02 * max(width, height))
        let patch = CGRect(x: point.x * width - radius, y: point.y * height - radius, width: 2 * radius, height: 2 * radius)
            .integral
            .intersection(CGRect(x: 0, y: 0, width: width, height: height))
        // CGImage cropping uses top-left pixel coordinates, matching our normalized space.
        guard !patch.isEmpty, let crop = image.cropping(to: patch) else { return nil }

        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .medium
            context.draw(crop, in: CGRect(x: 0, y: 0, width: 1, height: 1))
            return true
        }
        guard drawn else { return nil }
        return (0.2126 * Double(pixel[0]) + 0.7152 * Double(pixel[1]) + 0.0722 * Double(pixel[2])) / 255
    }

    /// A small grey square for the speed test.
    static let testImageBase64: String = {
        guard let context = CGContext(
            data: nil, width: 64, height: 64, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)
        else { return "" }
        context.setFillColor(CGColor(gray: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
        guard let image = context.makeImage() else { return "" }
        return jpegBase64(image, maxLongEdge: 64, quality: 0.8) ?? ""
    }()
}
