import AppKit
import Combine
import Foundation
import SwiftUI

struct ZoneTransitionNotice: Equatable, Sendable {
    let skippedCount: Int
    let previousAreaName: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var route: CampaignRoute?
    @Published private(set) var currentStep: RouteStep?
    @Published private(set) var nextStep: RouteStep?
    @Published private(set) var stepIndex = 0
    @Published private(set) var totalSteps = 0
    @Published private(set) var snapshotCommit = "bundled"
    @Published private(set) var currentAreaName = "The Road Forward"
    @Published var statusText = "Loading route…"
    @Published var ocrStatus: OCRStatus = .disabled
    @Published var isExpanded = false
    @Published var isInteractionEnabled = false
    @Published var overlayOpacity = 0.94
    @Published var textScale = 1.0
    @Published var isOCRActive = true
    @Published var ocrCrop = NormalizedRect.defaultAreaTitle
    @Published private(set) var suggestedAreaDetection: AreaDetection?
    @Published var isGeForceNowActive = false
    @Published var forceVisible = false
    @Published var routeConfiguration = RouteConfiguration()
    @Published var hotKeys = HotKeyDefinition.defaults
    @Published private(set) var transitionNotice: ZoneTransitionNotice?
    @Published private(set) var compactOverlayHeight: CGFloat = 210

    private var snapshot: LoadedSnapshot?
    private var progression: ProgressionEngine?
    private var storedState: StoredApplicationState
    private let persistence: PersistenceStore
    private let updateService = RouteUpdateService()
    private var remoteDetectionID: String?
    private var remoteDetectionCount = 0
    private var noticeTask: Task<Void, Never>?

    init(persistence: PersistenceStore = PersistenceStore()) {
        self.persistence = persistence
        self.storedState = persistence.load()
        apply(storedState.settings)
        if ProcessInfo.processInfo.environment["EXILE_ROUTE_PREVIEW"] == "1" { forceVisible = true }
        if ProcessInfo.processInfo.environment["EXILE_ROUTE_EXPANDED_PREVIEW"] == "1" { isExpanded = true }
        loadInitialRoute()
    }

    var shouldShowOverlay: Bool { forceVisible || isGeForceNowActive }
    var areaRecords: [String: AreaRecord] { snapshot?.areas ?? [:] }
    var nearbyExpectedAreaIDs: [String] {
        guard let route else { return [] }
        let end = min(route.steps.count, stepIndex + 8)
        guard stepIndex < end else { return [] }
        return Array(route.steps[stepIndex..<end].compactMap(\.expectedAreaID))
    }
    var currentAct: Int { currentStep?.act ?? 1 }
    var currentVisit: RouteVisit? { progression?.currentVisit }
    var currentZoneObjectives: [RouteObjective] { progression?.currentObjectives ?? [] }
    var upcomingVisits: [RouteVisit] {
        guard let route, let currentVisit,
              let currentIndex = route.visits.firstIndex(where: { $0.id == currentVisit.id }) else { return [] }
        let start = currentIndex + 1
        let end = min(route.visits.count, start + 2)
        guard start < end else { return [] }
        return Array(route.visits[start..<end])
    }
    var zoneObjectivePosition: Int {
        guard let active = currentZoneObjectives.firstIndex(where: { $0.state == .active }) else {
            return currentZoneObjectives.count
        }
        return active + 1
    }
    var progressFraction: Double {
        guard totalSteps > 1 else { return 0 }
        return Double(stepIndex) / Double(totalSteps - 1)
    }

    func moveNext() {
        clearTransitionNotice()
        progression?.moveNext()
        synchronizeFromEngine(announce: true)
    }

    func movePrevious() {
        clearTransitionNotice()
        progression?.movePrevious()
        synchronizeFromEngine(announce: false)
    }

    func resetProgress() {
        guard let route else { return }
        progression = ProgressionEngine(route: route)
        synchronizeFromEngine(announce: false)
        statusText = "Progress reset"
    }

    func toggleExpanded() {
        withAnimation(.easeInOut(duration: 0.18)) { isExpanded.toggle() }
        saveSettings()
    }

    func toggleInteraction() {
        isInteractionEnabled.toggle()
        statusText = isInteractionEnabled ? "Interaction mode" : "Click-through mode"
        saveSettings()
    }

    func toggleOverlay() { forceVisible.toggle() }

    func setHotKey(_ definition: HotKeyDefinition, for action: HotKeyAction) {
        hotKeys[action] = definition
        saveSettings()
    }

    func overlayFrame(for screenID: String) -> CGRect? {
        storedState.settings.overlayFrames[screenID]?.rect
    }

