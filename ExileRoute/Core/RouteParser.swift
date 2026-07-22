import Foundation

enum RouteParserError: LocalizedError, Equatable {
    case emptyRoute
    case unbalancedCondition(line: Int)
    case missingEndCondition

    var errorDescription: String? {
        switch self {
        case .emptyRoute: "The route contains no actionable steps."
        case .unbalancedCondition(let line): "Unexpected #endif at line \(line)."
        case .missingEndCondition: "The route contains an unterminated conditional block."
        }
    }
}

struct RouteParser: Sendable {
    let areas: [String: AreaRecord]
    let quests: [String: QuestRecord]

    func parse(sources: [(name: String, contents: String)], configuration: RouteConfiguration) throws -> CampaignRoute {
        var sections: [RouteSection] = []
        var currentAreaID = "1_1_1"
        var lastTownAreaID = "1_1_town"
        var portalAreaID: String?
        var conditionStack: [Bool] = []

        for (sourceIndex, source) in sources.enumerated() {
            var sectionName = source.name
            var section = RouteSection(name: sectionName, act: sourceIndex + 1, steps: [])
            let lines = source.contents.components(separatedBy: .newlines)

            for (zeroLine, originalLine) in lines.enumerated() {
                let lineNumber = zeroLine + 1
                let line = originalLine.trimmingCharacters(in: .whitespaces)
                guard !line.isEmpty else { continue }

                if line.hasPrefix("#section") {
                    sectionName = String(line.dropFirst("#section".count)).trimmingCharacters(in: .whitespaces)
                    section = RouteSection(name: sectionName, act: sourceIndex + 1, steps: section.steps)
                    continue
                }

                if line.hasPrefix("#ifdef") {
                    let definition = String(line.dropFirst("#ifdef".count)).trimmingCharacters(in: .whitespaces)
                    let parentEnabled = conditionStack.allSatisfy { $0 }
                    conditionStack.append(parentEnabled && configuration.definitions.contains(definition))
                    continue
                }

                if line.hasPrefix("#ifndef") {
                    let definition = String(line.dropFirst("#ifndef".count)).trimmingCharacters(in: .whitespaces)
                    let parentEnabled = conditionStack.allSatisfy { $0 }
                    conditionStack.append(parentEnabled && !configuration.definitions.contains(definition))
                    continue
                }

                if line == "#endif" {
                    guard !conditionStack.isEmpty else { throw RouteParserError.unbalancedCondition(line: lineNumber) }
                    conditionStack.removeLast()
                    continue
                }

                guard conditionStack.allSatisfy({ $0 }) else { continue }

                if line.hasPrefix("#sub") {
                    let hintSource = String(line.dropFirst("#sub".count)).trimmingCharacters(in: .whitespaces)
                    guard !section.steps.isEmpty else { continue }
                    let rendered = render(hintSource)
                    section.steps[section.steps.count - 1].hints.append(rendered.text)
                    continue
                }

                let rendered = render(line)
                let contextAreaID = currentAreaID
                var expectedAreaID: String?

                for fragment in rendered.fragments {
                    switch fragment.kind {
                    case .enter, .waypoint:
                        if let target = fragment.parameters.first, areas[target] != nil {
                            currentAreaID = target
                            expectedAreaID = target
                            if areas[target]?.isTownArea == true { lastTownAreaID = target }
                        }
                    case .logout:
                        let destination = areas[currentAreaID]?.parentTownAreaID ?? lastTownAreaID
                        currentAreaID = destination
                        lastTownAreaID = destination
                        expectedAreaID = destination
                    case .portal:
                        if fragment.parameters.first == "set" {
                            portalAreaID = currentAreaID
                        } else if fragment.parameters.first == "use", let destination = portalAreaID {
                            currentAreaID = destination
                            expectedAreaID = destination
                        }
                    default:
                        break
                    }
                }

                let stepID = "act-\(sourceIndex + 1)-line-\(lineNumber)"
                section.steps.append(RouteStep(
                    id: stepID,
                    act: sourceIndex + 1,
                    line: lineNumber,
                    rawText: line,
                    displayText: rendered.text,
                    fragments: rendered.fragments,
                    hints: [],
                    contextAreaID: contextAreaID,
                    expectedAreaID: expectedAreaID
                ))
            }
            sections.append(section)
        }

        guard conditionStack.isEmpty else { throw RouteParserError.missingEndCondition }
        guard sections.contains(where: { !$0.steps.isEmpty }) else { throw RouteParserError.emptyRoute }
        return CampaignRoute(source: sources.map(\.contents).joined(separator: "\n"), sections: sections)
    }

