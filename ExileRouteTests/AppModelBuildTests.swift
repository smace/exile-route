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
}
