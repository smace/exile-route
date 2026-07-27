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
        let url = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: "ocr-cases", withExtension: "json")
        )
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

    func testDuplicateExpectedAreaIDsKeepNearestRank() {
        let result = AreaMatcher(areas: areas).match(
            [OCRCandidate(text: "The Coast", confidence: 0.92)],
            expectedAreaIDs: ["coast", "coast", "passage"]
        )
        XCTAssertEqual(result?.areaID, "coast")
    }

    func testRejectsHUDLabelsAndQuestSentences() {
        let matcher = AreaMatcher(areas: areas)
        XCTAssertNil(matcher.match([OCRCandidate(text: "WAYPOINT SHOP MENU", confidence: 1)]))
        XCTAssertNil(matcher.match([OCRCandidate(text: "Search the Mud Flats for the entrance", confidence: 1)]))
    }

    func testNumberedSiblingAreasRequireTheExplicitExpectedLevel() {
        let pairs = [
            "The Chamber of Sins",
            "The Crypt",
            "The Solaris Temple",
            "The Lunaris Temple",
            "The Mines",
            "The Belly of the Beast"
        ]

        for (index, prefix) in pairs.enumerated() {
            let level1ID = "level-1-\(index)"
            let level2ID = "level-2-\(index)"
            let matcher = AreaMatcher(areas: [
                level1ID: AreaRecord(
                    id: level1ID,
                    name: "\(prefix) Level 1",
                    mapName: nil,
                    act: 1,
                    level: 1,
                    hasWaypoint: false,
                    isTownArea: false,
                    parentTownAreaID: "town"
                ),
                level2ID: AreaRecord(
                    id: level2ID,
                    name: "\(prefix) Level 2",
                    mapName: nil,
                    act: 1,
                    level: 2,
                    hasWaypoint: false,
                    isTownArea: false,
                    parentTownAreaID: "town"
                )
            ])

            XCTAssertNil(matcher.match(
                [OCRCandidate(text: "\(prefix) Level", confidence: 0.99)],
                expectedAreaIDs: [level2ID],
                allowedAreaIDs: [level2ID]
            ), prefix)
            XCTAssertNil(matcher.match(
                [OCRCandidate(text: "\(prefix) Level 1", confidence: 0.99)],
                expectedAreaIDs: [level2ID],
                allowedAreaIDs: [level2ID]
            ), prefix)
            XCTAssertNil(matcher.match(
                [OCRCandidate(text: "\(prefix) Level Z", confidence: 0.99)],
                expectedAreaIDs: [level2ID],
                allowedAreaIDs: [level2ID]
            ), prefix)
            XCTAssertEqual(matcher.match(
                [OCRCandidate(text: "\(prefix) Level 2", confidence: 0.99)],
                expectedAreaIDs: [level2ID],
                allowedAreaIDs: [level2ID]
            )?.areaID, level2ID, prefix)
        }
    }

    func testExactTownMatchRejectsPartialAndLowConfidenceCandidates() {
        let matcher = AreaMatcher(areas: areas)
        XCTAssertNil(matcher.match(
            [OCRCandidate(text: "Lioneye Watch", confidence: 0.99)],
            expectedAreaIDs: ["town"],
            allowedAreaIDs: ["town"],
            exactAreaID: "town",
            minimumCandidateConfidence: 0.80
        ))
        XCTAssertNil(matcher.match(
            [OCRCandidate(text: "Lioneye's Watch", confidence: 0.79)],
            expectedAreaIDs: ["town"],
            allowedAreaIDs: ["town"],
            exactAreaID: "town",
            minimumCandidateConfidence: 0.80
        ))
        XCTAssertEqual(matcher.match(
            [OCRCandidate(text: "Lioneye's Watch", confidence: 0.95)],
            expectedAreaIDs: ["town"],
            allowedAreaIDs: ["town"],
            exactAreaID: "town",
            minimumCandidateConfidence: 0.80
        )?.areaID, "town")
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
