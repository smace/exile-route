import CoreGraphics
import CoreVideo
import ImageIO
import Vision

enum VisionTextRecognizer {
    static func recognize(
        pixelBuffer: CVPixelBuffer,
        regionOfInterest: CGRect,
        customWords: [String]
    ) throws -> [OCRCandidate] {
        let request = configuredRequest(regionOfInterest: regionOfInterest, customWords: customWords)
        try VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up).perform([request])
        return candidates(from: request)
    }

    static func recognize(
        cgImage: CGImage,
        regionOfInterest: CGRect = CGRect(x: 0, y: 0, width: 1, height: 1),
        customWords: [String]
    ) throws -> [OCRCandidate] {
        let request = configuredRequest(regionOfInterest: regionOfInterest, customWords: customWords)
        try VNImageRequestHandler(cgImage: cgImage, orientation: .up).perform([request])
        return candidates(from: request)
    }

    private static func configuredRequest(regionOfInterest: CGRect, customWords: [String]) -> VNRecognizeTextRequest {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = ["en-US"]
        request.usesLanguageCorrection = true
        request.customWords = customWords
        request.minimumTextHeight = 0.025
        request.regionOfInterest = regionOfInterest
        return request
    }

    private static func candidates(from request: VNRecognizeTextRequest) -> [OCRCandidate] {
        let individual = (request.results ?? []).compactMap { observation -> OCRCandidate? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            return OCRCandidate(text: candidate.string, confidence: candidate.confidence)
        }
        guard individual.count > 1 else { return individual }
        let joined = OCRCandidate(
            text: individual.map(\.text).joined(separator: " "),
            confidence: individual.map(\.confidence).reduce(0, +) / Float(individual.count)
        )
        return individual + [joined]
    }
}
