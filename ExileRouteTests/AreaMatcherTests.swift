import AppKit
import XCTest
@testable import ExileRoute

final class AreaMatcherTests: XCTestCase {
    private let areas = [
        "coast": AreaRecord(id: "coast", name: "The Coast", mapName: nil, act: 1, level: 2, hasWaypoint: true, isTownArea: false, parentTownAreaID: "town"),
        "coast-late": AreaRecord(id: "coast-late", name: "The Coast", mapName: nil, act: 6, level: 45, hasWaypoint: true, isTownArea: false, parentTownAreaID: "town-late"),
        "town": AreaRecord(id: "town", name: "Lioneye's Watch", mapName: nil, act: 1, level: 1, hasWaypoint: true, isTownArea: true, parentTownAreaID: nil),
        "passage": AreaRecord(id: "passage", name: "The Submerged Passage", mapName: nil, act: 1, level: 5, hasWaypoint: false, isTownArea: false, parentTownAreaID: "town")
    ]

    func testMatchesResolutionAndStreamEffectFixtures() throws {
        struct Fixture: Decodable {
            let name: String
            let resolution: String
            let text: String
            let confidence: Float
            let expectedAreaID: String
        }
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/ocr-cases.json")
        let fixtures = try JSONDecoder().decode([Fixture].self, from: Data(contentsOf: url))
        let matcher = AreaMatcher(areas: areas)

        for fixture in fixtures {
            let result = matcher.match(
                [OCRCandidate(text: fixture.text, confidence: fixture.confidence)],
                expectedAreaIDs: [fixture.expectedAreaID]
            )
            XCTAssertEqual(result?.areaID, fixture.expectedAreaID, "\(fixture.name) at \(fixture.resolution)")
        }
    }

    func testExpectedRouteDisambiguatesDuplicateAreaNames() {
        let result = AreaMatcher(areas: areas).match(
            [OCRCandidate(text: "The Coast", confidence: 0.92)],
            expectedAreaIDs: ["coast-late"]
        )
        XCTAssertEqual(result?.areaID, "coast-late")
    }

    func testVisionReadsSyntheticHighContrastAreaTitle() throws {
        let image = NSImage(size: NSSize(width: 1200, height: 320))
        image.lockFocus()
        NSColor.black.setFill()
        NSRect(x: 0, y: 0, width: 1200, height: 320).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 104, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        NSAttributedString(string: "THE COAST", attributes: attributes)
            .draw(at: NSPoint(x: 275, y: 95))
        image.unlockFocus()

        var proposed = NSRect(origin: .zero, size: image.size)
        let cgImage = try XCTUnwrap(image.cgImage(forProposedRect: &proposed, context: nil, hints: nil))
        let candidates = try VisionTextRecognizer.recognize(cgImage: cgImage, customWords: areas.values.map(\.name))
        let detection = AreaMatcher(areas: areas).match(candidates, expectedAreaIDs: ["coast"])
        XCTAssertEqual(detection?.areaID, "coast")
    }
}
