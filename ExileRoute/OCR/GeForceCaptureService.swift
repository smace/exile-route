import CoreGraphics
import CoreMedia
import CoreVideo
import Foundation
@preconcurrency import ScreenCaptureKit

enum CaptureStartResult: Equatable, Sendable {
    case started(width: Int, height: Int)
    case alreadyRunning
    case waitingForWindow
    case permissionRequired
    case failed(String)
}

enum CaptureServiceEvent: Equatable, Sendable {
    case frame(Date)
    case detection(AreaDetection)
    case lowConfidence
    case recognitionFailed(String)
    case streamStopped(String)
}

@MainActor
protocol GeForceCaptureServicing: AnyObject {
    func update(context: TrackingContext, crop: NormalizedRect)
    func start() async -> CaptureStartResult
    func stop() async
}

@MainActor
final class ScreenCapturePermissionGate {
    private let preflight: () -> Bool
    private let request: () -> Bool
    private var hasRequestedAccess = false

    init(
        preflight: @escaping () -> Bool = CGPreflightScreenCaptureAccess,
        request: @escaping () -> Bool = CGRequestScreenCaptureAccess
    ) {
        self.preflight = preflight
        self.request = request
    }

    func ensureAccess() -> Bool {
        if preflight() {
            return true
        }
        guard !hasRequestedAccess else {
            return false
        }
        hasRequestedAccess = true
        return request()
    }
}

private final class CaptureOutput: NSObject, SCStreamOutput, @unchecked Sendable {
    private let lock = NSLock()
    private var matcher: AreaMatcher
    private var context = TrackingContext.empty
    private var crop: NormalizedRect
    private var isProcessing = false
    private var lastProcessedAt = 0.0
    private let customWords: [String]
    private let onEvent: @MainActor @Sendable (CaptureServiceEvent) -> Void

    init(
        areas: [String: AreaRecord],
        crop: NormalizedRect,
        onEvent: @escaping @MainActor @Sendable (CaptureServiceEvent) -> Void
    ) {
        matcher = AreaMatcher(areas: areas)
        customWords = Array(Set(areas.values.map(\.name))).sorted()
        self.crop = crop
        self.onEvent = onEvent
    }

    func update(context: TrackingContext, crop: NormalizedRect) {
        lock.lock()
        self.context = context
        self.crop = crop
        lock.unlock()
    }

    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .screen, sampleBuffer.isValid, let pixelBuffer = sampleBuffer.imageBuffer else { return }
        let timestamp = Date()
        Task { @MainActor in onEvent(.frame(timestamp)) }

        lock.lock()
        let now = timestamp.timeIntervalSinceReferenceDate
        guard !isProcessing, now - lastProcessedAt >= 0.75 else {
            lock.unlock()
            return
        }
        isProcessing = true
        lastProcessedAt = now
        let trackingContext = context
        let captureCrop = crop
        lock.unlock()

        defer {
            lock.lock()
            isProcessing = false
            lock.unlock()
        }

        do {
            var candidates = try VisionTextRecognizer.recognize(
                pixelBuffer: pixelBuffer,
                regionOfInterest: captureCrop.cgRect,
                customWords: customWords
            )
            if trackingContext.transition.isLogout {
                candidates += try VisionTextRecognizer.recognize(
                    pixelBuffer: pixelBuffer,
                    regionOfInterest: NormalizedRect.loadingTitle.cgRect,
                    customWords: customWords
                )
            }

            let detection: AreaDetection?
            if case .logout(let expectedTownID) = trackingContext.transition {
                detection = matcher.match(
                    candidates,
                    expectedAreaIDs: [expectedTownID],
                    allowedAreaIDs: [expectedTownID],
                    exactAreaID: expectedTownID,
                    minimumCandidateConfidence: 0.80,
                    timestamp: timestamp
                )
            } else {
                let expected = trackingContext.transition.expectedAreaID.map { [$0] } ?? []
                detection = matcher.match(
                    candidates,
                    expectedAreaIDs: expected,
                    allowedAreaIDs: trackingContext.automaticAreaIDs,
                    timestamp: timestamp
                ) ?? matcher.match(candidates, expectedAreaIDs: expected, timestamp: timestamp)
            }

            if let detection {
                Task { @MainActor in onEvent(.detection(detection)) }
            } else if !candidates.isEmpty {
                Task { @MainActor in onEvent(.lowConfidence) }
            }
        } catch {
            let message = error.localizedDescription
            Task { @MainActor in onEvent(.recognitionFailed(message)) }
        }
    }
}

