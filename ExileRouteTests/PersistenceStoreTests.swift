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
        XCTAssertEqual(settings.hotKeys, HotKeyDefinition.defaults)
    }
}
