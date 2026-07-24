import XCTest
@testable import ExileRoute

final class PersistenceStoreTests: XCTestCase {
    func testRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = PersistenceStore(baseURL: directory)
        var state = StoredApplicationState()
        state.progress.stepIndex = 42
        state.progress.updatedAt = Date(timeIntervalSince1970: 12_345.678)
        state.settings.overlayOpacity = 0.82
        state.settings.overlayScreenID = "display-42"
        try store.save(state)
        XCTAssertEqual(store.load(), state)
    }

    func testLegacySettingsMigrateToCurrentOCRCalibrationAndHotKeys() throws {
        let legacyJSON = """
        {
          "routeConfiguration" : {
            "bandit" : "Kill All",
            "includeLibrary" : false,
            "leagueStart" : true
          },
          "overlayOpacity" : 0.82,
          "textScale" : 1,
          "isExpanded" : false,
          "isInteractionEnabled" : false,
          "isOCRActive" : true,
          "ocrCrop" : {
            "x" : 0.25,
            "y" : 0.66,
            "width" : 0.5,
            "height" : 0.28
          },
          "overlayFrames" : {}
        }
        """

        let settings = try JSONDecoder().decode(UserSettings.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(settings.ocrCrop, .defaultAreaTitle)
        XCTAssertEqual(settings.ocrCalibrationVersion, 2)
        XCTAssertEqual(settings.overlayPlacementVersion, 1)
        XCTAssertNil(settings.overlayScreenID)
        XCTAssertEqual(settings.hotKeys, HotKeyDefinition.defaults)
    }

    @MainActor
    func testSavingFrameMigratesLegacyOverlayPlacement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let legacyState = """
        {
          "settings" : {
            "overlayPlacementVersion" : 2,
            "overlayFrames" : {
              "display-old" : { "x" : 1000, "y" : 600, "width" : 390, "height" : 210 }
            }
          },
          "progress" : {
            "stepIndex" : 0,
            "currentAreaID" : null,
            "completedStepIDs" : [],
            "skippedStepIDs" : [],
            "updatedAt" : 0
          }
        }
        """
        try Data(legacyState.utf8).write(to: directory.appendingPathComponent("state.json"))
        let store = PersistenceStore(baseURL: directory)
        let model = AppModel(persistence: store)

        XCTAssertNil(model.overlayFrame(for: "display-old"))

        let newFrame = CGRect(x: 24, y: 598, width: 390, height: 230)
        model.saveOverlayFrame(newFrame, for: "display-current")
        let migrated = store.load().settings

        XCTAssertEqual(migrated.overlayPlacementVersion, UserSettings.currentOverlayPlacementVersion)
        XCTAssertEqual(migrated.overlayFrames, ["display-current": WindowGeometry(newFrame)])
        XCTAssertEqual(migrated.overlayScreenID, "display-current")
    }

    func testLegacyProgressWithoutSkippedObjectivesDecodes() throws {
        let legacyJSON = """
        {
          "stepIndex" : 7,
          "currentAreaID" : "1_1_2",
          "completedStepIDs" : ["one", "two"],
          "updatedAt" : 12345
        }
        """

        let progress = try JSONDecoder().decode(ProgressState.self, from: Data(legacyJSON.utf8))

        XCTAssertEqual(progress.stepIndex, 7)
        XCTAssertEqual(progress.currentAreaID, "1_1_2")
        XCTAssertEqual(progress.completedStepIDs, ["one", "two"])
        XCTAssertEqual(progress.skippedStepIDs, [])
    }
}