private final class CaptureStreamDelegate: NSObject, SCStreamDelegate, @unchecked Sendable {
    private let onStopped: @MainActor @Sendable (String) -> Void

    init(onStopped: @escaping @MainActor @Sendable (String) -> Void) {
        self.onStopped = onStopped
    }

    func stream(_ stream: SCStream, didStopWithError error: any Error) {
        let message = error.localizedDescription
        Task { @MainActor in onStopped(message) }
    }
}

@MainActor
final class GeForceCaptureService: GeForceCaptureServicing {
    static let bundleIdentifier = "com.nvidia.gfnpc.mall"

    private let output: CaptureOutput
    private let streamDelegate: CaptureStreamDelegate
    private let permissionGate: ScreenCapturePermissionGate
    private let sampleQueue = DispatchQueue(label: "com.swannmace.ExileRoute.ocr", qos: .userInitiated)
    private var stream: SCStream?
    private var isStarting = false

    init(
        areas: [String: AreaRecord],
        crop: NormalizedRect,
        onEvent: @escaping @MainActor @Sendable (CaptureServiceEvent) -> Void,
        permissionGate: ScreenCapturePermissionGate = ScreenCapturePermissionGate()
    ) {
        self.permissionGate = permissionGate
        output = CaptureOutput(areas: areas, crop: crop, onEvent: onEvent)
        streamDelegate = CaptureStreamDelegate { message in
            onEvent(.streamStopped(message))
        }
    }

    func update(context: TrackingContext, crop: NormalizedRect) {
        output.update(context: context, crop: crop)
    }

    func start() async -> CaptureStartResult {
        guard stream == nil else { return .alreadyRunning }
        guard !isStarting else { return .alreadyRunning }
        isStarting = true
        defer { isStarting = false }

        guard permissionGate.ensureAccess() else {
            return .permissionRequired
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            let geForceWindows = content.windows.filter {
                $0.owningApplication?.bundleIdentifier == Self.bundleIdentifier && $0.isOnScreen
            }
            guard let window = geForceWindows.max(by: {
                $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height
            }), window.frame.width >= 640, window.frame.height >= 360 else {
                return .waitingForWindow
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
                delegate: streamDelegate
            )
            try capture.addStreamOutput(output, type: .screen, sampleHandlerQueue: sampleQueue)
            try await capture.startCapture()
            stream = capture
            return .started(width: Int(window.frame.width), height: Int(window.frame.height))
        } catch {
            return .failed(error.localizedDescription)
        }
    }

    func stop() async {
        guard let capture = stream else { return }
        stream = nil
        do {
            try await capture.stopCapture()
            try capture.removeStreamOutput(output, type: .screen)
        } catch {
            // A stopped or replaced stream is already unusable; the supervisor will recreate it.
        }
    }
}

private extension NormalizedRect {
    static let loadingTitle = NormalizedRect(x: 0.15, y: 0.30, width: 0.70, height: 0.40)

    var cgRect: CGRect {
        CGRect(
            x: min(max(x, 0), 1),
            y: min(max(y, 0), 1),
            width: min(max(width, 0.05), 1 - min(max(x, 0), 1)),
            height: min(max(height, 0.05), 1 - min(max(y, 0), 1))
        )
    }
}
