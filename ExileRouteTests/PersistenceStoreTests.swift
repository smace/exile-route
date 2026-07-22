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
}
