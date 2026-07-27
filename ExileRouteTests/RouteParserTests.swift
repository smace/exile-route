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
        XCTAssertEqual(route.steps[1].contextAreaID, "1_1_1")
        XCTAssertEqual(route.steps[2].expectedAreaID, "1_1_2")
        XCTAssertEqual(route.steps[2].contextAreaID, "1_1_town")
        XCTAssertEqual(route.steps[2].hints, ["Follow the shore"])
    }

    func testBuildsDistinctVisitsAcrossWaypointLogoutAndPortalReturn() throws {
        let source = """
        Find start
        ➞ {enter|1_1_town}
        Hand in reward
        {waypoint|1_1_2}
        Find item
        {portal|set}
        {logout}
        Hand in town
        Take {portal|use}
        Find returned item
        """
        let route = try RouteParser(areas: areas, quests: [:]).parse(
            sources: [("Act 1", source)],
            configuration: RouteConfiguration()
        )

        XCTAssertEqual(route.visits.map(\.areaID), [
            "1_1_1", "1_1_town", "1_1_2", "1_1_town", "1_1_2"
        ])
        XCTAssertEqual(route.visits.map { $0.stepRange.count }, [2, 2, 3, 2, 1])
        XCTAssertEqual(route.steps[6].expectedAreaID, "1_1_town")
        XCTAssertEqual(route.steps[8].expectedAreaID, "1_1_2")
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

    func testLeagueLibraryBanditAndArenaConditionsKeepZoneContext() throws {
        let source = """
        Always
        #ifdef LEAGUE_START
        League objective
        #endif
        #ifdef LIBRARY
        Library objective
        #endif
        #ifdef BANDIT_KILL
        Kill all bandits
        #endif
        #ifdef BANDIT_ALIRA
        Help Alira
        #endif
        #ifdef BANDIT_KRAITYN
        Help Kraityn
        #endif
        #ifdef BANDIT_OAK
        Help Oak
        #endif
        Enter {arena|The Arena}, kill {kill|Arena Boss}
        """

        let configurations: [(RouteConfiguration, String)] = [
            (RouteConfiguration(leagueStart: true, includeLibrary: true, bandit: .killAll), "Kill all bandits"),
            (RouteConfiguration(leagueStart: false, includeLibrary: false, bandit: .alira), "Help Alira"),
            (RouteConfiguration(leagueStart: false, includeLibrary: false, bandit: .kraityn), "Help Kraityn"),
            (RouteConfiguration(leagueStart: false, includeLibrary: false, bandit: .oak), "Help Oak")
        ]

        for (configuration, expectedBandit) in configurations {
            let route = try RouteParser(areas: areas, quests: [:]).parse(
                sources: [("Act 1", source)],
                configuration: configuration
            )
            XCTAssertTrue(route.steps.contains(where: { $0.displayText == expectedBandit }))
            XCTAssertEqual(route.steps.last?.fragments.first?.kind, .arena)
            XCTAssertEqual(route.steps.last?.contextAreaID, "1_1_1")
            XCTAssertNil(route.steps.last?.expectedAreaID)
            XCTAssertEqual(route.visits.count, 1)
        }
    }

    func testRejectsUnbalancedCondition() {
        XCTAssertThrowsError(try RouteParser(areas: areas, quests: [:]).parse(
            sources: [("Act 1", "#endif")],
            configuration: RouteConfiguration()
        ))
    }

    func testBundledSnapshotParsesAllTenActs() throws {
        let resourceRoot = try XCTUnwrap(Bundle.main.resourceURL)
        let decoder = JSONDecoder()
        let bundledAreas = try decoder.decode(
            [String: AreaRecord].self,
            from: Data(contentsOf: resourceRoot.appendingPathComponent("areas.json"))
        )
        let bundledQuests = try decoder.decode(
            [String: QuestRecord].self,
            from: Data(contentsOf: resourceRoot.appendingPathComponent("quests.json"))
        )
        let sources = try (1...10).map { act in
            let contents = try String(
                contentsOf: resourceRoot.appendingPathComponent("act-\(act).txt"),
                encoding: .utf8
            )
            return ("Act \(act)", contents)
        }
        let route = try RouteParser(areas: bundledAreas, quests: bundledQuests)
            .parse(sources: sources, configuration: RouteConfiguration())
        XCTAssertEqual(route.sections.count, 10)
        XCTAssertGreaterThan(route.steps.count, 350)
        XCTAssertGreaterThan(route.expectedAreaIDs.count, 150)
        XCTAssertGreaterThan(route.visits.count, 200)
        XCTAssertTrue(route.visits.allSatisfy { !$0.stepRange.isEmpty })
    }

    func testLegacyCachedSnapshotFallsBackToBundledGemCatalog() throws {
        let resourceRoot = try XCTUnwrap(Bundle.main.resourceURL)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(String(repeating: "c", count: 40))
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Data"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: directory.appendingPathComponent("Routes"),
            withIntermediateDirectories: true
        )
        for filename in ["areas.json", "quests.json"] {
            try FileManager.default.copyItem(
                at: resourceRoot.appendingPathComponent(filename),
                to: directory.appendingPathComponent("Data/\(filename)")
            )
        }
        for act in 1...10 {
            try FileManager.default.copyItem(
                at: resourceRoot.appendingPathComponent("act-\(act).txt"),
                to: directory.appendingPathComponent("Routes/act-\(act).txt")
            )
        }
        let decoder = JSONDecoder()
        let fallback = GemCatalog(
            gems: try decoder.decode(
                [String: GemRecord].self,
                from: Data(contentsOf: resourceRoot.appendingPathComponent("gems.json"))
            ),
            characters: try decoder.decode(
                [String: CharacterRecord].self,
                from: Data(contentsOf: resourceRoot.appendingPathComponent("characters.json"))
            ),
            vaalGemLookup: try decoder.decode(
                [String: String].self,
                from: Data(contentsOf: resourceRoot.appendingPathComponent("vaal-gem-lookup.json"))
            ),
            awakenedGemLookup: try decoder.decode(
                [String: String].self,
                from: Data(contentsOf: resourceRoot.appendingPathComponent("awakened-gem-lookup.json"))
            )
        )

        let snapshot = try SnapshotLoader().loadDirectory(directory, fallbackCatalog: fallback)

        XCTAssertEqual(snapshot.gemCatalog, fallback)
        XCTAssertEqual(snapshot.routeSources.count, 10)
    }
}
