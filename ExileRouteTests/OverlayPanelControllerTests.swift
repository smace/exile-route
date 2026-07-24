import AppKit
import XCTest
@testable import ExileRoute

final class OverlayPanelControllerTests: XCTestCase {
    func testWindowDragOnlyBeginsForLeftClickInInteractionMode() {
        XCTAssertTrue(
            OverlayPanel.shouldBeginWindowDrag(
                interactionEnabled: true,
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            OverlayPanel.shouldBeginWindowDrag(
                interactionEnabled: false,
                eventType: .leftMouseDown
            )
        )
        XCTAssertFalse(
            OverlayPanel.shouldBeginWindowDrag(
                interactionEnabled: true,
                eventType: .rightMouseDown
            )
        )
    }

    func testDefaultOriginUsesTopTrailingInsetBelowOCRRegion() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 875)
        let panelSize = CGSize(width: 390, height: 230)

        let origin = OverlayPlacement.defaultOrigin(
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            ocrCrop: .defaultAreaTitle
        )

        XCTAssertEqual(origin.x, 1_026)
        XCTAssertEqual(origin.y, 535.5, accuracy: 0.001)
    }

    func testDefaultOriginSupportsASecondaryDisplayLeftOfMain() {
        let visibleFrame = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let panelSize = CGSize(width: 390, height: 230)

        let origin = OverlayPlacement.defaultOrigin(
            visibleFrame: visibleFrame,
            panelSize: panelSize,
            ocrCrop: .defaultAreaTitle
        )

        XCTAssertEqual(origin.x, -414)
        XCTAssertEqual(origin.y, 686.8, accuracy: 0.001)
    }

    func testResizeKeepsTopTrailingCornerStable() {
        let currentFrame = CGRect(x: 1_026, y: 535.5, width: 390, height: 230)

        let origin = OverlayPlacement.resizedOrigin(
            currentFrame: currentFrame,
            newSize: CGSize(width: 460, height: 560)
        )

        XCTAssertEqual(origin.x, 956)
        XCTAssertEqual(origin.y, 205.5, accuracy: 0.001)
    }

    func testRestoringAStoredFrameKeepsItsTopTrailingCorner() {
        let storedFrame = CGRect(x: 1_026, y: 385.5, width: 390, height: 380)

        let origin = OverlayPlacement.resizedOrigin(
            currentFrame: storedFrame,
            newSize: CGSize(width: 390, height: 210)
        )

        XCTAssertEqual(origin.x, 1_026)
        XCTAssertEqual(origin.y, 555.5, accuracy: 0.001)
    }

    func testInitialResizeNeverAnimatesBeforePlacementIsStable() {
        XCTAssertFalse(
            OverlayPlacement.shouldAnimateResize(
                hasCompletedInitialResize: false,
                isPanelVisible: true
            )
        )
        XCTAssertFalse(
            OverlayPlacement.shouldAnimateResize(
                hasCompletedInitialResize: true,
                isPanelVisible: false
            )
        )
        XCTAssertTrue(
            OverlayPlacement.shouldAnimateResize(
                hasCompletedInitialResize: true,
                isPanelVisible: true
            )
        )
    }

    func testNoOpResizeDoesNotCompleteInitialPlacement() {
        XCTAssertFalse(
            OverlayPlacement.completesInitialResize(
                currentSize: CGSize(width: 390, height: 210),
                newSize: CGSize(width: 390, height: 210)
            )
        )
        XCTAssertTrue(
            OverlayPlacement.completesInitialResize(
                currentSize: CGSize(width: 390, height: 210),
                newSize: CGSize(width: 390, height: 380)
            )
        )
    }

    func testOriginIsConstrainedInsideVisibleFrame() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 875)
        let panelSize = CGSize(width: 390, height: 230)

        let origin = OverlayPlacement.constrainedOrigin(
            CGPoint(x: -100, y: 900),
            panelSize: panelSize,
            visibleFrame: visibleFrame
        )

        XCTAssertEqual(origin.x, 0)
        XCTAssertEqual(origin.y, 670)
    }
}
