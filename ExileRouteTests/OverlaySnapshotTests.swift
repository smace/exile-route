import SwiftUI
import XCTest
@testable import ExileRoute

@MainActor
final class OverlaySnapshotTests: XCTestCase {
    func testReferenceVisualStatesRenderAtExpectedSizes() throws {
        let states: [(String, (AppModel) -> Void, CGSize)] = [
            ("compact", { _ in }, CGSize(width: 390, height: 210)),
            ("expanded", { $0.toggleExpanded() }, CGSize(width: 460, height: 560)),
            ("interaction", { $0.toggleInteraction() }, CGSize(width: 390, height: 210)),
            ("ocr-error", { $0.ocrStatus = .failed("Permission required") }, CGSize(width: 390, height: 210)),
            ("large-text", { $0.setTextScale(1.35) }, CGSize(width: 390, height: 250))
        ]

        for (name, configure, size) in states {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let model = AppModel(persistence: PersistenceStore(baseURL: directory))
            configure(model)
            let view = OverlayView().environmentObject(model).frame(width: size.width, height: size.height)
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
}
