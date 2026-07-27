import XCTest
@testable import ExileRoute

@MainActor
private final class FakeCaptureService: GeForceCaptureServicing {
    var startResults: [CaptureStartResult]
    private(set) var startCount = 0
    private(set) var stopCount = 0
    private(set) var contexts: [TrackingContext] = []

    init(startResults: [CaptureStartResult]) {
        self.startResults = startResults
    }

    func update(context: TrackingContext, crop: NormalizedRect) {
        contexts.append(context)
    }

    func start() async -> CaptureStartResult {
        startCount += 1
        guard !startResults.isEmpty else { return .alreadyRunning }
        return startResults.removeFirst()
    }

    func stop() async {
        stopCount += 1
    }
}

@MainActor
final class CaptureSupervisorTests: XCTestCase {
    func testStartsInReturningStateAndForwardsTownDetection() async {
        let service = FakeCaptureService(startResults: [.started(width: 1440, height: 900)])
        var statuses: [OCRStatus] = []
        var detections: [AreaDetection] = []
        let supervisor = makeSupervisor(
            service: service,
            noFrameTimeout: 1_000,
            statuses: { statuses.append($0) },
            detections: { detections.append($0) }
        )
        let context = TrackingContext(
            stepID: "logout",
            currentAreaID: "coast",
            transition: .logout(expectedTownID: "town")
        )
        supervisor.update(context: context, crop: .defaultAreaTitle)

        await supervisor.setActive(true, inactiveStatus: .waitingForGeForceNow)
        let detection = AreaDetection(text: "Lioneye's Watch", areaID: "town", confidence: 0.95, timestamp: Date())
        supervisor.receive(.detection(detection))

        XCTAssertEqual(service.startCount, 1)
        XCTAssertTrue(statuses.contains(.returningToTown))
        XCTAssertEqual(detections, [detection])
        await supervisor.setActive(false, inactiveStatus: .waitingForGeForceNow)
    }

    func testNoFrameWatchdogStopsAndRecreatesCapture() async {
        let service = FakeCaptureService(startResults: [
            .started(width: 1440, height: 900),
            .started(width: 1728, height: 1117)
        ])
        var statuses: [OCRStatus] = []
        let base = Date()
        let supervisor = makeSupervisor(
            service: service,
            noFrameTimeout: 5,
            now: { base },
            statuses: { statuses.append($0) }
        )

        await supervisor.setActive(true, inactiveStatus: .waitingForGeForceNow)
        supervisor.receive(.frame(base))
        await supervisor.evaluateHealth(at: base.addingTimeInterval(5.1))

        XCTAssertEqual(service.stopCount, 1)
        XCTAssertEqual(service.startCount, 2)
        XCTAssertEqual(supervisor.restartCount, 1)
        XCTAssertTrue(statuses.contains(.noFrames))
        XCTAssertTrue(statuses.contains(.recovering))
        await supervisor.setActive(false, inactiveStatus: .waitingForGeForceNow)
    }

    func testMissingWindowRetriesUntilCaptureStarts() async throws {
        let service = FakeCaptureService(startResults: [
            .waitingForWindow,
            .started(width: 1440, height: 900)
        ])
        var statuses: [OCRStatus] = []
        let supervisor = makeSupervisor(
            service: service,
            noFrameTimeout: 1_000,
            retryDelays: [0],
            statuses: { statuses.append($0) }
        )

        await supervisor.setActive(true, inactiveStatus: .waitingForGeForceNow)
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(service.startCount, 2)
        XCTAssertTrue(supervisor.isRunning)
        XCTAssertTrue(statuses.contains(.waitingForGeForceNow))
        await supervisor.setActive(false, inactiveStatus: .waitingForGeForceNow)
    }

    func testUnexpectedStreamStopRecreatesTheStream() async throws {
        let service = FakeCaptureService(startResults: [
            .started(width: 1440, height: 900),
            .started(width: 1440, height: 900)
        ])
        var statuses: [OCRStatus] = []
        let supervisor = makeSupervisor(
            service: service,
            noFrameTimeout: 1_000,
            statuses: { statuses.append($0) }
        )

        await supervisor.setActive(true, inactiveStatus: .waitingForGeForceNow)
        supervisor.receive(.streamStopped("renderer replaced"))
        try await Task.sleep(for: .milliseconds(20))

        XCTAssertEqual(service.stopCount, 1)
        XCTAssertEqual(service.startCount, 2)
        XCTAssertEqual(supervisor.restartCount, 1)
        XCTAssertTrue(statuses.contains(.recovering))
        await supervisor.setActive(false, inactiveStatus: .waitingForGeForceNow)
    }

    func testDeactivationStopsRetriesAndPublishesInactiveStatus() async {
        let service = FakeCaptureService(startResults: [.waitingForWindow])
        var statuses: [OCRStatus] = []
        let supervisor = makeSupervisor(
            service: service,
            noFrameTimeout: 1_000,
            retryDelays: [5],
            statuses: { statuses.append($0) }
        )

        await supervisor.setActive(true, inactiveStatus: .waitingForGeForceNow)
        await supervisor.setActive(false, inactiveStatus: .disabled)

        XCTAssertEqual(statuses.last, .disabled)
        XCTAssertFalse(supervisor.isRunning)
        XCTAssertEqual(service.startCount, 1)
    }

    private func makeSupervisor(
        service: FakeCaptureService,
        noFrameTimeout: TimeInterval,
        retryDelays: [TimeInterval] = [0.5, 1, 2, 5],
        now: @escaping () -> Date = Date.init,
        statuses: @escaping (OCRStatus) -> Void = { _ in },
        detections: @escaping (AreaDetection) -> Void = { _ in }
    ) -> CaptureSupervisor {
        CaptureSupervisor(
            service: service,
            noFrameTimeout: noFrameTimeout,
            retryDelays: retryDelays,
            now: now,
            onDetection: detections,
            onStatus: statuses,
            onHealth: { _, _ in },
            onDiagnostic: { _ in }
        )
    }
}
