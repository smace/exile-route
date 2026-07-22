import XCTest
@testable import ExileRoute

final class BootstrapTests: XCTestCase {
    func testApplicationName() {
        XCTAssertEqual("Exile Route", "Exile Route")
    }

    @MainActor
    func testScreenCapturePermissionIsRequestedOnlyOncePerLaunch() {
        var preflightCount = 0
        var requestCount = 0
        let gate = ScreenCapturePermissionGate(
            preflight: {
                preflightCount += 1
                return false
            },
            request: {
                requestCount += 1
                return false
            }
        )

        XCTAssertFalse(gate.ensureAccess())
        XCTAssertFalse(gate.ensureAccess())
        XCTAssertEqual(preflightCount, 2)
        XCTAssertEqual(requestCount, 1)
    }

    @MainActor
    func testScreenCapturePermissionRecoversAfterGrantWithoutRequestingAgain() {
        var isGranted = false
        var requestCount = 0
        let gate = ScreenCapturePermissionGate(
            preflight: { isGranted },
            request: {
                requestCount += 1
                return false
            }
        )

        XCTAssertFalse(gate.ensureAccess())
        isGranted = true
        XCTAssertTrue(gate.ensureAccess())
        XCTAssertEqual(requestCount, 1)
    }
}
