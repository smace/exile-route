import Foundation

struct GitHubCommitResponse: Decodable, Sendable { let sha: String }

enum RouteUpdateError: LocalizedError {
    case invalidCommit
    case invalidSnapshot

    var errorDescription: String? {
        switch self {
        case .invalidCommit: "GitHub returned an invalid commit identifier."
        case .invalidSnapshot: "The downloaded snapshot did not pass route validation."
        }
    }
}

actor RouteUpdateService {
    private let session: URLSession
    private let fileManager: FileManager
    private let cacheRoot: URL

    init(session: URLSession = .shared, fileManager: FileManager = .default, cacheRoot: URL? = nil) {
        self.session = session
        self.fileManager = fileManager
        self.cacheRoot = cacheRoot ?? ApplicationDataLocation.routeCacheDirectory(fileManager: fileManager)
    }

    func downloadLatest() async throws -> URL {
        let commitURL = URL(string: "https://api.github.com/repos/HeartofPhos/exile-leveling/commits/main")!
        let (commitData, _) = try await session.data(from: commitURL)
        let sha = try JSONDecoder().decode(GitHubCommitResponse.self, from: commitData).sha
        guard sha.count == 40, sha.allSatisfy(\.isHexDigit) else { throw RouteUpdateError.invalidCommit }

        let staging = cacheRoot.appendingPathComponent(".staging-\(UUID().uuidString)", isDirectory: true)
        let routes = staging.appendingPathComponent("Routes", isDirectory: true)
        let data = staging.appendingPathComponent("Data", isDirectory: true)
        try fileManager.createDirectory(at: routes, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: data, withIntermediateDirectories: true)

        do {
            for act in 1...10 {
                let url = rawURL(sha: sha, path: "common/data/routes/act-\(act).txt")
                let contents = try await download(url)
                guard let text = String(data: contents, encoding: .utf8), text.contains("#section Act \(act)") else {
                    throw RouteUpdateError.invalidSnapshot
                }
                try contents.write(to: routes.appendingPathComponent("act-\(act).txt"), options: .atomic)
            }
            for filename in ["areas", "quests"] {
                let contents = try await download(rawURL(sha: sha, path: "common/data/json/\(filename).json"))
                _ = try JSONSerialization.jsonObject(with: contents)
                try contents.write(to: data.appendingPathComponent("\(filename).json"), options: .atomic)
            }

            let manifest = RouteSnapshotManifest(
                schemaVersion: 1,
                repository: "HeartofPhos/exile-leveling",
                commit: sha,
                generatedAt: ISO8601DateFormatter().string(from: Date())
            )
            let manifestData = try JSONEncoder().encode(manifest)
            try manifestData.write(to: staging.appendingPathComponent("snapshot-manifest.json"), options: .atomic)

            _ = try SnapshotLoader().loadDirectory(staging)

            let destination = cacheRoot.appendingPathComponent(sha, isDirectory: true)
            try fileManager.createDirectory(at: cacheRoot, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: staging)
                return destination
            }
            try fileManager.moveItem(at: staging, to: destination)
            return destination
        } catch {
            try? fileManager.removeItem(at: staging)
            throw error
        }
    }

    private func rawURL(sha: String, path: String) -> URL {
        URL(string: "https://raw.githubusercontent.com/HeartofPhos/exile-leveling/\(sha)/\(path)")!
    }

    private func download(_ url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode, data.count <= 5_000_000 else {
            throw RouteUpdateError.invalidSnapshot
        }
        return data
    }
}
