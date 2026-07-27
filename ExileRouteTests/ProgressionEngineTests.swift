import XCTest
@testable import ExileRoute

final class ProgressionEngineTests: XCTestCase {
    private func step(
        _ id: String,
        context: String,
        expected: String? = nil,
        text: String? = nil
    ) -> RouteStep {
        RouteStep(
            id: id,
            act: 1,
            line: Int(id) ?? 0,
            rawText: text ?? id,
            displayText: text ?? "Step \(id)",
            fragments: [],
            hints: [],
            contextAreaID: context,
            expectedAreaID: expected
        )
    }

    private func route() -> CampaignRoute {
        CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: [
                step("0", context: "a", text: "Find the first objective"),
                step("1", context: "a", expected: "b", text: "Enter B"),
                step("2", context: "b", text: "Find the item"),
                step("3", context: "b", expected: "c", text: "Enter C"),
                step("4", context: "c", text: "Hand in the quest")
            ])
        ])
    }

    func testRequiresRepeatedDetectionAndSelectsFirstObjectiveInNewArea() {
        var engine = ProgressionEngine(route: route())
        let detection = AreaDetection(text: "B", areaID: "b", confidence: 0.9, timestamp: Date())

        XCTAssertNil(engine.consume(detection))
        let result = engine.consume(detection)

        XCTAssertEqual(result?.areaID, "b")
        XCTAssertEqual(result?.skippedStepIDs, ["0"])
        XCTAssertEqual(engine.progress.stepIndex, 2)
        XCTAssertEqual(engine.progress.currentAreaID, "b")
        XCTAssertTrue(engine.progress.completedStepIDs.contains("1"))
        XCTAssertEqual(engine.currentVisit?.areaID, "b")
        XCTAssertEqual(engine.currentObjectives.map(\.state), [.active, .pending])
    }

    func testCurrentAreaDetectionCannotJumpToLaterRevisit() {
        let revisit = CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: [
                step("0", context: "a", expected: "b"),
                step("1", context: "b"),
                step("2", context: "b", expected: "c"),
                step("3", context: "c", expected: "b"),
                step("4", context: "b")
            ])
        ])
        var engine = ProgressionEngine(
            route: revisit,
            progress: ProgressState(stepIndex: 1, currentAreaID: "b")
        )
        let detection = AreaDetection(text: "B", areaID: "b", confidence: 0.95, timestamp: Date())

        XCTAssertNil(engine.consume(detection))
        XCTAssertNil(engine.consume(detection))
        XCTAssertEqual(engine.progress.stepIndex, 1)
    }

    func testOCRCannotSkipObjectivesAndVisitsToReachTidalIsland() {
        let campaignStart = CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: [
                step("0", context: "coast", text: "Get waypoint"),
                step("1", context: "coast", expected: "mud-flats", text: "Enter The Mud Flats"),
                step("2", context: "mud-flats", text: "Find 3 Rhoa Glyphs"),
                step("3", context: "mud-flats", expected: "passage", text: "Enter The Submerged Passage"),
                step("4", context: "passage", expected: "coast", text: "Waypoint to The Coast"),
                step("5", context: "coast", expected: "tidal-island", text: "Enter The Tidal Island"),
                step("6", context: "tidal-island", text: "Kill Hailrake")
            ])
        ])
        var engine = ProgressionEngine(
            route: campaignStart,
            progress: ProgressState(stepIndex: 0, currentAreaID: "coast")
        )
        let falsePositive = AreaDetection(
            text: "The Tidal Island",
            areaID: "tidal-island",
            confidence: 0.98,
            timestamp: Date()
        )

        XCTAssertEqual(engine.currentVisitExpectedAreaIDs, ["mud-flats"])
        XCTAssertNil(engine.consume(falsePositive))
        XCTAssertNil(engine.consume(falsePositive))
        XCTAssertEqual(engine.progress.stepIndex, 0)
        XCTAssertEqual(engine.progress.currentAreaID, "coast")
        XCTAssertTrue(engine.progress.completedStepIDs.isEmpty)
        XCTAssertTrue(engine.progress.skippedStepIDs.isEmpty)
    }

    func testOnlyTheImmediateTransitionCanAdvanceAutomatically() {
        let multipleTransitions = CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: [
                step("0", context: "a", expected: "b"),
                step("1", context: "a", expected: "c"),
                step("2", context: "c")
            ])
        ])
        var engine = ProgressionEngine(route: multipleTransitions)
        let future = AreaDetection(text: "C", areaID: "c", confidence: 0.99, timestamp: Date())

        XCTAssertEqual(engine.currentVisitExpectedAreaIDs, ["b", "c"])
        XCTAssertEqual(engine.immediateExpectedAreaID, "b")
        XCTAssertNil(engine.consume(future))
        XCTAssertNil(engine.consume(future))
        XCTAssertEqual(engine.progress.stepIndex, 0)
    }

    func testNumberedTransitionCanRequireThreeConfirmations() {
        var engine = ProgressionEngine(route: route())
        let detection = AreaDetection(text: "B Level 2", areaID: "b", confidence: 0.99, timestamp: Date())

        XCTAssertNil(engine.consume(detection, confirmationCount: 3))
        XCTAssertNil(engine.consume(detection, confirmationCount: 3))
        XCTAssertEqual(engine.consume(detection, confirmationCount: 3)?.areaID, "b")
    }

    func testIgnoresLowConfidenceAndNeverRegresses() {
        var engine = ProgressionEngine(
            route: route(),
            progress: ProgressState(stepIndex: 4, currentAreaID: "c")
        )
        let low = AreaDetection(text: "A", areaID: "a", confidence: 0.4, timestamp: Date())
        XCTAssertNil(engine.consume(low))
        XCTAssertEqual(engine.progress.stepIndex, 4)
    }

    func testManualNavigationCompletesObjectivesAndTransitionsAreas() {
        var engine = ProgressionEngine(route: route())

        engine.movePrevious()
        XCTAssertEqual(engine.progress.stepIndex, 0)

        engine.moveNext()
        XCTAssertEqual(engine.progress.stepIndex, 1)
        XCTAssertEqual(engine.progress.currentAreaID, "a")
        XCTAssertTrue(engine.progress.completedStepIDs.contains("0"))

        engine.moveNext()
        XCTAssertEqual(engine.progress.stepIndex, 2)
        XCTAssertEqual(engine.progress.currentAreaID, "b")
        XCTAssertTrue(engine.progress.completedStepIDs.contains("1"))

        engine.movePrevious()
        XCTAssertEqual(engine.progress.stepIndex, 1)
        XCTAssertEqual(engine.progress.currentAreaID, "a")
        XCTAssertFalse(engine.progress.completedStepIDs.contains("1"))
    }

    func testPreviousReturnsToFirstSkippedObjectiveAndSuppressesImmediateOCRBounce() {
        var engine = ProgressionEngine(
            route: route(),
            progress: ProgressState(stepIndex: 2, currentAreaID: "b")
        )
        let detection = AreaDetection(text: "C", areaID: "c", confidence: 0.95, timestamp: Date())
        XCTAssertNil(engine.consume(detection))
        XCTAssertEqual(engine.consume(detection)?.skippedStepIDs, ["2"])
        XCTAssertEqual(engine.progress.stepIndex, 4)

        engine.movePrevious()

        XCTAssertEqual(engine.progress.stepIndex, 2)
        XCTAssertEqual(engine.progress.currentAreaID, "b")
        XCTAssertFalse(engine.progress.skippedStepIDs.contains("2"))
        XCTAssertNil(engine.consume(detection))
        XCTAssertNil(engine.consume(detection))
        XCTAssertEqual(engine.progress.stepIndex, 2)
    }

    func testDistantJumpRequiresExplicitCommand() {
        let steps = (0..<12).map { index in
            step(
                "\(index)",
                context: index <= 10 ? "start" : "far",
                expected: index == 10 ? "far" : nil
            )
        }
        let distantRoute = CampaignRoute(source: "fixture", sections: [
            RouteSection(name: "Act 1", act: 1, steps: steps)
        ])
        var engine = ProgressionEngine(route: distantRoute)
        let detection = AreaDetection(text: "Far", areaID: "far", confidence: 0.95, timestamp: Date())

        XCTAssertNil(engine.consume(detection, forwardWindow: 6))
        XCTAssertNil(engine.consume(detection, forwardWindow: 6))
        XCTAssertEqual(engine.progress.stepIndex, 0)
        XCTAssertEqual(engine.jumpForward(toAreaID: "far")?.areaID, "far")
        XCTAssertEqual(engine.progress.stepIndex, 11)
        XCTAssertEqual(engine.progress.skippedStepIDs.count, 10)
    }

    func testLegacyArrivalCursorAdvancesToFirstObjective() {
        let legacy = ProgressState(stepIndex: 1, currentAreaID: "b")
        let engine = ProgressionEngine(route: route(), progress: legacy)

        XCTAssertEqual(engine.progress.stepIndex, 2)
        XCTAssertTrue(engine.progress.completedStepIDs.contains("1"))
        XCTAssertEqual(engine.currentStep?.displayText, "Find the item")
    }
}
