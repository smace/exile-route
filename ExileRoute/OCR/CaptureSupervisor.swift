import Foundation

@MainActor
final class CaptureSupervisor {
    private let service: GeForceCaptureServicing
    private let onDetection: (AreaDetection) -> Void
    private let onStatus: (OCRStatus) -> Void
    private let onHealth: (Date?, Int) -> Void
    private let onDiagnostic: (String) -> Void
    private let now: () -> Date
    private let noFrameTimeout: TimeInterval
    private let retryDelays: [TimeInterval]

    private(set) var context = TrackingContext.empty
    private(set) var isRunning = false
    private(set) var restartCount = 0
    private(set) var lastFrameAt: Date?
    private var isActive = false
    private var isStarting = false
    private var retryIndex = 0
    private var retryTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?

    init(
        service: GeForceCaptureServicing,
        noFrameTimeout: TimeInterval = 5,
        retryDelays: [TimeInterval] = [0.5, 1, 2, 5],
        now: @escaping () -> Date = Date.init,
        onDetection: @escaping (AreaDetection) -> Void,
        onStatus: @escaping (OCRStatus) -> Void,
        onHealth: @escaping (Date?, Int) -> Void,
        onDiagnostic: @escaping (String) -> Void
    ) {
        self.service = service
        self.noFrameTimeout = noFrameTimeout
        self.retryDelays = retryDelays
        self.now = now
        self.onDetection = onDetection
        self.onStatus = onStatus
        self.onHealth = onHealth
        self.onDiagnostic = onDiagnostic
    }

    func update(context: TrackingContext, crop: NormalizedRect) {
        let previous = self.context
        self.context = context
        service.update(context: context, crop: crop)
        guard isRunning, previous != context else { return }
        publishLiveStatus()
        onDiagnostic("context step=\(context.stepID ?? "none") current=\(context.currentAreaID ?? "none") expected=\(context.transition.expectedAreaID ?? "none") logout=\(context.transition.isLogout)")
    }

    func setActive(_ active: Bool, inactiveStatus: OCRStatus) async {
        if !active {
            onStatus(inactiveStatus)
        }
        guard active != isActive else { return }
        isActive = active
        retryTask?.cancel()
        retryTask = nil

        if active {
            onDiagnostic("capture activated")
            startWatchdog()
            await attemptStart(recovery: false)
        } else {
            watchdogTask?.cancel()
            watchdogTask = nil
            isRunning = false
            isStarting = false
            lastFrameAt = nil
            retryIndex = 0
            onHealth(nil, restartCount)
            await service.stop()
            onDiagnostic("capture deactivated")
        }
    }

    func receive(_ event: CaptureServiceEvent) {
        switch event {
        case .frame(let date):
            lastFrameAt = date
            onHealth(date, restartCount)
        case .detection(let detection):
            onStatus(.recognized(detection.text))
            onDetection(detection)
        case .lowConfidence:
            onStatus(context.transition.isLogout ? .returningToTown : .lowConfidence)
        case .recognitionFailed(let message):
            onStatus(.failed(message))
            onDiagnostic("recognition failed error=\(Self.sanitize(message))")
        case .streamStopped(let message):
            guard isActive, isRunning else { return }
            isRunning = false
            onDiagnostic("stream stopped error=\(Self.sanitize(message))")
            Task { [weak self] in
                await self?.recoverStoppedStream()
            }
        }
    }

    func evaluateHealth(at date: Date) async {
        guard isActive, isRunning, let lastFrameAt,
              date.timeIntervalSince(lastFrameAt) >= noFrameTimeout else { return }
        onStatus(.noFrames)
        onDiagnostic("no frames timeout=\(Int(noFrameTimeout))s")
        restartCount += 1
        onHealth(lastFrameAt, restartCount)
        isRunning = false
        await service.stop()
        await attemptStart(recovery: true)
    }

    private func attemptStart(recovery: Bool) async {
        guard isActive, !isRunning, !isStarting else { return }
        isStarting = true
        if recovery { onStatus(.recovering) }
        let result = await service.start()
        isStarting = false
        guard isActive else {
            await service.stop()
            return
        }

        switch result {
        case .started(let width, let height):
            isRunning = true
            retryIndex = 0
            lastFrameAt = now()
            onHealth(lastFrameAt, restartCount)
            publishLiveStatus()
            onDiagnostic("stream started window=\(width)x\(height) restarts=\(restartCount)")
        case .alreadyRunning:
            isRunning = true
            retryIndex = 0
            lastFrameAt = now()
            onHealth(lastFrameAt, restartCount)
            publishLiveStatus()
        case .waitingForWindow:
            onStatus(recovery ? .recovering : .waitingForGeForceNow)
            onDiagnostic("window unavailable")
            scheduleRetry(recovery: true)
        case .permissionRequired:
            onStatus(.permissionRequired)
            onDiagnostic("screen capture permission required")
        case .failed(let message):
            onStatus(.recovering)
            onDiagnostic("start failed error=\(Self.sanitize(message))")
            scheduleRetry(recovery: true)
        }
    }

    private func scheduleRetry(recovery: Bool) {
        guard isActive, retryTask == nil, !retryDelays.isEmpty else { return }
        let delay = retryDelays[min(retryIndex, max(retryDelays.count - 1, 0))]
        retryIndex = min(retryIndex + 1, max(retryDelays.count - 1, 0))
        retryTask = Task { [weak self] in
            guard delay > 0 else {
                self?.retryTask = nil
                await self?.attemptStart(recovery: recovery)
                return
            }
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.retryTask = nil
            await self?.attemptStart(recovery: recovery)
        }
    }

    private func startWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, let self else { return }
                await self.evaluateHealth(at: self.now())
            }
        }
    }

    private func publishLiveStatus() {
        onStatus(context.transition.isLogout ? .returningToTown : .scanning)
    }

    private func recoverStoppedStream() async {
        guard isActive else { return }
        onStatus(.recovering)
        restartCount += 1
        onHealth(lastFrameAt, restartCount)
        await service.stop()
        await attemptStart(recovery: true)
    }

    private static func sanitize(_ value: String) -> String {
        value.replacingOccurrences(of: "\n", with: " ").prefix(240).description
    }
}
