import Foundation

struct LoadedSnapshot: Sendable {
    let manifest: RouteSnapshotManifest
    let areas: [String: AreaRecord]
    let quests: [String: QuestRecord]
    let gemCatalog: GemCatalog
    let routeSources: [(name: String, contents: String)]
}

enum SnapshotLoaderError: LocalizedError {
    case missingResource(String)
    case invalidManifest
    case invalidContent(String)

    var errorDescription: String? {
        switch self {
        case .missingResource(let name): "Missing bundled resource: \(name)."
        case .invalidManifest: "The bundled route manifest is invalid."
        case .invalidContent(let message): "The route snapshot is invalid: \(message)."
        }
    }
}

struct SnapshotLoader: Sendable {
    func loadBundled(bundle: Bundle = .main) throws -> LoadedSnapshot {
        let decoder = JSONDecoder()
        let manifestURL = try resourceURL(named: "snapshot-manifest", extension: "json", subdirectory: nil, bundle: bundle)
        let manifest = try decoder.decode(RouteSnapshotManifest.self, from: Data(contentsOf: manifestURL))
        guard manifest.schemaVersion == 1, manifest.commit.count == 40 else { throw SnapshotLoaderError.invalidManifest }

        let areasURL = try resourceURL(named: "areas", extension: "json", subdirectory: "Data", bundle: bundle)
        let questsURL = try resourceURL(named: "quests", extension: "json", subdirectory: "Data", bundle: bundle)
        let areas = try decoder.decode([String: AreaRecord].self, from: Data(contentsOf: areasURL))
        let quests = try decoder.decode([String: QuestRecord].self, from: Data(contentsOf: questsURL))
        let gemCatalog = try loadCatalog(
            from: try resourceDirectory(bundle: bundle),
            decoder: decoder
        )
        var sources: [(name: String, contents: String)] = []
        for act in 1...10 {
            let url = try resourceURL(named: "act-\(act)", extension: "txt", subdirectory: "Routes", bundle: bundle)
            sources.append(("Act \(act)", try String(contentsOf: url, encoding: .utf8)))
        }
        return try validate(LoadedSnapshot(
            manifest: manifest,
            areas: areas,
            quests: quests,
            gemCatalog: gemCatalog,
            routeSources: sources
        ))
    }

    func loadDirectory(_ directory: URL, fallbackCatalog: GemCatalog? = nil) throws -> LoadedSnapshot {
        let decoder = JSONDecoder()
        let manifestURL = directory.appendingPathComponent("snapshot-manifest.json")
        let manifest: RouteSnapshotManifest
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            manifest = try decoder.decode(RouteSnapshotManifest.self, from: Data(contentsOf: manifestURL))
        } else {
            manifest = RouteSnapshotManifest(
                schemaVersion: 1,
                repository: "HeartofPhos/exile-leveling",
                commit: directory.lastPathComponent,
                generatedAt: ISO8601DateFormatter().string(from: Date())
            )
        }
        let dataDirectory = directory.appendingPathComponent("Data")
        let routesDirectory = directory.appendingPathComponent("Routes")
        let areas = try decoder.decode([String: AreaRecord].self, from: Data(contentsOf: dataDirectory.appendingPathComponent("areas.json")))
        let quests = try decoder.decode([String: QuestRecord].self, from: Data(contentsOf: dataDirectory.appendingPathComponent("quests.json")))
        let gemCatalog: GemCatalog
        do {
            gemCatalog = try loadCatalog(from: dataDirectory, decoder: decoder)
        } catch {
            guard let fallbackCatalog else { throw error }
            gemCatalog = fallbackCatalog
        }
        let sources = try (1...10).map { act in
            ("Act \(act)", try String(contentsOf: routesDirectory.appendingPathComponent("act-\(act).txt"), encoding: .utf8))
        }
        return try validate(LoadedSnapshot(
            manifest: manifest,
            areas: areas,
            quests: quests,
            gemCatalog: gemCatalog,
            routeSources: sources
        ))
    }

    func cachedDirectory(
        for commit: String,
        fileManager: FileManager = .default,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> URL {
        ApplicationDataLocation.routeCacheDirectory(
            fileManager: fileManager,
            bundleIdentifier: bundleIdentifier
        )
            .appendingPathComponent(commit, isDirectory: true)
    }

    private func validate(_ snapshot: LoadedSnapshot) throws -> LoadedSnapshot {
        guard snapshot.manifest.schemaVersion == 1,
              snapshot.manifest.commit.count == 40,
              snapshot.manifest.commit.allSatisfy(\.isHexDigit) else {
            throw SnapshotLoaderError.invalidManifest
        }
        guard snapshot.areas.count > 100,
              !snapshot.quests.isEmpty,
              snapshot.gemCatalog.gems.count > 100,
              snapshot.gemCatalog.characters.count == 7,
              snapshot.routeSources.count == 10 else {
            throw SnapshotLoaderError.invalidContent("missing campaign data")
        }
        let route = try RouteParser(areas: snapshot.areas, quests: snapshot.quests)
            .parse(sources: snapshot.routeSources, configuration: RouteConfiguration())
        guard Set(route.steps.map(\.act)) == Set(1...10), route.steps.count > 300 else {
            throw SnapshotLoaderError.invalidContent("campaign parse is incomplete")
        }
        return snapshot
    }

    private func loadCatalog(from dataDirectory: URL, decoder: JSONDecoder) throws -> GemCatalog {
        GemCatalog(
            gems: try decoder.decode(
                [String: GemRecord].self,
                from: Data(contentsOf: dataDirectory.appendingPathComponent("gems.json"))
            ),
            characters: try decoder.decode(
                [String: CharacterRecord].self,
                from: Data(contentsOf: dataDirectory.appendingPathComponent("characters.json"))
            ),
            vaalGemLookup: try decoder.decode(
                [String: String].self,
                from: Data(contentsOf: dataDirectory.appendingPathComponent("vaal-gem-lookup.json"))
            ),
            awakenedGemLookup: try decoder.decode(
                [String: String].self,
                from: Data(contentsOf: dataDirectory.appendingPathComponent("awakened-gem-lookup.json"))
            )
        )
    }

    private func resourceDirectory(bundle: Bundle) throws -> URL {
        if let resourceURL = bundle.resourceURL {
            let data = resourceURL.appendingPathComponent("Data", isDirectory: true)
            if FileManager.default.fileExists(atPath: data.path) { return data }
        }
        let gemsURL = try resourceURL(
            named: "gems",
            extension: "json",
            subdirectory: "Data",
            bundle: bundle
        )
        return gemsURL.deletingLastPathComponent()
    }

    private func resourceURL(named: String, extension ext: String, subdirectory: String?, bundle: Bundle) throws -> URL {
        if let url = bundle.url(forResource: named, withExtension: ext, subdirectory: subdirectory) { return url }
        if let url = bundle.url(forResource: named, withExtension: ext) { return url }
        throw SnapshotLoaderError.missingResource("\(named).\(ext)")
    }
}
