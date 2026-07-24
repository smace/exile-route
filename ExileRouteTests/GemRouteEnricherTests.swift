import XCTest
@testable import ExileRoute

final class GemRouteEnricherTests: XCTestCase {
    private let fireballID = "Metadata/Items/Gems/SkillGemFireball"
    private let clarityID = "Metadata/Items/Gems/SkillGemClarity"
    private let sparkID = "Metadata/Items/Gems/SkillGemSpark"

    func testAddsOneQuestRewardThenAvailableVendorPurchases() {
        let result = enricher().enrich(route(), with: build(gemIDs: [fireballID, clarityID]))
        let gemSteps = result.route.steps.compactMap { $0.gemAcquisition }

        XCTAssertEqual(gemSteps.map(\.gemName), ["Fireball", "Clarity"])
        XCTAssertEqual(gemSteps.map(\.kind), [.quest, .vendor])
        XCTAssertEqual(gemSteps.map(\.npc), ["Tarkleigh", "Nessa"])
        XCTAssertNil(gemSteps[0].cost)
        XCTAssertEqual(gemSteps[1].cost, "Orb of Transmutation")
        XCTAssertEqual(gemSteps[1].contexts, ["Auras"])
        XCTAssertEqual(result.route.steps[1].id, "campaign-q1-gem-quest-\(fireballID)")
        XCTAssertEqual(result.route.steps[2].id, "campaign-q1-gem-vendor-\(clarityID)")
    }

    func testStartingGemIsNotScheduledAndUnavailableGemProducesWarning() {
        let catalog = catalog(startGemID: fireballID)
        let result = GemRouteEnricher(quests: quests(), catalog: catalog)
            .enrich(route(), with: build(gemIDs: [fireballID, sparkID]))

        XCTAssertTrue(result.route.steps.compactMap(\.gemAcquisition).isEmpty)
        XCTAssertEqual(result.warnings.map(\.gemID), [sparkID])
        XCTAssertEqual(result.warnings.first?.kind, .unavailableGem)
    }

    func testSelectsAtMostOneQuestRewardAcrossMultipleOffers() {
        let firstOffer = QuestRewardOffer(
            questNPC: "Tarkleigh",
            quest: [fireballID: QuestRewardEligibility(classes: ["Witch"])],
            vendor: [:]
        )
        let secondOffer = QuestRewardOffer(
            questNPC: "Nessa",
            quest: [clarityID: QuestRewardEligibility(classes: ["Witch"])],
            vendor: [:]
        )
        let questRecords = ["q1": QuestRecord(
            id: "q1",
            name: "Enemy at the Gate",
            act: "1",
            rewardOffers: ["first": firstOffer, "second": secondOffer]
        )]
        let quest = RouteFragment(
            kind: .quest,
            value: "Enemy at the Gate",
            parameters: ["q1", "first", "second"]
        )
        let route = CampaignRoute(
            source: "fixture",
            sections: [RouteSection(name: "Act 1", act: 1, steps: [RouteStep(
                id: "campaign-q1",
                act: 1,
                line: 10,
                rawText: "Hand in quest",
                displayText: "Hand in quest",
                fragments: [quest],
                hints: [],
                contextAreaID: "town",
                expectedAreaID: nil
            )])]
        )

        let result = GemRouteEnricher(quests: questRecords, catalog: catalog())
            .enrich(route, with: build(gemIDs: [fireballID, clarityID]))

        XCTAssertEqual(result.route.steps.compactMap(\.gemAcquisition).map(\.gemName), ["Fireball"])
        XCTAssertEqual(result.warnings.map(\.gemID), [clarityID])
    }

    private func route() -> CampaignRoute {
        let quest = RouteFragment(kind: .quest, value: "Enemy at the Gate", parameters: ["q1"])
        let step = RouteStep(
            id: "campaign-q1",
            act: 1,
            line: 10,
            rawText: "Hand in quest",
            displayText: "Hand in quest",
            fragments: [quest],
            hints: [],
            contextAreaID: "town",
            expectedAreaID: nil
        )
        return CampaignRoute(
            source: "fixture",
            sections: [RouteSection(name: "Act 1", act: 1, steps: [step])]
        )
    }

    private func build(gemIDs: [String]) -> ImportedBuild {
        ImportedBuild(
            characterClass: "Witch",
            skillSets: [ImportedSkillSet(id: "0", name: "Levelling", gemIDs: gemIDs)],
            requiredGems: gemIDs.map {
                RequiredGem(gemID: $0, contexts: $0 == clarityID ? ["Auras"] : ["Levelling"])
            },
            warnings: [],
            importedAt: Date(timeIntervalSince1970: 1)
        )
    }

    private func enricher() -> GemRouteEnricher {
        GemRouteEnricher(quests: quests(), catalog: catalog())
    }

    private func quests() -> [String: QuestRecord] {
        let offer = QuestRewardOffer(
            questNPC: "Tarkleigh",
            quest: [
                fireballID: QuestRewardEligibility(classes: ["Witch"]),
                clarityID: QuestRewardEligibility(classes: ["Witch"])
            ],
            vendor: [
                fireballID: QuestVendorReward(classes: ["Witch"], npc: "Nessa"),
                clarityID: QuestVendorReward(classes: ["Witch"], npc: "Nessa")
            ]
        )
        return ["q1": QuestRecord(
            id: "q1",
            name: "Enemy at the Gate",
            act: "1",
            rewardOffers: ["q1": offer]
        )]
    }

    private func catalog(startGemID: String = "start") -> GemCatalog {
        GemCatalog(
            gems: [
                fireballID: GemRecord(
                    id: fireballID,
                    name: "Fireball",
                    primaryAttribute: "intelligence",
                    requiredLevel: 1,
                    isSupport: false
                ),
                clarityID: GemRecord(
                    id: clarityID,
                    name: "Clarity",
                    primaryAttribute: "intelligence",
                    requiredLevel: 10,
                    isSupport: false
                ),
                sparkID: GemRecord(
                    id: sparkID,
                    name: "Spark",
                    primaryAttribute: "intelligence",
                    requiredLevel: 1,
                    isSupport: false
                )
            ],
            characters: [
                "Witch": CharacterRecord(startGemID: startGemID, chestGemID: "chest")
            ],
            vaalGemLookup: [:],
            awakenedGemLookup: [:]
        )
    }
}
