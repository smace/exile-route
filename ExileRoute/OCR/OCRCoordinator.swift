import Combine
import Foundation

@MainActor
final class OCRCoordinator {
    private let model: AppModel
    private let capture: GeForceCaptureService
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        capture = GeForceCaptureService(
            areas: model.areaRecords,
            crop: model.ocrCrop,
            onDetection: { [weak model] detection in
                Self.debugLog("detection=\(detection.text) confidence=\(detection.confidence)")
                model?.consumeDetection(detection)
            },
            onStatus: { [weak model] status in
                Self.debugLog("status=\(status)")
                model?.ocrStatus = status
            }
        )
        bind()
    }

    private func bind() {
        Publishers.CombineLatest(model.$isGeForceNowActive, model.$isOCRActive)
            .removeDuplicates { $0 == $1 }
            .receive(on: RunLoop.main)
            .sink { [weak self] active, enabled in
                guard let self else { return }
                if active && enabled {
                    refreshContext()
                    Task { await capture.start() }
                } else {
                    Task { await capture.stop() }
                    model.ocrStatus = enabled ? .waitingForGeForceNow : .disabled
                }
            }
            .store(in: &cancellables)

        Publishers.CombineLatest(model.$stepIndex, model.$ocrCrop)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _ in self?.refreshContext() }
            .store(in: &cancellables)
    }

    private func refreshContext() {
        capture.update(expectedAreaIDs: model.nearbyExpectedAreaIDs, crop: model.ocrCrop)
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        FileHandle.standardError.write(Data("[ExileRoute OCR] \(message)\n".utf8))
        #endif
    }
}
