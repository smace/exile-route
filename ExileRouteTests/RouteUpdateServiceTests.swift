import Foundation
import XCTest
@testable import ExileRoute

final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            guard let handler = Self.handler else { throw URLError(.resourceUnavailable) }
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class RouteUpdateServiceTests: XCTestCase {
    private let commit = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    private var temporaryDirectory: URL!
    private var resourceRoot: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        resourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("ExileRoute/Resources")
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        MockURLProtocol.handler = nil
        try? FileManager.default.removeItem(at: temporaryDirectory)
    }

    func testInstallsFullyValidatedSnapshotAtomically() async throws {
        MockURLProtocol.handler = validHandler()
        let destination = try await service().downloadLatest()
        let snapshot = try SnapshotLoader().loadDirectory(destination)
        XCTAssertEqual(snapshot.manifest.commit, commit)
        XCTAssertEqual(snapshot.routeSources.count, 10)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent(".staging").path))
    }

    func testNetworkFailureKeepsLastValidSnapshot() async throws {
        let previous = temporaryDirectory.appendingPathComponent("previous", isDirectory: true)
        try FileManager.default.createDirectory(at: previous, withIntermediateDirectories: true)
        let sentinel = previous.appendingPathComponent("valid")
        try Data("keep".utf8).write(to: sentinel)
        MockURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }

        do { _ = try await service().downloadLatest(); XCTFail("Expected network failure") }
        catch { XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path)) }
    }

    func testPartialCommitIsRejectedWithoutInstallation() async {
        MockURLProtocol.handler = validHandler { request in
            request.url?.path.hasSuffix("act-9.txt") == true ? (404, Data()) : nil
        }
        do { _ = try await service().downloadLatest(); XCTFail("Expected partial snapshot rejection") }
        catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent(commit).path))
        }
    }

    func testInvalidSchemaIsRejectedWithoutInstallation() async {
        MockURLProtocol.handler = validHandler { request in
            request.url?.path.hasSuffix("areas.json") == true ? (200, Data("[]".utf8)) : nil
        }
        do { _ = try await service().downloadLatest(); XCTFail("Expected schema rejection") }
        catch {
            XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent(commit).path))
        }
    }

    private func service() -> RouteUpdateService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return RouteUpdateService(
            session: URLSession(configuration: configuration),
            cacheRoot: temporaryDirectory
        )
    }

    private func validHandler(
        responseOverride: ((URLRequest) -> (Int, Data)?)? = nil
    ) -> (URLRequest) throws -> (HTTPURLResponse, Data) {
        let root = resourceRoot!
        return { [commit, root] request in
            if let replacement = responseOverride?(request) {
                return (Self.response(for: request, status: replacement.0), replacement.1)
            }
            guard let url = request.url else { throw URLError(.badURL) }
            if url.host == "api.github.com" {
                return (Self.response(for: request), Data("{\"sha\":\"\(commit)\"}".utf8))
            }
            let filename = url.lastPathComponent
            let source: URL
            if filename.hasPrefix("act-") { source = root.appendingPathComponent("Routes/\(filename)") }
            else { source = root.appendingPathComponent("Data/\(filename)") }
            return (Self.response(for: request), try Data(contentsOf: source))
        }
    }

    private static func response(for request: URLRequest, status: Int = 200) -> HTTPURLResponse {
        HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    }
}
