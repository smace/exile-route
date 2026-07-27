import Combine
import Foundation

@MainActor
private final class CaptureEventRelay {
    var handler: ((CaptureServiceEvent) -> Void)?

    func send(_ event: CaptureServiceEvent) {
        handler?(event)
    }
}

@MainActor
final class OCRCoordinator {
    private let model: AppModel
    private let relay: CaptureEventRelay
    private let supervisor: CaptureSupervisor
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        let relay = CaptureEventRelay()
        self.relay = relay
        let capture = GeForceCaptureService(
            areas: model.areaRecords,
            crop: model.ocrCrop,
            onEvent: { event in relay.send(event) }
        )
        supervisor = CaptureSupervisor(
            service: capture,
            onDetection: { [weak model] detection in
                model?.consumeDetection(detection)
            },
            onStatus: { [weak model] status in
                model?.ocrStatus = status
                model?.recordTrackingDiagnostic("state=\(status.diagnosticName)")
            },
            onHealth: { [weak model] lastFrameAt, restartCount in
                model?.updateTrackingHealth(lastFrameAt: lastFrameAt, restartCount: restartCount)
            },
            onDiagnostic: { [weak model] message in
                model?.recordTrackingDiagnostic(message)
            }
        )
        relay.handler = { [weak self] event in
            self?.supervisor.receive(event)
        }
        bind()
    }

    private func bind() {
        Publishers.CombineLatest(model.$isGeForceNowActive, model.$isOCRActive)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] active, enabled in
                guard let self else { return }
                refreshContext()
                Task {
                    await supervisor.setActive(
                        active && enabled,
                        inactiveStatus: enabled ? .waitingForGeForceNow : .disabled
                    )
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$stepIndex, model.$ocrCrop)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshContext() }
            .store(in: &cancellables)
    }

    private func refreshContext() {
        supervisor.update(context: model.trackingContext, crop: model.ocrCrop)
    }
}
