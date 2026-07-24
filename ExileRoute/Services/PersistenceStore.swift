import Foundation

struct UserSettings: Codable, Equatable, Sendable {
    static let currentOverlayPlacementVersion = 3

    var routeConfiguration = RouteConfiguration()
    var overlayOpacity = 0.94
    var textScale = 1.0
    var isExpanded = false
    var isInteractionEnabled = false
    var isOCRActive = true
    var ocrCrop = NormalizedRect.defaultAreaTitle
    var overlayFrames: [String: WindowGeometry] = [:]
    var overlayPlacementVersion = currentOverlayPlacementVersion
    var hotKeys = HotKeyDefinition.defaults
    var ocrCalibrationVersion = 2

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        routeConfiguration = try container.decodeIfPresent(RouteConfiguration.self, forKey: .routeConfiguration) ?? RouteConfiguration()
        overlayOpacity = try container.decodeIfPresent(Double.self, forKey: .overlayOpacity) ?? 0.94
        textScale = try container.decodeIfPresent(Double.self, forKey: .textScale) ?? 1
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? false
        isInteractionEnabled = try container.decodeIfPresent(Bool.self, forKey: .isInteractionEnabled) ?? false
        isOCRActive = try container.decodeIfPresent(Bool.self, forKey: .isOCRActive) ?? true
        overlayFrames = try container.decodeIfPresent([String: WindowGeometry].self, forKey: .overlayFrames) ?? [:]
        overlayPlacementVersion = try container.decodeIfPresent(Int.self, forKey: .overlayPlacementVersion) ?? 1
        hotKeys = try container.decodeIfPresent([HotKeyAction: HotKeyDefinition].self, forKey: .hotKeys) ?? HotKeyDefinition.defaults
        let storedCalibrationVersion = try container.decodeIfPresent(Int.self, forKey: .ocrCalibrationVersion) ?? 1
        ocrCrop = storedCalibrationVersion >= 2
            ? (try container.decodeIfPresent(NormalizedRect.self, forKey: .ocrCrop) ?? .defaultAreaTitle)
            : .defaultAreaTitle
        ocrCalibrationVersion = 2
    }
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

    static let defaultAreaTitle = NormalizedRect(x: 0.72, y: 0.86, width: 0.27, height: 0.13)
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
