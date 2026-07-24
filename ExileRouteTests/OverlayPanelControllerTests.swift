import AppKit
import XCTest
@testable import ExileRoute

final class OverlayPanelControllerTests: XCTestCase {
    func testDefaultOriginUsesTopLeadingInsets() {
        let visibleFrame = CGRect(x: 0, y: 25, width: 1_440, height: 875)
        let panelSize = CGSize(width: 390, height: 230)

        let origin = OverlayPlacement.defaultOrigin(visibleFrame: visibleFrame, panelSize: panelSize)

        XCTAssertEqual(origin.x, 24)
        XCTAssertEqual(origin.y, 598)
    }

    func testDefaultOriginSupportsASecondaryDisplayLeftOfMain() {
        let visibleFrame = CGRect(x: -1_920, y: 0, width: 1_920, height: 1_080)
        let panelSize = CGSize(width: 390, height: 230)

        let origin = OverlayPlacement.defaultOrigin(visibleFrame: visibleFrame, panelSize: panelSize)

        XCTAssertEqual(origin.x, -1_896)
        XCTAssertEqual(origin.y, 778)
    }

    func testResizeKeepsTopLeadingCornerStable() {
        let currentFrame = CGRect(x: 24, y: 598, width: 390, height: 230)

        let origin = OverlayPlacement.resizedOrigin(
            currentFrame: currentFrame,
            newSize: CGSize(width: 460, height: 560)
        )

        XCTAssertEqual(origin.x, 24)
        XCTAssertEqual(origin.y, 268)
    }

    func testRestoringAStoredFrameKeepsItsTopLeadingCorner() {
        let storedFrame = CGRect(x: 24, y: 530, width: 390, height: 380)

        let origin = OverlayPlacement.resizedOrigin(
            currentFrame: storedFrame,
            newSize: CGSize(width: 390, height: 210)
        )

        XCTAssertEqual(origin.x, 24)
        XCTAssertEqual(origin.y, 700)
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
