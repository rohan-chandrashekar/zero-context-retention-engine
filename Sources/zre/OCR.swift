import Foundation
import Vision
import CoreVideo

final class OCR {
    private let recognitionLevel: VNRequestTextRecognitionLevel
    private let usesLanguageCorrection: Bool
    private let minimumTextHeight: Float

    init(accurate: Bool, languageCorrection: Bool, minimumTextHeight: Float = 0.0) {
        self.recognitionLevel = accurate ? .accurate : .fast
        self.usesLanguageCorrection = languageCorrection
        self.minimumTextHeight = minimumTextHeight
    }

    func recognize(_ pixelBuffer: CVPixelBuffer) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = recognitionLevel
        request.usesLanguageCorrection = usesLanguageCorrection
        request.minimumTextHeight = minimumTextHeight

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }

        guard let observations = request.results else { return "" }
        var lines: [String] = []
        lines.reserveCapacity(observations.count)
        for observation in observations {
            if let candidate = observation.topCandidates(1).first {
                lines.append(candidate.string)
            }
        }
        return lines.joined(separator: "\n")
    }
}
