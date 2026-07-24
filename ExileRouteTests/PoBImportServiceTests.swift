import Foundation
import XCTest
@testable import ExileRoute

final class PoBImportServiceTests: XCTestCase {
    private let malformedXMLCode = "eJyzCUgsyfBPcyrNzEnJzEu3swGzFJJzEouL_RJzU22VwjNLkjOU7GyCszNzcortALkDEXg"
    private let unknownGemCode = "eJyzCUgsyfBPcyrNzEnJzEu3swGzFJJzEouL_RJzU22VwjNLkjOU7GyCszNzcoqhtEJqXmJSTmqKrVJJUWkqUNY9NVchPTXXEygSmpedl1-epw8UUtK3s9EHa4DRQAP0wVYAaTSrAUZVMBM"

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testDecodesAllEnabledSkillSetsNormalizesAndDeduplicatesGems() throws {
        let result = try service().decode(TestPoBFixtures.multiSkillSet)

        XCTAssertEqual(result.build.characterClass, "Witch")
        XCTAssertEqual(result.build.skillSets.map(\.name), ["Levelling", "Auras"])
        XCTAssertEqual(result.build.requiredGems.map(\.gemID), [
            "Metadata/Items/Gems/SkillGemFireball",
            "Metadata/Items/Gems/SkillGemClarity"
        ])
        XCTAssertEqual(result.build.requiredGems[0].contexts, ["Levelling"])
        XCTAssertFalse(result.build.requiredGems.map(\.gemID).contains("Metadata/Items/Gems/SkillGemSpark"))
        XCTAssertTrue(result.build.warnings.isEmpty)
    }

    func testDecodesLegacySkillsWithoutSkillSets() throws {
        let result = try service().decode(TestPoBFixtures.legacy)

        XCTAssertEqual(result.build.characterClass, "Ranger")
        XCTAssertEqual(result.build.skillSets.count, 1)
        XCTAssertEqual(
            result.build.requiredGems.first?.gemID,
            "Metadata/Items/Gems/SkillGemPoisonArrow"
        )
    }

    func testRejectsInvalidAndOversizedCodes() {
        XCTAssertThrowsError(try service().decode("not-a-pob")) { error in
            XCTAssertEqual(error as? PoBImportError, .invalidCode)
        }
        XCTAssertThrowsError(try service(maximumCompressedBytes: 4).decode(TestPoBFixtures.multiSkillSet)) { error in
            XCTAssertEqual(error as? PoBImportError, .compressedInputTooLarge)
        }
        XCTAssertThrowsError(try service().decode(malformedXMLCode)) { error in
            XCTAssertEqual(error as? PoBImportError, .invalidXML)
        }
        XCTAssertThrowsError(
            try service(maximumDecompressedBytes: 20).decode(TestPoBFixtures.multiSkillSet)
        ) { error in
            XCTAssertEqual(error as? PoBImportError, .decompressedInputTooLarge)
        }
        let badChecksum = String(TestPoBFixtures.legacy.dropLast()) + "A"
        XCTAssertThrowsError(try service().decode(badChecksum)) { error in
            XCTAssertEqual(error as? PoBImportError, .invalidCode)
        }
    }

    func testRetainsUnknownGemAsWarningWithoutInventingCatalogData() throws {
        let result = try service().decode(unknownGemCode)

        XCTAssertEqual(result.build.requiredGems.map(\.gemID), ["Unknown/Gem"])
        XCTAssertEqual(result.build.skillSets.first?.gemIDs, ["Unknown/Gem"])
        XCTAssertEqual(result.build.warnings.first?.kind, .unknownGem)
        XCTAssertEqual(result.build.warnings.first?.gemID, "Unknown/Gem")
    }

    func testRewritesPobbInURLToRawEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://pobb.in/example/raw")
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(TestPoBFixtures.legacy.utf8))
        }
        let result = try await service(session: mockSession()).import(from: "https://pobb.in/example")
        XCTAssertEqual(result.build.characterClass, "Ranger")
    }

    func testRewritesEverySupportedURLProvider() async throws {
        let cases = [
            ("https://pastebin.com/AbCd1234", "https://pastebin.com/raw/AbCd1234"),
            ("https://poe.ninja/pob/778b8", "https://poe.ninja/pob/raw/778b8"),
            ("https://maxroll.gg/poe/pob/fs2j10ee", "https://maxroll.gg/poe/api/pob/fs2j10ee")
        ]
        for (input, expected) in cases {
            MockURLProtocol.handler = { request in
                XCTAssertEqual(request.url?.absoluteString, expected)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )!
                return (response, Data(TestPoBFixtures.legacy.utf8))
            }
            let result = try await service(session: mockSession()).import(from: input)
            XCTAssertEqual(result.build.characterClass, "Ranger")
        }
    }

    func testRejectsHTTPFailureRedirectToUnsupportedHostAndLargeResponse() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 503,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data())
        }
        await XCTAssertThrowsPoBError(.badResponse) {
            _ = try await self.service(session: self.mockSession()).import(from: "https://pobb.in/error")
        }

        MockURLProtocol.handler = { _ in
            let response = HTTPURLResponse(
                url: URL(string: "https://example.com/stolen")!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(TestPoBFixtures.legacy.utf8))
        }
        await XCTAssertThrowsPoBError(.badResponse) {
            _ = try await self.service(session: self.mockSession()).import(from: "https://pobb.in/redirect")
        }

        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: 200,
                httpVersion: nil,
                headerFields: nil
            )!
            return (response, Data(repeating: 65, count: 33))
        }
        await XCTAssertThrowsPoBError(.compressedInputTooLarge) {
            _ = try await self.service(
                session: self.mockSession(),
                maximumCompressedBytes: 16
            ).import(from: "https://pobb.in/large")
        }
    }

    func testRejectsInsecureAndUnsupportedURLs() async {
        do {
            _ = try await service().import(from: "http://pobb.in/example")
            XCTFail("Expected insecure URL rejection")
        } catch {
            XCTAssertEqual(error as? PoBImportError, .invalidURL)
        }
        do {
            _ = try await service().import(from: "https://example.com/build")
            XCTFail("Expected host rejection")
        } catch {
            XCTAssertEqual(error as? PoBImportError, .unsupportedHost)
        }
    }

    private func service(
        session: URLSession = .shared,
        maximumCompressedBytes: Int = 1_000_000,
        maximumDecompressedBytes: Int = 10_000_000
    ) -> PoBImportService {
        PoBImportService(
            catalog: loadCatalog(),
            session: session,
            maximumCompressedBytes: maximumCompressedBytes,
            maximumDecompressedBytes: maximumDecompressedBytes
        )
    }

    private func loadCatalog() -> GemCatalog {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("ExileRoute/Resources/Data")
        let decoder = JSONDecoder()
        return GemCatalog(
            gems: try! decoder.decode(
                [String: GemRecord].self,
                from: Data(contentsOf: root.appendingPathComponent("gems.json"))
            ),
            characters: try! decoder.decode(
                [String: CharacterRecord].self,
                from: Data(contentsOf: root.appendingPathComponent("characters.json"))
            ),
            vaalGemLookup: try! decoder.decode(
                [String: String].self,
                from: Data(contentsOf: root.appendingPathComponent("vaal-gem-lookup.json"))
            ),
            awakenedGemLookup: try! decoder.decode(
                [String: String].self,
                from: Data(contentsOf: root.appendingPathComponent("awakened-gem-lookup.json"))
            )
        )
    }

    private func mockSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private func XCTAssertThrowsPoBError(
    _ expected: PoBImportError,
    operation: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await operation()
        XCTFail("Expected \(expected)", file: file, line: line)
    } catch {
        XCTAssertEqual(error as? PoBImportError, expected, file: file, line: line)
    }
}
