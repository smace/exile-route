import SwiftUI
import XCTest
@testable import ExileRoute

@MainActor
final class OverlaySnapshotTests: XCTestCase {
    func testReferenceVisualStatesRenderAtExpectedSizes() throws {
        let states: [(String, (AppModel) -> Void)] = [
            ("compact-short-visit", { _ in }),
            ("expanded", { $0.toggleExpanded() }),
            ("interaction", { $0.toggleInteraction() }),
            ("ocr-error", { $0.ocrStatus = .failed("Permission required") }),
            ("large-text", {
                Self.moveToLongestVisit($0)
                $0.setTextScale(1.35)
            }),
            ("seven-objectives", { Self.moveToLongestVisit($0) }),
            ("completed-active-pending-skipped", { Self.configureSkippedObjectives($0, returnToSkippedVisit: true) }),
            ("skipped-transition-notice", { Self.configureSkippedObjectives($0, returnToSkippedVisit: false) })
        ]

        for (name, configure) in states {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(persistence: PersistenceStore(baseURL: directory))
            configure(model)
            let size = model.isExpanded
                ? CGSize(width: 460, height: 560)
                : CGSize(width: 390, height: model.compactOverlayHeight)
            let view = OverlayView()
                .environmentObject(model)
                .environment(\.isSnapshotRendering, true)
                .frame(width: size.width, height: size.height)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.nsImage, "Failed to render \(name)")
            XCTAssertEqual(image.size.width, size.width, accuracy: 0.5)
            XCTAssertEqual(image.size.height, size.height, accuracy: 0.5)
            let attachment = XCTAttachment(image: image)
            attachment.name = "overlay-\(name)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    private static func moveToLongestVisit(_ model: AppModel) {
        guard let route = model.route,
              let visit = route.visits.max(by: { $0.stepRange.count < $1.stepRange.count }) else { return }
        while model.stepIndex < visit.stepRange.lowerBound { model.moveNext() }
    }

    private static func configureSkippedObjectives(_ model: AppModel, returnToSkippedVisit: Bool) {
        guard let route = model.route,
              let visit = route.visits.first(where: { visit in
                  visit.stepRange.count >= 4 && route.steps[visit.stepRange.upperBound - 1].expectedAreaID != nil
              }) else { return }

        while model.stepIndex < visit.stepRange.lowerBound { model.moveNext() }
        model.moveNext()

        guard let areaID = route.steps[visit.stepRange.upperBound - 1].expectedAreaID else { return }
        let detection = AreaDetection(text: model.areaName(for: areaID), areaID: areaID, confidence: 0.97, timestamp: Date())
        model.consumeDetection(detection)
        model.consumeDetection(detection)
        if returnToSkippedVisit { model.movePrevious() }
    }
}
