import Foundation

enum RouteImportError: LocalizedError {
    case invalidURL
    case responseTooLarge
    case badResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL: "Only HTTPS route URLs are supported."
        case .responseTooLarge: "The route exceeds the 1 MB safety limit."
        case .badResponse: "The route could not be downloaded."
        }
    }
}

struct RouteImportService: Sendable {
    let maximumBytes: Int
    let session: URLSession

    init(maximumBytes: Int = 1_000_000, session: URLSession = .shared) {
        self.maximumBytes = maximumBytes
        self.session = session
    }

    func source(from input: String) async throws -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil else { return trimmed }
        guard url.scheme == "https" else { throw RouteImportError.invalidURL }
        let resolvedURL: URL
        if url.host == "pastebin.com", !url.path.hasPrefix("/raw/") {
            resolvedURL = URL(string: "https://pastebin.com/raw\(url.path)")!
        } else {
            resolvedURL = url
        }
        let (data, response) = try await session.data(from: resolvedURL)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else { throw RouteImportError.badResponse }
        guard data.count <= maximumBytes else { throw RouteImportError.responseTooLarge }
        guard let source = String(data: data, encoding: .utf8) else { throw RouteImportError.badResponse }
        return source
    }
}