    func saveOverlayFrame(_ frame: CGRect, for screenID: String) {
        storedState.settings.overlayFrames[screenID] = WindowGeometry(frame)
        try? persist()
    }

    func setOverlayOpacity(_ value: Double) {
        overlayOpacity = min(max(value, 0.55), 1)
        saveSettings()
    }

    func setTextScale(_ value: Double) {
        textScale = min(max(value, 0.8), 1.35)
        updateCompactOverlayHeight()
        saveSettings()
    }

    func setOCRActive(_ active: Bool) {
        isOCRActive = active
        ocrStatus = active ? .waitingForGeForceNow : .disabled
        statusText = active ? "Area recognition resumed" : "Area recognition paused"
        saveSettings()
    }

    func setOCRCrop(_ crop: NormalizedRect) {
        ocrCrop = crop.clamped
        saveSettings()
    }

    func resetOCRCrop() { setOCRCrop(.defaultAreaTitle) }

    func acceptSuggestedAreaJump() {
        guard let areaID = suggestedAreaDetection?.areaID,
              let result = progression?.jumpForward(toAreaID: areaID) else { return }
        suggestedAreaDetection = nil
        presentTransitionNotice(for: result)
        synchronizeFromEngine(announce: true)
    }

    func dismissSuggestedAreaJump() {
        suggestedAreaDetection = nil
        remoteDetectionID = nil
        remoteDetectionCount = 0
    }

    func applyRouteConfiguration(_ configuration: RouteConfiguration) {
        routeConfiguration = configuration
        rebuildRoute(reset: true)
        saveSettings()
    }

