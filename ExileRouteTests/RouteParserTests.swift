import XCTest
@testable import ExileRoute

final class RouteParserTests: XCTestCase {
    private let areas: [String: AreaRecord] = [
        "1_1_1": AreaRecord(id: "1_1_1", name: "The Twilight Strand", mapName: nil, act: 1, level: 1, hasWaypoint: false, isTownArea: false, parentTownAreaID: "1_1_town"),
        "1_1_town": AreaRecord(id: "1_1_town", name: "Lioneye's Watch", mapName: nil, act: 1, level: 1, hasWaypoint: true, isTownArea: true, parentTownAreaID: nil),
        "1_1_2": AreaRecord(id: "1_1_2", name: "The Coast", mapName: nil, act: 1, level: 2, hasWaypoint: true, isTownArea: false, parentTownAreaID: "1_1_town")
    ]

    func testParsesFragmentsConditionsAndHints() throws {
        let source = """
        #section Act 1
        Find and kill {kill|Hillock}
        ➞ {enter|1_1_town} #Lioneye's Watch
        #ifdef LEAGUE_START
            ➞ {enter|1_1_2} #The Coast
                #sub Follow the shore
        #endif
        """
        let route = try RouteParser(areas: areas, quests: [:]).parse(
            sources: [("Act 1", source)],
            configuration: RouteConfiguration()
        )
        XCTAssertEqual(route.steps.count, 3)
        XCTAssertEqual(route.steps[1].displayText, "→ Lioneye's Watch")
        XCTAssertEqual(route.steps[2].expectedAreaID, "1_1_2")
        XCTAssertEqual(route.steps[2].hints, ["Follow the shore"])
    }

    func testExcludesDisabledConditional() throws {
        let source = """
        #section Act 1
        Find {generic|start}
        #ifdef LEAGUE_START
            Find {generic|optional}
        #endif
        """
        let route = try RouteParser(areas: areas, quests: [:]).parse(
            sources: [("Act 1", source)],
            configuration: RouteConfiguration(leagueStart: false)
        )
        XCTAssertEqual(route.steps.map(\.displayText), ["Find start"])
    }

    func testRejectsUnbalancedCondition() {
        XCTAssertThrowsError(try RouteParser(areas: areas, quests: [:]).parse(
            sources: [("Act 1", "#endif")],
            configuration: RouteConfiguration()
        ))
    }

    func testBundledSnapshotParsesAllTenActs() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resourceRoot = projectRoot.appendingPathComponent("ExileRoute/Resources")
        let decoder = JSONDecoder()
        let bundledAreas = try decoder.decode(
            [String: AreaRecord].self,
            from: Data(contentsOf: resourceRoot.appendingPathComponent("Data/areas.json"))
        )
        let bundledQuests = try decoder.decode(
            [String: QuestRecord].self,
            from: Data(contentsOf: resourceRoot.appendingPathComponent("Data/quests.json"))
        )
        let sources = try (1...10).map { act in
            let contents = try String(
                contentsOf: resourceRoot.appendingPathComponent("Routes/act-\(act).txt"),
                encoding: .utf8
            )
            return ("Act \(act)", contents)
        }
        let route = try RouteParser(areas: bundledAreas, quests: bundledQuests)
            .parse(sources: sources, configuration: RouteConfiguration())
        XCTAssertEqual(route.sections.count, 10)
        XCTAssertGreaterThan(route.steps.count, 350)
        XCTAssertGreaterThan(route.expectedAreaIDs.count, 150)
    }
}
