import Foundation

struct GemRouteEnricher: Sendable {
    let quests: [String: QuestRecord]
    let catalog: GemCatalog

    func enrich(_ baseRoute: CampaignRoute, with build: ImportedBuild) -> GemRouteEnrichment {
        var acquired = Set<String>()
        var rewardedQuestIDs = Set<String>()
        if let character = catalog.characters[build.characterClass] {
            acquired.insert(character.startGemID)
            acquired.insert(character.chestGemID)
        }
        var warnings = build.warnings
        var enrichedSections: [RouteSection] = []

        for baseSection in baseRoute.sections {
            var steps: [RouteStep] = []
            for baseStep in baseSection.steps {
                steps.append(baseStep)
                for fragment in baseStep.fragments where fragment.kind == .quest {
                    guard let questID = fragment.parameters.first,
                          let quest = quests[questID] else { continue }
                    let explicitOffers = Array(fragment.parameters.dropFirst())
                    let rewardOfferIDs = explicitOffers.isEmpty ? [questID] : explicitOffers
                    for rewardOfferID in rewardOfferIDs {
                        guard let offer = quest.rewardOffers[rewardOfferID] else { continue }
                        if !rewardedQuestIDs.contains(questID),
                           let reward = firstQuestReward(
                            in: offer,
                            build: build,
                            excluding: acquired
                        ) {
                            acquired.insert(reward.gemID)
                            rewardedQuestIDs.insert(questID)
                            steps.append(step(
                                for: reward,
                                kind: .quest,
                                npc: offer.questNPC,
                                parent: baseStep
                            ))
                        }
                        for reward in vendorRewards(
                            in: offer,
                            build: build,
                            excluding: acquired
                        ) {
                            acquired.insert(reward.gemID)
                            let npc = offer.vendor[reward.gemID]?.npc ?? offer.questNPC
                            steps.append(step(
                                for: reward,
                                kind: .vendor,
                                npc: npc,
                                parent: baseStep
                            ))
                        }
                    }
                }
            }
            enrichedSections.append(RouteSection(name: baseSection.name, act: baseSection.act, steps: steps))
        }

        for required in build.requiredGems where !acquired.contains(required.gemID) {
            if warnings.contains(where: {
                $0.gemID == required.gemID && $0.kind == .unknownGem
            }) {
                continue
            }
            let name = catalog.gems[required.gemID]?.name ?? required.gemID
            let warning = PoBImportWarning(
                kind: .unavailableGem,
                gemID: required.gemID,
                message: "\(name) is not available from a campaign quest or vendor for \(build.characterClass)."
            )
            if !warnings.contains(where: { $0.id == warning.id }) { warnings.append(warning) }
        }
        return GemRouteEnrichment(
            route: CampaignRoute(source: baseRoute.source, sections: enrichedSections),
            warnings: warnings
        )
    }

    private func firstQuestReward(
        in offer: QuestRewardOffer,
        build: ImportedBuild,
        excluding acquired: Set<String>
    ) -> RequiredGem? {
        build.requiredGems.first { required in
            guard !acquired.contains(required.gemID),
                  catalog.gems[required.gemID] != nil,
                  let eligibility = offer.quest[required.gemID] else { return false }
            return supports(build.characterClass, classes: eligibility.classes)
        }
    }

    private func vendorRewards(
        in offer: QuestRewardOffer,
        build: ImportedBuild,
        excluding acquired: Set<String>
    ) -> [RequiredGem] {
        build.requiredGems.filter { required in
            guard !acquired.contains(required.gemID),
                  catalog.gems[required.gemID] != nil,
                  let eligibility = offer.vendor[required.gemID] else { return false }
            return supports(build.characterClass, classes: eligibility.classes)
        }
    }

    private func supports(_ characterClass: String, classes: [String]) -> Bool {
        classes.isEmpty || classes.contains(characterClass)
    }

    private func step(
        for required: RequiredGem,
        kind: GemAcquisitionKind,
        npc: String,
        parent: RouteStep
    ) -> RouteStep {
        let gem = catalog.gems[required.gemID]!
        let cost = kind == .vendor ? cost(for: gem.requiredLevel) : nil
        let acquisition = GemAcquisition(
            gemID: gem.id,
            gemName: gem.name,
            primaryAttribute: gem.primaryAttribute,
            kind: kind,
            npc: npc,
            cost: cost,
            contexts: required.contexts,
            parentStepID: parent.id
        )
        let verb = kind == .quest ? "Take" : "Buy"
        let costText = cost.map { " • \($0)" } ?? ""
        let displayText = "\(verb) \(gem.name) from \(npc)\(costText)"
        let contextHint = required.contexts.isEmpty
            ? []
            : ["For \(required.contexts.joined(separator: ", "))"]
        return RouteStep(
            id: "\(parent.id)-gem-\(kind.rawValue)-\(gem.id)",
            act: parent.act,
            line: parent.line,
            rawText: displayText,
            displayText: displayText,
            fragments: [RouteFragment(kind: .gem, value: gem.name, parameters: [gem.id])],
            hints: contextHint,
            contextAreaID: parent.contextAreaID,
            expectedAreaID: nil,
            gemAcquisition: acquisition
        )
    }

    private func cost(for requiredLevel: Int) -> String {
        switch requiredLevel {
        case ..<8: "Scroll of Wisdom"
        case ..<16: "Orb of Transmutation"
        case ..<28: "Orb of Alteration"
        case ..<38: "Orb of Chance"
        default: "Orb of Alchemy"
        }
    }
}
