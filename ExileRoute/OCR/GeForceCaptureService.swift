import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
import ScreenCaptureKit

private final class CaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var matcher: AreaMatcher
    private var expectedAreaIDs: [String] = []
    private var crop: NormalizedRect
    private var isProcessing = false
    private let customWords: [String]
    private let onDetection: @MainActor @Sendable (AreaDetection) -> Void
    private let onStatus: @MainActor @Sendable (OCRStatus) -> Void

    init(
        areas: [String: AreaRecord],
        crop: NormalizedRect,
        onDetection: @escaping @MainActor @Sendable (AreaDetection) -> Void,
        onStatus: @escaping @MainActor @Sendable (OCRStatus) -> Void
    ) {
        matcher = AreaMatcher(areas: areas)
        customWords = Array(Set(areas.values.map(\.name))).sorted()
        self.crop = crop
        self.onDetection = onDetection
        self.onStatus = onStatus
    }

    func update(expectedAreaIDs: [String], crop: NormalizedRect) {
        lock.lock()
        self.expectedAreaIDs = expectedAreaIDs
        self.crop = crop
        lock.unlock()
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of outputType: SCStreamOutputType) {
        guard outputType == .screen, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer else { return }

        lock.lock()
        guard !isProcessing else { lock.unlock(); return }
        isProcessing = true
        let expected = expectedAreaIDs
        let captureCrop = crop
        lock.unlock()

        defer {
            lock.lock()
            isProcessing = false
            lock.unlock()
        }

        do {
            let candidates = try VisionTextRecognizer.recognize(
                pixelBuffer: pixelBuffer,
                regionOfInterest: captureCrop.cgRect,
                customWords: customWords
            )
            if let detection = matcher.match(candidates, expectedAreaIDs: expected) {
                Task { @MainActor in onDetection(detection) }
            } else if !candidates.isEmpty {
                Task { @MainActor in onStatus(.lowConfidence) }
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in onStatus(.failed(message)) }
        }
    }
}

@MainActor
final class GeForceCaptureService {
    static let bundleIdentifier = "com.nvidia.gfnpc.mall"

    private let output: CaptureOutput
    private let onStatus: @MainActor @Sendable (OCRStatus) -> Void
    private let sampleQueue = DispatchQueue(label: "com.swannmace.ExileRoute.ocr", qos: .userInitiated)
    private var stream: SCStream?
    private var isStarting = false

    init(
        areas: [String: AreaRecord],
        crop: NormalizedRect,
        onDetection: @escaping @MainActor @Sendable (AreaDetection) -> Void,
        onStatus: @escaping @MainActor @Sendable (OCRStatus) -> Void
    ) {
        self.onStatus = onStatus
        output = CaptureOutput(areas: areas, crop: crop, onDetection: onDetection, onStatus: onStatus)
    }

    func update(expectedAreaIDs: [String], crop: NormalizedRect) {
        output.update(expectedAreaIDs: expectedAreaIDs, crop: crop)
    }

    func start() async {
        guard stream == nil, !isStarting else { return }
        isStarting = true
        defer { isStarting = false }

        guard CGPreflightScreenCaptureAccess() || CGRequestScreenCaptureAccess() else {
            onStatus(.permissionRequired)
            return
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard let window = content.windows.first(where: {
                $0.owningApplication?.bundleIdentifier == Self.bundleIdentifier && $0.isOnScreen
            }) else {
                onStatus(.waitingForGeForceNow)
                return
            }

            let configuration = SCStreamConfiguration()
            configuration.width = max(Int(window.frame.width * 2), 1)
            configuration.height = max(Int(window.frame.height * 2), 1)
            configuration.pixelFormat = kCVPixelFormatType_32BGRA
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 2)
            configuration.queueDepth = 2
            configuration.showsCursor = false
            configuration.capturesAudio = false

            let capture = SCStream(
                filter: SCContentFilter(desktopIndependentWindow: window),
                configuration: configuration,
                delegate: nil
            )
            try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await capture.startCapture()
            stream = capture
            onStatus(.scanning)
        } catch {
            onStatus(.failed(error.localizedDescription))
        }
    }

    func stop() async {
        guard let capture = stream else { return }
        stream = nil
        do {
            try await capture.stopCapture()
            try capture.removeStreamOutput(output, type: .screen)
        } catch {
            onStatus(.failed(error.localizedDescription))
        }
    }
}

private extension NormalizedRect {
    var cgRect: CGRect {
        CGRect(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            width: min(max(width, 0.05), 1 - min(max(x, 0), 1)),
            height: min(max(height, 0.05), 1 - min(max(y, 0), 1))
        )
    }
}
