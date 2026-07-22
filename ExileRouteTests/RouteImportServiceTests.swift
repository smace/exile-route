import Foundation
import XCTest
@testable import ExileRoute

final class RouteImportServiceTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testKeepsInlineRouteText() async throws {
        let source = "#section Act 1\nFind {generic|Hillock}"
        let imported = try await RouteImportService().source(from: source)
        XCTAssertEqual(imported, source)
    }

    func testResolvesPastebinToHTTPSRawEndpoint() async throws {
        MockURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://pastebin.com/raw/abc123")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("#section Act 1".utf8))
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        let service = RouteImportService(session: URLSession(configuration: configuration))
        let imported = try await service.source(from: "https://pastebin.com/abc123")
        XCTAssertEqual(imported, "#section Act 1")
    }

    func testRejectsInsecureURL() async {
        do { _ = try await RouteImportService().source(from: "http://example.com/route.txt"); XCTFail("Expected rejection") }
        catch RouteImportError.invalidURL { }
        catch { XCTFail("Unexpected error: \(error)") }
    }
}