    private func render(_ source: String) -> (text: String, fragments: [RouteFragment]) {
        let expression = try! NSRegularExpression(pattern: #"\{([^}]+)\}"#)
        let range = NSRange(source.startIndex..<source.endIndex, in: source)
        let matches = expression.matches(in: source, range: range)
        var output = source
        var fragments: [RouteFragment] = []

        for match in matches.reversed() {
            guard let tokenRange = Range(match.range(at: 1), in: source),
                  let fullRange = Range(match.range(at: 0), in: output) else { continue }
            let token = String(source[tokenRange])
            let components = token.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            let name = components.first ?? ""
            let parameters = Array(components.dropFirst())
            let fragment = makeFragment(name: name, parameters: parameters)
            fragments.insert(fragment, at: 0)
            output.replaceSubrange(fullRange, with: fragment.value)
        }

        if let comment = output.range(of: " #") { output.removeSubrange(comment.lowerBound...) }
        output = output.replacingOccurrences(of: "➞", with: "→")
        return (output.trimmingCharacters(in: .whitespaces), fragments)
    }

    private func makeFragment(name: String, parameters: [String]) -> RouteFragment {
        let first = parameters.first ?? ""
        switch name {
        case "enter": return RouteFragment(kind: .enter, value: areas[first]?.name ?? first, parameters: parameters)
        case "area": return RouteFragment(kind: .area, value: areas[first]?.name ?? first, parameters: parameters)
        case "waypoint":
            return RouteFragment(kind: .waypoint, value: first.isEmpty ? "waypoint" : (areas[first]?.name ?? first), parameters: parameters)
        case "waypoint_get": return RouteFragment(kind: .waypointGet, value: "waypoint")
        case "portal": return RouteFragment(kind: .portal, value: first == "set" ? "a portal" : "the portal", parameters: parameters)
        case "logout": return RouteFragment(kind: .logout, value: "log out")
        case "kill": return RouteFragment(kind: .kill, value: first, parameters: parameters)
        case "arena": return RouteFragment(kind: .arena, value: first, parameters: parameters)
        case "quest": return RouteFragment(kind: .quest, value: quests[first]?.name ?? first, parameters: parameters)
        case "quest_text": return RouteFragment(kind: .questText, value: first, parameters: parameters)
        case "generic": return RouteFragment(kind: .generic, value: first, parameters: parameters)
        case "trial": return RouteFragment(kind: .trial, value: "Labyrinth Trial")
        case "ascend": return RouteFragment(kind: .ascend, value: "\(first.capitalized) Labyrinth", parameters: parameters)
        case "crafting": return RouteFragment(kind: .crafting, value: "crafting recipe", parameters: parameters)
        case "dir": return RouteFragment(kind: .direction, value: directionLabel(first), parameters: parameters)
        default: return RouteFragment(kind: .unknown, value: first.isEmpty ? name : first, parameters: parameters)
        }
    }

    private func directionLabel(_ value: String) -> String {
        switch value {
        case "0", "360": "↑"
        case "45": "↗"
        case "90": "→"
        case "135": "↘"
        case "180": "↓"
        case "225": "↙"
        case "270": "←"
        case "315": "↖"
        default: value + "°"
        }
    }
}
