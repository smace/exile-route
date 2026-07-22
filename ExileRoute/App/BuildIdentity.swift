import Foundation

struct BuildIdentity: Equatable {
    let version: String
    let build: String
    let revision: String

    init(bundle: Bundle = .main) {
        self.init(
            infoDictionary: bundle.infoDictionary ?? [:],
            revision: Self.bundledRevision(in: bundle)
        )
    }

    init(infoDictionary: [String: Any], revision: String? = nil) {
        version = Self.value(for: "CFBundleShortVersionString", in: infoDictionary, fallback: "0.0.0")
        build = Self.value(for: "CFBundleVersion", in: infoDictionary, fallback: "0")
        self.revision = revision?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? "unknown"
    }

    var compactDescription: String {
        "v\(version) (\(build)) • \(revision)"
    }

    var accessibleDescription: String {
        "Version \(version), build \(build), commit \(revision)"
    }

    private static func value(
        for key: String,
        in infoDictionary: [String: Any],
        fallback: String
    ) -> String {
        guard let value = infoDictionary[key] as? String,
              !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return fallback
        }
        return value
    }

    private static func bundledRevision(in bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "build-revision", withExtension: "txt") else { return nil }
        return try? String(contentsOf: url, encoding: .utf8)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
