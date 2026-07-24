import Compression
import Foundation

enum PoBImportError: LocalizedError, Equatable {
    case emptyInput
    case invalidURL
    case unsupportedHost
    case badResponse
    case compressedInputTooLarge
    case invalidCode
    case decompressedInputTooLarge
    case invalidXML
    case missingCharacterClass
    case missingSkills

    var errorDescription: String? {
        switch self {
        case .emptyInput: "Enter a Path of Building code or supported HTTPS URL."
        case .invalidURL: "Only HTTPS Path of Building URLs are supported."
        case .unsupportedHost: "This Path of Building host is not supported."
        case .badResponse: "The Path of Building code could not be downloaded."
        case .compressedInputTooLarge: "The Path of Building code exceeds the 1 MB safety limit."
        case .invalidCode: "The Path of Building code is not valid Base64URL/zlib data."
        case .decompressedInputTooLarge: "The expanded Path of Building XML exceeds the 10 MB safety limit."
        case .invalidXML: "The Path of Building XML is malformed or too complex."
        case .missingCharacterClass: "The Path of Building file does not contain a character class."
        case .missingSkills: "The Path of Building file does not contain any enabled skills."
        }
    }
}

struct PoBImportService: Sendable {
    let catalog: GemCatalog
    let session: URLSession
    let maximumCompressedBytes: Int
    let maximumDecompressedBytes: Int

    init(
        catalog: GemCatalog,
        session: URLSession = .shared,
        maximumCompressedBytes: Int = 1_000_000,
        maximumDecompressedBytes: Int = 10_000_000
    ) {
        self.catalog = catalog
        self.session = session
        self.maximumCompressedBytes = maximumCompressedBytes
        self.maximumDecompressedBytes = maximumDecompressedBytes
    }

    func `import`(from input: String) async throws -> PoBImportResult {
        let source = try await sourceCode(from: input)
        return try decode(source)
    }

    func decode(_ code: String) throws -> PoBImportResult {
        let compactCode = code.filter { !$0.isWhitespace }
        guard !compactCode.isEmpty else { throw PoBImportError.emptyInput }
        guard compactCode.utf8.count <= maximumCompressedBytes * 2 else {
            throw PoBImportError.compressedInputTooLarge
        }
        guard let compressed = decodeBase64URL(compactCode),
              compressed.count <= maximumCompressedBytes else {
            throw PoBImportError.invalidCode
        }
        let xml = try inflate(compressed)
        let parserDelegate = PoBXMLParserDelegate()
        let parser = XMLParser(data: xml)
        parser.shouldResolveExternalEntities = false
        parser.delegate = parserDelegate
        guard parser.parse(), parserDelegate.failure == nil else {
            throw parserDelegate.failure ?? PoBImportError.invalidXML
        }
        guard let characterClass = parserDelegate.characterClass?.nilIfEmpty else {
            throw PoBImportError.missingCharacterClass
        }
        guard !parserDelegate.skillSets.isEmpty else { throw PoBImportError.missingSkills }

        var orderedGemIDs: [String] = []
        var contextsByGemID: [String: [String]] = [:]
        var warnings: [PoBImportWarning] = []
        var importedSkillSets: [ImportedSkillSet] = []

        for (index, parsedSet) in parserDelegate.skillSets.enumerated() {
            var setGemIDs: [String] = []
            for parsedGem in parsedSet.gems {
                let mappedID = normalizedGemID(parsedGem.id)
                if catalog.gems[mappedID] == nil {
                    if !warnings.contains(where: { $0.gemID == mappedID && $0.kind == .unknownGem }) {
                        warnings.append(PoBImportWarning(
                            kind: .unknownGem,
                            gemID: mappedID,
                            message: "Unknown gem identifier: \(mappedID)"
                        ))
                    }
                }
                if !setGemIDs.contains(mappedID) { setGemIDs.append(mappedID) }
                if contextsByGemID[mappedID] == nil {
                    orderedGemIDs.append(mappedID)
                    contextsByGemID[mappedID] = []
                }
                let context = cleanPoBText(parsedGem.context).nilIfEmpty ?? parsedSet.name
                if contextsByGemID[mappedID]?.contains(context) == false {
                    contextsByGemID[mappedID]?.append(context)
                }
            }
            if !setGemIDs.isEmpty {
                let name = cleanPoBText(parsedSet.name).nilIfEmpty ?? "Skill Set \(index + 1)"
                importedSkillSets.append(ImportedSkillSet(
                    id: "\(index)-\(name)",
                    name: name,
                    gemIDs: setGemIDs
                ))
            }
        }

        guard !orderedGemIDs.isEmpty else { throw PoBImportError.missingSkills }
        let requiredGems = orderedGemIDs.map {
            RequiredGem(gemID: $0, contexts: contextsByGemID[$0] ?? [])
        }
        return PoBImportResult(build: ImportedBuild(
            characterClass: characterClass,
            skillSets: importedSkillSets,
            requiredGems: requiredGems,
            warnings: warnings,
            importedAt: Date()
        ))
    }