    func importRoute(_ input: String) async {
        do {
            let source = try await RouteImportService().source(from: input)
            guard let snapshot else { return }
            let parsed = try RouteParser(areas: snapshot.areas, quests: snapshot.quests)
                .parse(sources: [("Custom Route", source)], configuration: routeConfiguration)
            storedState.customRouteSource = source
            install(route: parsed, progress: ProgressState())
            try persist()
            statusText = "Custom route imported"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func restoreBundledRoute() {
        storedState.customRouteSource = nil
        rebuildRoute(reset: true)
        try? persist()
        statusText = "Bundled route restored"
    }

    func exportRoute(to url: URL) throws {
        guard let source = route?.source else { return }
        try source.write(to: url, atomically: true, encoding: .utf8)
    }

    func updateRoutes() async {
        statusText = "Checking upstream route…"
        do {
            let directory = try await updateService.downloadLatest()
            let loaded = try SnapshotLoader().loadDirectory(directory)
            snapshot = loaded
            snapshotCommit = String(loaded.manifest.commit.prefix(8))
            storedState.customRouteSource = nil
            storedState.activeSnapshotCommit = loaded.manifest.commit
            rebuildRoute(reset: false)
            try persist()
            statusText = "Route updated to \(snapshotCommit)"
        } catch {
            statusText = "Update failed — using last valid route"
        }
    }

    func consumeDetection(_ detection: AreaDetection) {
        ocrStatus = detection.confidence >= 0.55 ? .recognized(detection.text) : .lowConfidence
        if let result = progression?.consume(detection) {
            suggestedAreaDetection = nil
            remoteDetectionID = nil
            remoteDetectionCount = 0
            presentTransitionNotice(for: result)
            synchronizeFromEngine(announce: true)
            return
        }

        guard detection.confidence >= 0.7, let areaID = detection.areaID,
              progression?.suppressesJump(to: areaID) == false,
              let route, let futureIndex = route.steps[stepIndex...].firstIndex(where: { $0.expectedAreaID == areaID }),
              futureIndex > stepIndex + 6 else { return }
        if remoteDetectionID == areaID { remoteDetectionCount += 1 }
        else { remoteDetectionID = areaID; remoteDetectionCount = 1 }
        if remoteDetectionCount >= 2 { suggestedAreaDetection = detection }
    }

    private func loadInitialRoute() {
        do {
            let loader = SnapshotLoader()
            let loaded: LoadedSnapshot
            if let commit = storedState.activeSnapshotCommit {
                do { loaded = try loader.loadDirectory(loader.cachedDirectory(for: commit)) }
                catch {
                    storedState.activeSnapshotCommit = nil
                    loaded = try loader.loadBundled()
                }
            } else {
                loaded = try loader.loadBundled()
            }
            snapshot = loaded
            snapshotCommit = String(loaded.manifest.commit.prefix(8))
            rebuildRoute(reset: false)
            statusText = "Route \(snapshotCommit) ready"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func rebuildRoute(reset: Bool) {
        guard let snapshot else { return }
        do {
            let parser = RouteParser(areas: snapshot.areas, quests: snapshot.quests)
            let parsed: CampaignRoute
            if let custom = storedState.customRouteSource {
                parsed = try parser.parse(sources: [("Custom Route", custom)], configuration: routeConfiguration)
            } else {
                parsed = try parser.parse(sources: snapshot.routeSources, configuration: routeConfiguration)
            }
            install(route: parsed, progress: reset ? ProgressState() : storedState.progress)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func install(route: CampaignRoute, progress: ProgressState) {
        self.route = route
        progression = ProgressionEngine(route: route, progress: progress)
        synchronizeFromEngine(announce: false)
    }

    private func synchronizeFromEngine(announce: Bool) {
        guard let progression else { return }
        stepIndex = progression.progress.stepIndex
        totalSteps = progression.route.steps.count
        currentStep = progression.currentStep
        nextStep = progression.nextStep
        if let areaID = progression.progress.currentAreaID ?? progression.currentStep?.contextAreaID,
           let areaName = snapshot?.areas[areaID]?.name {
            currentAreaName = areaName
        }
        storedState.progress = progression.progress
        try? persist()
        updateCompactOverlayHeight()
        if announce, let step = progression.currentStep { statusText = step.displayText }
    }

    func areaName(for areaID: String) -> String {
        snapshot?.areas[areaID]?.name ?? areaID
    }

    func objectives(in visit: RouteVisit) -> [RouteObjective] {
        progression?.objectives(in: visit) ?? []
    }

    private func presentTransitionNotice(for result: AreaProgressionResult) {
        guard !result.skippedStepIDs.isEmpty else {
            clearTransitionNotice()
            return
        }
        let previousName = result.previousAreaID.map(areaName(for:)) ?? "Previous area"
        transitionNotice = ZoneTransitionNotice(
            skippedCount: result.skippedStepIDs.count,
            previousAreaName: previousName
        )
        noticeTask?.cancel()
        noticeTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            self?.transitionNotice = nil
            self?.updateCompactOverlayHeight()
        }
        updateCompactOverlayHeight()
    }

    private func clearTransitionNotice() {
        noticeTask?.cancel()
        noticeTask = nil
        transitionNotice = nil
        updateCompactOverlayHeight()
    }

    private func updateCompactOverlayHeight() {
        let charactersPerLine = max(24, Int(42 / textScale))
        let rowHeight = currentZoneObjectives.reduce(CGFloat.zero) { partial, objective in
            let lines = max(1, Int(ceil(Double(objective.step.displayText.count) / Double(charactersPerLine))))
            return partial + CGFloat(lines) * CGFloat(18) * CGFloat(textScale) + CGFloat(12)
        }
        let activeHints = currentZoneObjectives.first(where: { $0.state == .active })?.step.hints ?? []
        let hintHeight = CGFloat(activeHints.prefix(3).count) * CGFloat(22) * CGFloat(textScale)
        let noticeHeight: CGFloat = transitionNotice == nil ? 0 : 34
        compactOverlayHeight = min(520, max(210, 116 + rowHeight + hintHeight + noticeHeight))
    }

    private func apply(_ settings: UserSettings) {
        routeConfiguration = settings.routeConfiguration
        overlayOpacity = settings.overlayOpacity
        textScale = settings.textScale
        isExpanded = settings.isExpanded
        isInteractionEnabled = settings.isInteractionEnabled
        isOCRActive = settings.isOCRActive
        ocrCrop = settings.ocrCrop
        hotKeys = settings.hotKeys
    }

    private func saveSettings() {
        storedState.settings.routeConfiguration = routeConfiguration
        storedState.settings.overlayOpacity = overlayOpacity
        storedState.settings.textScale = textScale
        storedState.settings.isExpanded = isExpanded
        storedState.settings.isInteractionEnabled = isInteractionEnabled
        storedState.settings.isOCRActive = isOCRActive
        storedState.settings.ocrCrop = ocrCrop
        storedState.settings.hotKeys = hotKeys
        try? persist()
    }

    private func persist() throws { try persistence.save(storedState) }
}

private extension NormalizedRect {
    var clamped: NormalizedRect {
        let clampedX = min(max(x, 0), 0.95)
        let clampedY = min(max(y, 0), 0.95)
        return NormalizedRect(
            x: clampedX,
            y: clampedY,
            width: min(max(width, 0.05), 1 - clampedX),
            height: min(max(height, 0.05), 1 - clampedY)
        )
    }
}
