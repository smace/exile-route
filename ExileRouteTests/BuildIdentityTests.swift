import XCTest
@testable import ExileRoute

final class BuildIdentityTests: XCTestCase {
    func testFormatsVersionBuildAndRevision() {
        let identity = BuildIdentity(infoDictionary: [
            "CFBundleShortVersionString": "1.2.3",
            "CFBundleVersion": "42"
        ], revision: "deadbeef")

        XCTAssertEqual(identity.compactDescription, "v1.2.3 (42) • deadbeef")
        XCTAssertEqual(identity.accessibleDescription, "Version 1.2.3, build 42, commit deadbeef")
    }

    func testUsesReadableFallbacksForMissingValues() {
        let identity = BuildIdentity(infoDictionary: [:])

        XCTAssertEqual(identity.compactDescription, "v0.0.0 (0) • unknown")
    }
}
