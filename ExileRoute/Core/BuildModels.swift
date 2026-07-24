import Foundation

struct ImportedSkillSet: Codable, Equatable, Hashable, Sendable, Identifiable {
    let id: String
    let name: String
    let gemIDs: [String]
}

struct RequiredGem: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String { gemID }
    let gemID: String
    let contexts: [String]
}

enum PoBImportWarningKind: String, Codable, Sendable {
    case unknownGem
    case unavailableGem
}

struct PoBImportWarning: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: String { "\(kind.rawValue)-\(gemID)" }
    let kind: PoBImportWarningKind
    let gemID: String
    let message: String
}

struct ImportedBuild: Codable, Equatable, Hashable, Sendable {
    let characterClass: String
    let skillSets: [ImportedSkillSet]
    let requiredGems: [RequiredGem]
    let warnings: [PoBImportWarning]
    let importedAt: Date
}

struct PoBImportResult: Equatable, Sendable {
    let build: ImportedBuild
}

enum GemAcquisitionKind: String, Codable, Hashable, Sendable {
    case quest
    case vendor
}

struct GemAcquisition: Codable, Equatable, Hashable, Sendable {
    let gemID: String
    let gemName: String
    let primaryAttribute: String
    let kind: GemAcquisitionKind
    let npc: String
    let cost: String?
    let contexts: [String]
    let parentStepID: String
}

struct GemRouteEnrichment: Sendable {
    let route: CampaignRoute
    let warnings: [PoBImportWarning]
}
