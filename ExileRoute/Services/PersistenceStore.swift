import Foundation

struct UserSettings: Codable, Equatable, Sendable {
    var routeConfiguration = RouteConfiguration()
    var overlayOpacity = 0.94
    var textScale = 1.0
    var isExpanded = false
    var isInteractionEnabled = false
    var isOCRActive = true
    var ocrCrop = NormalizedRect.defaultAreaTitle
    var overlayFrames: [String: WindowGeometry] = [:]
}

struct WindowGeometry: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    init(_ rect: CGRect) {
        x = rect.origin.x
        y = rect.origin.y
        width = rect.width
        height = rect.height
    }

    var rect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
}

struct NormalizedRect: Codable, Equatable, Sendable {
    var x: Double
    var y: Double
    var width: Double
    var height: Double

    static let defaultAreaTitle = NormalizedRect(x: 0.25, y: 0.66, width: 0.5, height: 0.28)
}

struct StoredApplicationState: Codable, Equatable, Sendable {
    var settings = UserSettings()
    var progress = ProgressState()
    var customRouteSource: String?
    var activeSnapshotCommit: String?
}

struct PersistenceStore {
    let fileManager: FileManager
    let baseURL: URL

    init(fileManager: FileManager = .default, baseURL: URL? = nil) {
        self.fileManager = fileManager
        self.baseURL = baseURL ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Exile Route", isDirectory: true)
    }

    func load() -> StoredApplicationState {
        let url = baseURL.appendingPathComponent("state.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        guard let data = try? Data(contentsOf: url),
              let state = try? decoder.decode(StoredApplicationState.self, from: data) else {
            return StoredApplicationState()
        }
        return state
    }

    func save(_ state: StoredApplicationState) throws {
        try fileManager.createDirectory(at: baseURL, withIntermediateDirectories: true)
        let data = try JSONEncoder.pretty.encode(state)
        try data.write(to: baseURL.appendingPathComponent("state.json"), options: .atomic)
    }
}

private extension JSONEncoder {
    static var pretty: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return encoder
    }
}
