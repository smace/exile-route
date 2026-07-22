import Foundation

struct AreaRecord: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let mapName: String?
    let act: Int
    let level: Int
    let hasWaypoint: Bool
    let isTownArea: Bool
    let parentTownAreaID: String?

    enum CodingKeys: String, CodingKey {
        case id, name, act, level
        case mapName = "map_name"
        case hasWaypoint = "has_waypoint"
        case isTownArea = "is_town_area"
        case parentTownAreaID = "parent_town_area_id"
    }
}

struct QuestRecord: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let act: String
}

struct RouteSnapshotManifest: Codable, Hashable, Sendable {
    let schemaVersion: Int
    let repository: String
    let commit: String
    let generatedAt: String
}

enum BanditChoice: String, Codable, CaseIterable, Sendable {
    case killAll = "Kill All"
    case oak = "Oak"
    case kraityn = "Kraityn"
    case alira = "Alira"
}

struct RouteConfiguration: Codable, Equatable, Sendable {
    var leagueStart = true
    var includeLibrary = true
    var bandit: BanditChoice = .killAll

    var definitions: Set<String> {
        var result: Set<String> = []
        if leagueStart { result.insert("LEAGUE_START") }
        if includeLibrary { result.insert("LIBRARY") }
        switch bandit {
        case .killAll: result.insert("BANDIT_KILL")
        case .oak: result.insert("BANDIT_OAK")
        case .kraityn: result.insert("BANDIT_KRAITYN")
        case .alira: result.insert("BANDIT_ALIRA")
        }
        return result
    }
}

enum RouteFragmentKind: String, Codable, Hashable, Sendable {
    case area, enter, waypoint, waypointGet, portal, logout
    case kill, arena, quest, questText, generic, trial, ascend, crafting, direction
    case text, unknown
}

struct RouteFragment: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let kind: RouteFragmentKind
    let value: String
    let parameters: [String]

    init(kind: RouteFragmentKind, value: String, parameters: [String] = []) {
        self.id = UUID()
        self.kind = kind
        self.value = value
        self.parameters = parameters
    }
}

struct RouteStep: Identifiable, Codable, Hashable, Sendable {
    let id: String
    let act: Int
    let line: Int
    let rawText: String
    let displayText: String
    let fragments: [RouteFragment]
    var hints: [String]
    let expectedAreaID: String?
}

struct RouteSection: Identifiable, Codable, Hashable, Sendable {
    var id: String { name }
    let name: String
    let act: Int
    var steps: [RouteStep]
}

struct CampaignRoute: Codable, Hashable, Sendable {
    let source: String
    let sections: [RouteSection]

    var steps: [RouteStep] { sections.flatMap(\.steps) }
    var expectedAreaIDs: [String] { steps.compactMap(\.expectedAreaID) }
}

struct ProgressState: Codable, Equatable, Sendable {
    var stepIndex = 0
    var currentAreaID: String?
    var completedStepIDs: Set<String> = []
    var updatedAt = Date()
}

struct AreaDetection: Equatable, Sendable {
    let text: String
    let areaID: String?
    let confidence: Float
    let timestamp: Date
}

enum OCRStatus: Equatable, Sendable {
    case disabled
    case waitingForGeForceNow
    case permissionRequired
    case scanning
    case recognized(String)
    case lowConfidence
    case failed(String)
}