    private func sourceCode(from input: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw PoBImportError.emptyInput }
        guard let candidate = URL(string: trimmed), candidate.scheme != nil else { return trimmed }
        let url = try rewrittenURL(candidate)
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse,
              200..<300 ~= http.statusCode,
              http.url?.scheme?.lowercased() == "https",
              let finalHost = http.url?.host?.lowercased(),
              Self.allowedHosts.contains(finalHost) else {
            throw PoBImportError.badResponse
        }
        guard data.count <= maximumCompressedBytes * 2 else {
            throw PoBImportError.compressedInputTooLarge
        }
        guard let code = String(data: data, encoding: .utf8) else { throw PoBImportError.badResponse }
        return code
    }

    private func rewrittenURL(_ url: URL) throws -> URL {
        guard url.scheme?.lowercased() == "https" else { throw PoBImportError.invalidURL }
        guard let host = url.host?.lowercased(), Self.allowedHosts.contains(host) else {
            throw PoBImportError.unsupportedHost
        }
        let components = url.pathComponents.filter { $0 != "/" }
        let raw: String
        switch host {
        case "pastebin.com":
            guard let identifier = components.last, !identifier.isEmpty else { throw PoBImportError.invalidURL }
            raw = "https://pastebin.com/raw/\(identifier)"
        case "pobb.in":
            guard let identifier = components.first, !identifier.isEmpty else { throw PoBImportError.invalidURL }
            raw = "https://pobb.in/\(identifier)/raw"
        case "poe.ninja":
            guard components.count >= 2, components[0] == "pob" else { throw PoBImportError.invalidURL }
            raw = "https://poe.ninja/pob/raw/\(components[1])"
        case "maxroll.gg":
            guard components.count >= 3, components[0] == "poe", components[1] == "pob" else {
                throw PoBImportError.invalidURL
            }
            raw = "https://maxroll.gg/poe/api/pob/\(components[2])"
        default:
            throw PoBImportError.unsupportedHost
        }
        guard let rewritten = URL(string: raw) else { throw PoBImportError.invalidURL }
        return rewritten
    }

    private func decodeBase64URL(_ code: String) -> Data? {
        var base64 = code.replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder != 0 { base64.append(String(repeating: "=", count: 4 - remainder)) }
        return Data(base64Encoded: base64)
    }

    private func inflate(_ compressed: Data) throws -> Data {
        guard compressed.count > 6 else { throw PoBImportError.invalidCode }
        let cmf = Int(compressed[compressed.startIndex])
        let flg = Int(compressed[compressed.startIndex + 1])
        guard cmf & 0x0F == 8,
              ((cmf << 8) + flg).isMultiple(of: 31),
              flg & 0x20 == 0 else {
            throw PoBImportError.invalidCode
        }
        let checksumBytes = compressed.suffix(4)
        let expectedChecksum = checksumBytes.reduce(UInt32.zero) {
            ($0 << 8) | UInt32($1)
        }
        let payload = compressed.dropFirst(2).dropLast(4)
        let output = try inflateRaw(Data(payload))
        guard adler32(output) == expectedChecksum else { throw PoBImportError.invalidCode }
        return output
    }

    private func inflateRaw(_ compressed: Data) throws -> Data {
        let destinationSize = 64 * 1024
        let destination = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
        defer { destination.deallocate() }
        var stream = compression_stream(
            dst_ptr: destination,
            dst_size: 0,
            src_ptr: UnsafePointer(destination),
            src_size: 0,
            state: nil
        )
        guard compression_stream_init(&stream, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) != COMPRESSION_STATUS_ERROR else {
            throw PoBImportError.invalidCode
        }
        defer { compression_stream_destroy(&stream) }

        var output = Data()

        return try compressed.withUnsafeBytes { rawBuffer in
            guard let source = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                throw PoBImportError.invalidCode
            }
            stream.src_ptr = source
            stream.src_size = compressed.count
            repeat {
                stream.dst_ptr = destination
                stream.dst_size = destinationSize
                let status = compression_stream_process(&stream, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                let produced = destinationSize - stream.dst_size
                if produced > 0 {
                    guard output.count + produced <= maximumDecompressedBytes else {
                        throw PoBImportError.decompressedInputTooLarge
                    }
                    output.append(destination, count: produced)
                }
                switch status {
                case COMPRESSION_STATUS_END:
                    return output
                case COMPRESSION_STATUS_OK:
                    continue
                default:
                    throw PoBImportError.invalidCode
                }
            } while true
        }
    }

    private func normalizedGemID(_ originalID: String) -> String {
        let aliases: [String: String] = [
            "Metadata/Items/Gems/Smite": "Metadata/Items/Gems/SkillGemSmite",
            "Metadata/Items/Gems/ConsecratedPath": "Metadata/Items/Gems/SkillGemConsecratedPath",
            "Metadata/Items/Gems/VaalAncestralWarchief": "Metadata/Items/Gems/SkillGemVaalAncestralWarchief",
            "Metadata/Items/Gems/HeraldOfAgony": "Metadata/Items/Gems/SkillGemHeraldOfAgony",
            "Metadata/Items/Gems/HeraldOfPurity": "Metadata/Items/Gems/SkillGemHeraldOfPurity",
            "Metadata/Items/Gems/ScourgeArrow": "Metadata/Items/Gems/SkillGemScourgeArrow",
            "Metadata/Items/Gems/RainOfSpores": "Metadata/Items/Gems/SkillGemToxicRain",
            "Metadata/Items/Gems/SummonRelic": "Metadata/Items/Gems/SkillGemSummonRelic",
            "Metadata/Items/Gems/SkillGemNewPhaseRun": "Metadata/Items/Gems/SkillGemPhaseRun",
            "Metadata/Items/Gems/SkillGemNewArcticArmour": "Metadata/Items/Gems/SkillGemArcticArmour"
        ]
        let aliased = aliases[originalID] ?? originalID
        let vaalNormalized = catalog.vaalGemLookup[aliased] ?? aliased
        return catalog.awakenedGemLookup[vaalNormalized] ?? vaalNormalized
    }

    private func adler32(_ data: Data) -> UInt32 {
        let modulus: UInt32 = 65_521
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in data {
            a = (a + UInt32(byte)) % modulus
            b = (b + a) % modulus
        }
        return (b << 16) | a
    }

    private func cleanPoBText(_ text: String) -> String {
        text.replacingOccurrences(
            of: #"\^(x[a-zA-Z0-9]{6}|[0-9])"#,
            with: "",
            options: .regularExpression
        )
    }

    private static let allowedHosts: Set<String> = [
        "pastebin.com", "pobb.in", "poe.ninja", "maxroll.gg"
    ]
}

