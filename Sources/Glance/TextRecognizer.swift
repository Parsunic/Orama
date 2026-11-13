import CoreGraphics
import Vision
import GlanceCore

/// Reads the text on a screenshot with Apple's on-device recogniser. Free, no
/// network, no extra permission. Returns a box for every line AND for every
/// word in it, so a one-word button label can be matched exactly.
enum TextRecognizer {
    static func boxes(in image: CGImage) -> [TextBox] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return []
        }

        var boxes: [TextBox] = []
        for observation in request.results ?? [] {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let line = candidate.string
            boxes.append(TextBox(text: line, rect: Geometry.topLeftRect(fromVision: observation.boundingBox)))

            line.enumerateSubstrings(in: line.startIndex..<line.endIndex, options: .byWords) { word, range, _, _ in
                guard let word, word != line,
                      let wordBox = try? candidate.boundingBox(for: range)
                else { return }
                boxes.append(TextBox(text: word, rect: Geometry.topLeftRect(fromVision: wordBox.boundingBox)))
            }
        }
        return boxes
    }
}
