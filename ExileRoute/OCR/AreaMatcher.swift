import Foundation

struct OCRCandidate: Equatable, Sendable {
    let text: String
    let confidence: Float
    let boundingBox: CGRect?

    init(text: String, confidence: Float, boundingBox: CGRect? = nil) {
        self.text = text
        self.confidence = confidence
        self.boundingBox = boundingBox
    }
}

struct AreaMatcher: Sendable {
    private struct Entry: Sendable {
        let id: String
        let name: String
        let normalizedName: String
    }

    private let entries: [Entry]

    init(areas: [String: AreaRecord]) {
        entries = areas.values.map { Entry(id: $0.id, name: $0.name, normalizedName: Self.normalize($0.name)) }
    }

    func match(_ candidates: [OCRCandidate], expectedAreaIDs: [String] = [], timestamp: Date = Date()) -> AreaDetection? {
        var expectedRanks: [String: Int] = [:]
        for (offset, areaID) in expectedAreaIDs.enumerated() where expectedRanks[areaID] == nil {
            expectedRanks[areaID] = offset
        }
        var best: (entry: Entry, text: String, score: Float, expectedRank: Int?)?

        for candidate in candidates where !candidate.text.isEmpty {
            let normalizedText = Self.normalize(candidate.text)
            guard normalizedText.count >= 3 else { continue }
            for entry in entries {
                let similarity = Self.similarity(normalizedText, entry.normalizedName)
                let isNearTitleLength = abs(normalizedText.count - entry.normalizedName.count) <= 5
                let contains = isNearTitleLength && (
                    normalizedText.contains(entry.normalizedName) || entry.normalizedName.contains(normalizedText)
                )
                var score = contains ? max(candidate.confidence, 0.84) : (similarity * 0.72 + candidate.confidence * 0.28)
                let rank = expectedRanks[entry.id]
                if rank != nil { score += 0.08 }
                guard similarity >= 0.62, score >= 0.72 else { continue }

                if let current = best {
                    let winsExpectedTie = abs(score - current.score) < 0.04 && (rank ?? .max) < (current.expectedRank ?? .max)
                    guard score > current.score || winsExpectedTie else { continue }
                }
                best = (entry, candidate.text, min(score, 1), rank)
            }
        }

        guard let best else { return nil }
        return AreaDetection(text: best.entry.name, areaID: best.entry.id, confidence: best.score, timestamp: timestamp)
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US"))
            .unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character(String($0)) : " " }
            .reduce(into: "") { result, character in
                if character == " ", result.last == " " { return }
                result.append(character)
            }
            .trimmingCharacters(in: .whitespaces)
    }

    private static func similarity(_ lhs: String, _ rhs: String) -> Float {
        let left = Array(lhs)
        let right = Array(rhs)
        guard !left.isEmpty, !right.isEmpty else { return 0 }
        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            for (rightIndex, rightCharacter) in right.enumerated() {
                current.append(min(
                    current[rightIndex] + 1,
                    previous[rightIndex + 1] + 1,
                    previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                ))
            }
            previous = current
        }
        return 1 - Float(previous[right.count]) / Float(max(left.count, right.count))
    }
}