private final class PoBXMLParserDelegate: NSObject, XMLParserDelegate {
    struct ParsedGem {
        let id: String
        let context: String
    }

    struct ParsedSkillSet {
        let name: String
        let gems: [ParsedGem]
    }

    struct SkillAccumulator {
        let enabled: Bool
        let label: String
        var gemIDs: [String] = []
    }

    var characterClass: String?
    var skillSets: [ParsedSkillSet] = []
    var failure: PoBImportError?

    private var currentSetName = "Default"
    private var currentSetGems: [ParsedGem] = []
    private var currentSkill: SkillAccumulator?
    private var recentEmptySkillLabel = ""
    private var insideSkillSet = false
    private var sawSkillSet = false
    private var elementCount = 0
    private var gemCount = 0

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        elementCount += 1
        guard elementCount <= 50_000 else {
            failure = .invalidXML
            parser.abortParsing()
            return
        }
        switch elementName {
        case "Build":
            characterClass = attributeDict["className"]
        case "SkillSet":
            finishLegacySetIfNeeded()
            sawSkillSet = true
            insideSkillSet = true
            currentSetName = attributeDict["title"] ?? "Default"
            currentSetGems = []
            recentEmptySkillLabel = ""
        case "Skill":
            currentSkill = SkillAccumulator(
                enabled: attributeDict["enabled"] != "false",
                label: attributeDict["label"] ?? ""
            )
        case "Gem":
            guard currentSkill?.enabled == true, let gemID = attributeDict["gemId"], !gemID.isEmpty else { return }
            gemCount += 1
            guard gemCount <= 5_000 else {
                failure = .invalidXML
                parser.abortParsing()
                return
            }
            currentSkill?.gemIDs.append(gemID)
        default:
            break
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        switch elementName {
        case "Skill":
            guard let skill = currentSkill, skill.enabled else {
                currentSkill = nil
                return
            }
            if skill.gemIDs.isEmpty {
                if !skill.label.isEmpty { recentEmptySkillLabel = skill.label }
            } else {
                let context = recentEmptySkillLabel.nilIfEmpty
                    ?? currentSetName.nilIfEmpty
                    ?? skill.label.nilIfEmpty
                    ?? "Default"
                currentSetGems.append(contentsOf: skill.gemIDs.map {
                    ParsedGem(id: $0, context: context)
                })
            }
            currentSkill = nil
        case "SkillSet":
            if !currentSetGems.isEmpty {
                skillSets.append(ParsedSkillSet(name: currentSetName, gems: currentSetGems))
            }
            insideSkillSet = false
            currentSetName = "Default"
            currentSetGems = []
            recentEmptySkillLabel = ""
        default:
            break
        }
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        finishLegacySetIfNeeded()
    }

    private func finishLegacySetIfNeeded() {
        guard !insideSkillSet, !currentSetGems.isEmpty else { return }
        if !sawSkillSet {
            skillSets.append(ParsedSkillSet(name: currentSetName, gems: currentSetGems))
        }
        currentSetGems = []
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
