import XCTest
@testable import ExileRoute

final class ProgressionEngineTests: XCTestCase {
    private func route() -> CampaignRoute {
        CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: [
                RouteStep(id: "0", act: 1, line: 1, rawText: "start", displayText: "Start", fragments: [], hints: [], expectedAreaID: "a"),
                RouteStep(id: "1", act: 1, line: 2, rawText: "walk", displayText: "Walk", fragments: [], hints: [], expectedAreaID: nil),
                RouteStep(id: "2", act: 1, line: 3, rawText: "next", displayText: "Next", fragments: [], hints: [], expectedAreaID: "b")
            ])
        ])
    }

    func testRequiresRepeatedDetectionAndAdvancesForward() {
        var engine = ProgressionEngine(route: route())
        let detection = AreaDetection(text: "B", areaID: "b", confidence: 0.9, timestamp: Date())
        XCTAssertFalse(engine.consume(detection))
        XCTAssertTrue(engine.consume(detection))
        XCTAssertEqual(engine.progress.stepIndex, 2)
        XCTAssertEqual(engine.progress.currentAreaID, "b")
    }

    func testIgnoresLowConfidenceAndNeverRegresses() {
        var engine = ProgressionEngine(route: route(), progress: ProgressState(stepIndex: 2))
        let low = AreaDetection(text: "A", areaID: "a", confidence: 0.4, timestamp: Date())
        XCTAssertFalse(engine.consume(low))
        XCTAssertEqual(engine.progress.stepIndex, 2)
    }

    func testManualNavigationStaysInBounds() {
        var engine = ProgressionEngine(route: route())
        engine.movePrevious()
        XCTAssertEqual(engine.progress.stepIndex, 0)
        engine.moveNext()
        engine.moveNext()
        engine.moveNext()
        XCTAssertEqual(engine.progress.stepIndex, 2)
    }

    func testDistantJumpRequiresExplicitCommand() {
        let distantRoute = CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: (0..<12).map { index in
                RouteStep(
                    id: "\(index)", act: 1, line: index + 1, rawText: "step",
                    displayText: "Step \(index)", fragments: [], hints: [],
                    expectedAreaID: index == 10 ? "far" : nil
                )
            })
        ])
        var engine = ProgressionEngine(route: distantRoute)
        let detection = AreaDetection(text: "Far", areaID: "far", confidence: 0.95, timestamp: Date())
        XCTAssertFalse(engine.consume(detection, forwardWindow: 6))
        XCTAssertFalse(engine.consume(detection, forwardWindow: 6))
        XCTAssertEqual(engine.progress.stepIndex, 0)
        XCTAssertTrue(engine.jumpForward(toAreaID: "far"))
        XCTAssertEqual(engine.progress.stepIndex, 10)
    }
}
