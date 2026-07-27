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
    @Published var updateChannel = UpdateChannel.stable
    @Published private(set) var hotKeyValidationMessage: String?
    @Published private(set) var transitionNotice: ZoneTransitionNotice?
    @Published private(set) var compactOverlayHeight: CGFloat = 210
    @Published private(set) var importedBuild: ImportedBuild?
    @Published private(set) var buildWarnings: [PoBImportWarning] = []
    @Published private(set) var lastTrackingFrameAt: Date?
    @Published private(set) var trackingRestartCount = 0

    private var snapshot: LoadedSnapshot?
    private var progression: ProgressionEngine?
    private var storedState: StoredApplicationState
    private let persistence: PersistenceStore
    private let updateService = RouteUpdateService()
    private var remoteDetectionID: String?
    private var remoteDetectionCount = 0
    private var noticeTask: Task<Void, Never>?
    private var trackingDiagnosticEvents: [String] = []

    init(persistence: PersistenceStore = PersistenceStore()) {
        self.persistence = persistence
        self.storedState = persistence.load()
        self.importedBuild = storedState.importedBuild
        apply(storedState.settings)
        if ProcessInfo.processInfo.environment["EXILE_ROUTE_PREVIEW"] == "1" { forceVisible = true }
        if ProcessInfo.processInfo.environment["EXILE_ROUTE_EXPANDED_PREVIEW"] == "1" { isExpanded = true }
        loadInitialRoute()
    }

    var shouldShowOverlay: Bool { forceVisible || isGeForceNowActive }
    var areaRecords: [String: AreaRecord] { snapshot?.areas ?? [:] }
    var nearbyExpectedAreaIDs: [String] { progression?.immediateExpectedAreaID.map { [$0] } ?? [] }
    var trackingContext: TrackingContext {
        guard let progression else { return .empty }
        let expectedAreaID = progression.immediateExpectedAreaID
        let transition: TrackingTransition
        if let expectedAreaID,
           currentStep?.expectedAreaID == expectedAreaID,
           currentStep?.fragments.contains(where: { $0.kind == .logout }) == true {
            transition = .logout(expectedTownID: expectedAreaID)
        } else if let expectedAreaID {
            transition = .area(expectedAreaID: expectedAreaID)
        } else {
            transition = .none
        }
        return TrackingContext(
            stepID: currentStep?.id,
            currentAreaID: progression.progress.currentAreaID,
            transition: transition
        )
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
        statusText = isInteractionEnabled ? "Drag the overlay anywhere" : "Overlay locked • click-through"
        saveSettings()
    }

    func toggleOverlay() { forceVisible.toggle() }

    @discardableResult
    func setHotKey(_ definition: HotKeyDefinition, for action: HotKeyAction) -> Bool {
        guard HotKeyDefinition.supports(keyCode: definition.keyCode) else {
            hotKeyValidationMessage = "That key is not supported."
            return false
        }
        if let conflict = hotKeys.first(where: { $0.key != action && $0.value == definition })?.key {
            hotKeyValidationMessage = "\(definition.display) is already assigned to \(conflict.title)."
            statusText = "Shortcut conflict • \(definition.display)"
            return false
        }
        hotKeys[action] = definition
        hotKeyValidationMessage = nil
        statusText = "\(action.title) • \(definition.display)"
        saveSettings()
        return true
    }

    func resetHotKeys() {
        hotKeys = HotKeyDefinition.defaults
        hotKeyValidationMessage = nil
        statusText = "Keyboard shortcuts restored"
        saveSettings()
    }

    func setUpdateChannel(_ channel: UpdateChannel) {
        updateChannel = channel
        statusText = channel == .beta ? "Beta updates enabled" : "Stable updates only"
        saveSettings()
    }

    func overlayFrame(for screenID: String) -> CGRect? {
        guard storedState.settings.overlayPlacementVersion >= UserSettings.currentOverlayPlacementVersion else {
            return nil
        }
        return storedState.settings.overlayFrames[screenID]?.rect
    }

    var preferredOverlayScreenID: String? {
        guard storedState.settings.overlayPlacementVersion >= UserSettings.currentOverlayPlacementVersion else {
            return nil
        }
        return storedState.settings.overlayScreenID
    }

    func saveOverlayFrame(_ frame: CGRect, for screenID: String) {
        if storedState.settings.overlayPlacementVersion < UserSettings.currentOverlayPlacementVersion {
            storedState.settings.overlayFrames.removeAll()
            storedState.settings.overlayScreenID = nil
            storedState.settings.overlayPlacementVersion = UserSettings.currentOverlayPlacementVersion
        }
        storedState.settings.overlayFrames[screenID] = WindowGeometry(frame)
        storedState.settings.overlayScreenID = screenID
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

    func setMeasuredCompactOverlayHeight(_ height: CGFloat) {
        let adjustedHeight = min(520, max(210, ceil(height)))
        guard abs(compactOverlayHeight - adjustedHeight) >= 1 else { return }
        compactOverlayHeight = adjustedHeight
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

    func updateTrackingHealth(lastFrameAt: Date?, restartCount: Int) {
        self.lastTrackingFrameAt = lastFrameAt
        trackingRestartCount = restartCount
    }

    func recordTrackingDiagnostic(_ message: String, at date: Date = Date()) {
        let timestamp = Self.diagnosticTimestamp.string(from: date)
        let sanitized = message.replacingOccurrences(of: "\n", with: " ").prefix(320)
        trackingDiagnosticEvents.append("\(timestamp) \(sanitized)")
        if trackingDiagnosticEvents.count > 250 {
            trackingDiagnosticEvents.removeFirst(trackingDiagnosticEvents.count - 250)
        }
    }

    func copyTrackingDiagnostics() {
        let header = [
            "Exile Route tracking diagnostics",
            "build=\(BuildIdentity().compactDescription)",
            "ocr=\(ocrStatus.diagnosticName)",
            "step=\(currentStep?.id ?? "none")",
            "current=\(trackingContext.currentAreaID ?? "none")",
            "expected=\(trackingContext.transition.expectedAreaID ?? "none")",
            "restarts=\(trackingRestartCount)"
        ]
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString((header + trackingDiagnosticEvents).joined(separator: "\n"), forType: .string)
        statusText = "Tracking diagnostics copied"
    }

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

    func importBuild(_ input: String) async {
        guard let snapshot else {
            statusText = "Campaign data is not ready"
            return
        }
        statusText = "Importing Path of Building…"
        do {
            let result = try await PoBImportService(catalog: snapshot.gemCatalog).import(from: input)
            storedState.importedBuild = result.build
            importedBuild = result.build
            rebuildRoute(reset: false, preservingCurrentStep: true)
            try persist()
            let count = result.build.requiredGems.count
            statusText = "Imported \(result.build.characterClass) build • \(count) gems"
        } catch {
            statusText = error.localizedDescription
        }
    }

    func removeBuild() {
        guard importedBuild != nil else { return }
        storedState.importedBuild = nil
        importedBuild = nil
        buildWarnings = []
        rebuildRoute(reset: false, preservingCurrentStep: true)
        try? persist()
        statusText = "Path of Building removed"
    }

    func importRoute(_ input: String) async {
        do {
            let source = try await RouteImportService().source(from: input)
            guard let snapshot else { return }
            let parsed = try RouteParser(areas: snapshot.areas, quests: snapshot.quests)
                .parse(sources: [("Custom Route", source)], configuration: routeConfiguration)
            storedState.customRouteSource = source
            let route = enrichedRoute(from: parsed)
            install(route: route, progress: ProgressState())
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
            rebuildRoute(reset: false, preservingCurrentStep: true)
            try persist()
            statusText = "Route updated to \(snapshotCommit)"
        } catch {
            statusText = "Update failed — using last valid route"
        }
    }

    func consumeDetection(_ detection: AreaDetection) {
        let context = trackingContext
        let confirmationCount: Int
        if context.transition.isLogout {
            confirmationCount = 1
        } else if isNumberedSiblingTransition(context) {
            confirmationCount = 3
        } else {
            confirmationCount = 2
        }
        if let result = progression?.consume(detection, confirmationCount: confirmationCount) {
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
              progression?.currentVisit?.stepRange.contains(futureIndex) == false else { return }
        if remoteDetectionID == areaID { remoteDetectionCount += 1 }
        else { remoteDetectionID = areaID; remoteDetectionCount = 1 }
        if remoteDetectionCount >= 2 { suggestedAreaDetection = detection }
    }

    private func loadInitialRoute() {
        do {
            let loader = SnapshotLoader()
            let bundled = try loader.loadBundled()
            let loaded: LoadedSnapshot
            if let commit = storedState.activeSnapshotCommit {
                do {
                    loaded = try loader.loadDirectory(
                        loader.cachedDirectory(for: commit),
                        fallbackCatalog: bundled.gemCatalog
                    )
                }
                catch {
                    storedState.activeSnapshotCommit = nil
                    loaded = bundled
                }
            } else {
                loaded = bundled
            }
            snapshot = loaded
            snapshotCommit = String(loaded.manifest.commit.prefix(8))
            rebuildRoute(reset: false)
            statusText = "Route \(snapshotCommit) ready"
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func rebuildRoute(reset: Bool, preservingCurrentStep: Bool = false) {
        guard let snapshot else { return }
        do {
            let previousStep = preservingCurrentStep ? currentStep : nil
            let parser = RouteParser(areas: snapshot.areas, quests: snapshot.quests)
            let baseRoute: CampaignRoute
            if let custom = storedState.customRouteSource {
                baseRoute = try parser.parse(sources: [("Custom Route", custom)], configuration: routeConfiguration)
            } else {
                baseRoute = try parser.parse(sources: snapshot.routeSources, configuration: routeConfiguration)
            }
            let route = enrichedRoute(from: baseRoute)
            var progress = reset ? ProgressState() : storedState.progress
            if preservingCurrentStep, let previousStep {
                progress = rebase(progress: progress, from: previousStep, to: route)
            }
            install(route: route, progress: progress)
        } catch {
            statusText = error.localizedDescription
        }
    }

    private func enrichedRoute(from baseRoute: CampaignRoute) -> CampaignRoute {
        guard let snapshot, let importedBuild else {
            buildWarnings = []
            return baseRoute
        }
        let enrichment = GemRouteEnricher(quests: snapshot.quests, catalog: snapshot.gemCatalog)
            .enrich(baseRoute, with: importedBuild)
        buildWarnings = enrichment.warnings
        return enrichment.route
    }

    private func rebase(
        progress: ProgressState,
        from previousStep: RouteStep,
        to route: CampaignRoute
    ) -> ProgressState {
        var rebased = progress
        let steps = route.steps
        let exactID = previousStep.id
        let parentID = previousStep.gemAcquisition?.parentStepID
        if let index = steps.firstIndex(where: { $0.id == exactID }) {
            rebased.stepIndex = index
        } else if let parentID, let index = steps.firstIndex(where: { $0.id == parentID }) {
            rebased.stepIndex = index
        } else {
            rebased.stepIndex = min(progress.stepIndex, max(steps.count - 1, 0))
        }
        let validIDs = Set(steps.map(\.id))
        rebased.completedStepIDs.formIntersection(validIDs)
        rebased.skippedStepIDs.formIntersection(validIDs)
        if steps.indices.contains(rebased.stepIndex) {
            rebased.currentAreaID = steps[rebased.stepIndex].contextAreaID
        }
        rebased.updatedAt = Date()
        return rebased
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
            let titleHeight = CGFloat(lines) * 18 * CGFloat(textScale)
            let hints = objective.state == .active ? objective.step.hints : []
            let hintHeight = hints.reduce(CGFloat.zero) { hintTotal, hint in
                let hintLines = max(1, Int(ceil(Double(hint.count) / Double(charactersPerLine))))
                return hintTotal + CGFloat(hintLines) * 16 * CGFloat(textScale) + 5
            }
            let contentHeight = titleHeight + hintHeight
            return partial + max(30 * CGFloat(textScale), contentHeight + 12)
        }
        let rowSpacing = CGFloat(max(currentZoneObjectives.count - 1, 0)) * 6
        let chromeHeight = 128 + max(0, CGFloat(textScale - 1) * 16)
        let noticeHeight: CGFloat = transitionNotice == nil ? 0 : 42
        setMeasuredCompactOverlayHeight(chromeHeight + rowHeight + rowSpacing + noticeHeight)
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
        updateChannel = settings.updateChannel
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
        storedState.settings.updateChannel = updateChannel
        try? persist()
    }

    private func persist() throws { try persistence.save(storedState) }

    private func isNumberedSiblingTransition(_ context: TrackingContext) -> Bool {
        guard let currentID = context.currentAreaID,
              let expectedID = context.transition.expectedAreaID,
              let current = snapshot?.areas[currentID]?.name,
              let expected = snapshot?.areas[expectedID]?.name,
              let currentLevel = Self.levelSuffix(in: current),
              let expectedLevel = Self.levelSuffix(in: expected) else { return false }
        return currentLevel.prefix == expectedLevel.prefix && currentLevel.number != expectedLevel.number
    }

    private static func levelSuffix(in value: String) -> (prefix: String, number: Int)? {
        guard let range = value.range(of: #" Level ([0-9]+)$"#, options: .regularExpression),
              let number = Int(value[range].split(separator: " ").last ?? "") else { return nil }
        return (String(value[..<range.lowerBound]), number)
    }

    private static let diagnosticTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

extension OCRStatus {
    var diagnosticName: String {
        switch self {
        case .disabled: "disabled"
        case .waitingForGeForceNow: "waiting"
        case .permissionRequired: "permission-required"
        case .scanning: "scanning"
        case .returningToTown: "returning-to-town"
        case .recovering: "recovering"
        case .noFrames: "no-frames"
        case .recognized: "recognized"
        case .lowConfidence: "low-confidence"
        case .failed: "failed"
        }
    }
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
