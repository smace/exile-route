import Foundation

enum UpdateChannel: String, CaseIterable, Codable, Sendable {
    case stable
    case beta

    var title: String {
        switch self {
        case .stable: "Stable"
        case .beta: "Beta"
        }
    }

    var allowedSparkleChannels: Set<String> {
        switch self {
        case .stable: []
        case .beta: ["beta"]
        }
    }
}

enum DistributionFlavor: String, Sendable {
    case stable
    case beta
    case dev

    static var current: DistributionFlavor {
        let value = Bundle.main.object(forInfoDictionaryKey: "ExileRouteDistributionFlavor") as? String
        return DistributionFlavor(rawValue: value ?? "") ?? .stable
    }

    var updatesEnabled: Bool { self != .dev }
}

enum ApplicationDataLocation {
    static func directoryName(bundleIdentifier: String?) -> String {
        bundleIdentifier?.hasSuffix(".Dev") == true ? "Exile Route Dev" : "Exile Route"
    }

    static func dataDirectory(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        dataDirectory(
            in: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            bundleIdentifier: bundleIdentifier
        )
    }

    static func dataDirectory(in applicationSupportDirectory: URL, bundleIdentifier: String?) -> URL {
        applicationSupportDirectory.appendingPathComponent(
            directoryName(bundleIdentifier: bundleIdentifier),
            isDirectory: true
        )
    }

    static func routeCacheDirectory(
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        routeCacheDirectory(
            in: fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
            bundleIdentifier: bundleIdentifier
        )
    }

    static func routeCacheDirectory(in applicationSupportDirectory: URL, bundleIdentifier: String?) -> URL {
        dataDirectory(in: applicationSupportDirectory, bundleIdentifier: bundleIdentifier)
            .appendingPathComponent("RouteCache", isDirectory: true)
    }
}
