import XCTest
@testable import ExileRoute

@MainActor
final class AppModelBuildTests: XCTestCase {
    func testImportReplacementAndRemovalPreserveCampaignObjectiveAndOptions() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersistenceStore(baseURL: directory)
        let model = AppModel(persistence: store)
        let configuration = model.routeConfiguration

        for _ in 0..<20 { model.moveNext() }
        let campaignStepID = try XCTUnwrap(model.currentStep?.id)

        await model.importBuild(TestPoBFixtures.multiSkillSet)
        XCTAssertEqual(model.currentStep?.id, campaignStepID)
        XCTAssertEqual(model.routeConfiguration, configuration)
        XCTAssertEqual(model.importedBuild?.characterClass, "Witch")

        await model.importBuild(TestPoBFixtures.legacy)
        XCTAssertEqual(model.currentStep?.id, campaignStepID)
        XCTAssertEqual(model.routeConfiguration, configuration)
        XCTAssertEqual(model.importedBuild?.characterClass, "Ranger")

        model.removeBuild()
        XCTAssertEqual(model.currentStep?.id, campaignStepID)
        XCTAssertEqual(model.routeConfiguration, configuration)
        XCTAssertNil(model.importedBuild)
        XCTAssertNil(store.load().importedBuild)
    }

    func testRemovingBuildFromGemObjectiveReturnsToItsCampaignParent() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))

        await model.importBuild(TestPoBFixtures.multiSkillSet)
        let gemIndex = try XCTUnwrap(model.route?.steps.firstIndex(where: { $0.gemAcquisition != nil }))
        while model.stepIndex < gemIndex { model.moveNext() }
        let parentID = try XCTUnwrap(model.currentStep?.gemAcquisition?.parentStepID)

        model.removeBuild()

        XCTAssertEqual(model.currentStep?.id, parentID)
        XCTAssertNil(model.currentStep?.gemAcquisition)
    }

    func testFailedImportLeavesBuildRouteAndProgressUnchanged() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))

        await model.importBuild(TestPoBFixtures.multiSkillSet)
        for _ in 0..<10 { model.moveNext() }
        let build = model.importedBuild
        let route = model.route
        let currentStepID = model.currentStep?.id

        await model.importBuild("not-a-pob")

        XCTAssertEqual(model.importedBuild, build)
        XCTAssertEqual(model.route, route)
        XCTAssertEqual(model.currentStep?.id, currentStepID)
    }

    func testLogoutContextWaitsForOneExactTownDetection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let logoutIndex = try XCTUnwrap(model.route?.steps.firstIndex(where: {
            $0.fragments.contains(where: { $0.kind == .logout })
        }))
        while model.stepIndex < logoutIndex { model.moveNext() }
        guard case .logout(let expectedTownID) = model.trackingContext.transition else {
            return XCTFail("Expected an armed logout transition")
        }
        let initialStep = model.stepIndex
        let detection = AreaDetection(
            text: model.areaName(for: expectedTownID),
            areaID: expectedTownID,
            confidence: 0.95,
            timestamp: Date()
        )

        model.consumeDetection(detection)

        XCTAssertGreaterThan(model.stepIndex, initialStep)
        XCTAssertEqual(model.trackingContext.currentAreaID, expectedTownID)
    }

    func testNumberedSiblingTransitionRequiresThreeDetections() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let transitionIndex = try XCTUnwrap(model.route?.steps.firstIndex(where: {
            $0.contextAreaID == "1_2_6_1" && $0.expectedAreaID == "1_2_6_2"
        }))
        while model.stepIndex < transitionIndex { model.moveNext() }
        let initialStep = model.stepIndex
        let detection = AreaDetection(
            text: "The Chamber of Sins Level 2",
            areaID: "1_2_6_2",
            confidence: 0.99,
            timestamp: Date()
        )

        model.consumeDetection(detection)
        model.consumeDetection(detection)
        XCTAssertEqual(model.stepIndex, initialStep)

        model.consumeDetection(detection)
        XCTAssertGreaterThan(model.stepIndex, initialStep)
    }

    func testTrackingDiagnosticsAreBoundedAndContainNoRawOCRText() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        for index in 0..<300 {
            model.recordTrackingDiagnostic("event=\(index)", at: Date(timeIntervalSince1970: TimeInterval(index)))
        }
        model.ocrStatus = .recognized("A raw area title")

        model.copyTrackingDiagnostics()

        let exported = NSPasteboard.general.string(forType: .string) ?? ""
        XCTAssertFalse(exported.contains("event=0"))
        XCTAssertTrue(exported.contains("event=299"))
        XCTAssertFalse(exported.contains("A raw area title"))
        XCTAssertLessThanOrEqual(exported.split(separator: "\n").count, 257)
    }

    func testCaptureRecoveryDoesNotMutateBuildProgressOrShortcuts() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        await model.importBuild(TestPoBFixtures.multiSkillSet)
        for _ in 0..<20 { model.moveNext() }
        let build = model.importedBuild
        let stepID = model.currentStep?.id
        let objectiveStates = model.currentZoneObjectives.map(\.state)
        let hotKeys = model.hotKeys

        model.ocrStatus = .noFrames
        model.updateTrackingHealth(lastFrameAt: Date(), restartCount: 1)
        model.ocrStatus = .recovering
        model.updateTrackingHealth(lastFrameAt: Date(), restartCount: 2)

        XCTAssertEqual(model.importedBuild, build)
        XCTAssertEqual(model.currentStep?.id, stepID)
        XCTAssertEqual(model.currentZoneObjectives.map(\.state), objectiveStates)
        XCTAssertEqual(model.hotKeys, hotKeys)
    }
}
