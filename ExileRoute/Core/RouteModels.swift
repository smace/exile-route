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
    let rewardOffers: [String: QuestRewardOffer]

    enum CodingKeys: String, CodingKey {
        case id, name, act
        case rewardOffers = "reward_offers"
    }
}

struct QuestRewardEligibility: Codable, Hashable, Sendable {
    let classes: [String]
}

struct QuestVendorReward: Codable, Hashable, Sendable {
    let classes: [String]
    let npc: String
}

struct QuestRewardOffer: Codable, Hashable, Sendable {
    let questNPC: String
    let quest: [String: QuestRewardEligibility]
    let vendor: [String: QuestVendorReward]

    enum CodingKeys: String, CodingKey {
        case questNPC = "quest_npc"
        case quest, vendor
    }
}

struct GemRecord: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let primaryAttribute: String
    let requiredLevel: Int
    let isSupport: Bool

    enum CodingKeys: String, CodingKey {
        case id, name
        case primaryAttribute = "primary_attribute"
        case requiredLevel = "required_level"
        case isSupport = "is_support"
    }
}

struct CharacterRecord: Codable, Hashable, Sendable {
    let startGemID: String
    let chestGemID: String

    enum CodingKeys: String, CodingKey {
        case startGemID = "start_gem_id"
        case chestGemID = "chest_gem_id"
    }
}

struct GemCatalog: Hashable, Sendable {
    let gems: [String: GemRecord]
    let characters: [String: CharacterRecord]
    let vaalGemLookup: [String: String]
    let awakenedGemLookup: [String: String]
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
    case gem, text, unknown
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
    let contextAreaID: String
    let expectedAreaID: String?
    let gemAcquisition: GemAcquisition?

    init(
        id: String,
        act: Int,
        line: Int,
        rawText: String,
        displayText: String,
        fragments: [RouteFragment],
        hints: [String],
        contextAreaID: String,
        expectedAreaID: String?,
        gemAcquisition: GemAcquisition? = nil
    ) {
        self.id = id
        self.act = act
        self.line = line
        self.rawText = rawText
        self.displayText = displayText
        self.fragments = fragments
        self.hints = hints
        self.contextAreaID = contextAreaID
        self.expectedAreaID = expectedAreaID
        self.gemAcquisition = gemAcquisition
    }
}

struct RouteVisit: Identifiable, Hashable, Sendable {
    let id: String
    let areaID: String
    let stepRange: Range<Int>
}

enum RouteObjectiveState: String, Hashable, Sendable {
    case completed
    case active
    case pending
    case skipped
}

struct RouteObjective: Identifiable, Hashable, Sendable {
    var id: String { step.id }
    let stepIndex: Int
    let step: RouteStep
    let state: RouteObjectiveState
}

enum TrackingTransition: Equatable, Sendable {
    case none
    case area(expectedAreaID: String)
    case logout(expectedTownID: String)

    var expectedAreaID: String? {
        switch self {
        case .none: nil
        case .area(let areaID), .logout(let areaID): areaID
        }
    }

    var isLogout: Bool {
        if case .logout = self { return true }
        return false
    }
}

struct TrackingContext: Equatable, Sendable {
    let stepID: String?
    let currentAreaID: String?
    let transition: TrackingTransition

    static let empty = TrackingContext(stepID: nil, currentAreaID: nil, transition: .none)

    var automaticAreaIDs: Set<String> {
        Set([currentAreaID, transition.expectedAreaID].compactMap { $0 })
    }
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

    var visits: [RouteVisit] {
        let allSteps = steps
        guard let first = allSteps.first else { return [] }

        var result: [RouteVisit] = []
        var start = 0
        var areaID = first.contextAreaID

        for index in 1..<allSteps.count where allSteps[index].contextAreaID != areaID {
            result.append(RouteVisit(
                id: "\(allSteps[start].id)-visit",
                areaID: areaID,
                stepRange: start..<index
            ))
            start = index
            areaID = allSteps[index].contextAreaID
        }

        result.append(RouteVisit(
            id: "\(allSteps[start].id)-visit",
            areaID: areaID,
            stepRange: start..<allSteps.count
        ))
        return result
    }

    func visit(containing stepIndex: Int) -> RouteVisit? {
        visits.first { $0.stepRange.contains(stepIndex) }
    }
}

struct ProgressState: Codable, Equatable, Sendable {
    var stepIndex: Int
    var currentAreaID: String?
    var completedStepIDs: Set<String>
    var skippedStepIDs: Set<String>
    var updatedAt: Date

    init(
        stepIndex: Int = 0,
        currentAreaID: String? = nil,
        completedStepIDs: Set<String> = [],
        skippedStepIDs: Set<String> = [],
        updatedAt: Date = Date()
    ) {
        self.stepIndex = stepIndex
        self.currentAreaID = currentAreaID
        self.completedStepIDs = completedStepIDs
        self.skippedStepIDs = skippedStepIDs
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stepIndex = try container.decodeIfPresent(Int.self, forKey: .stepIndex) ?? 0
        currentAreaID = try container.decodeIfPresent(String.self, forKey: .currentAreaID)
        completedStepIDs = try container.decodeIfPresent(Set<String>.self, forKey: .completedStepIDs) ?? []
        skippedStepIDs = try container.decodeIfPresent(Set<String>.self, forKey: .skippedStepIDs) ?? []
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt) ?? Date()
    }
}

struct AreaProgressionResult: Equatable, Sendable {
    let previousAreaID: String?
    let areaID: String
    let skippedStepIDs: [String]
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
    case returningToTown
    case recovering
    case noFrames
    case recognized(String)
    case lowConfidence
    case failed(String)
}
