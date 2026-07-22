import Foundation

struct ProgressionEngine: Sendable {
    private(set) var route: CampaignRoute
    private(set) var progress: ProgressState
    private var pendingAreaID: String?
    private var pendingCount = 0

    init(route: CampaignRoute, progress: ProgressState = ProgressState()) {
        self.route = route
        self.progress = progress
        self.progress.stepIndex = min(max(progress.stepIndex, 0), max(route.steps.count - 1, 0))
    }

    var currentStep: RouteStep? { route.steps[safe: progress.stepIndex] }
    var nextStep: RouteStep? { route.steps[safe: progress.stepIndex + 1] }

    mutating func moveNext() {
        guard progress.stepIndex + 1 < route.steps.count else { return }
        if let currentStep { progress.completedStepIDs.insert(currentStep.id) }
        progress.stepIndex += 1
        progress.updatedAt = Date()
    }

    mutating func movePrevious() {
        guard progress.stepIndex > 0 else { return }
        progress.stepIndex -= 1
        progress.completedStepIDs.remove(route.steps[progress.stepIndex].id)
        progress.updatedAt = Date()
    }

    @discardableResult
    mutating func jumpForward(toAreaID areaID: String) -> Bool {
        guard let match = route.steps[progress.stepIndex...].firstIndex(where: { $0.expectedAreaID == areaID }),
              match >= progress.stepIndex else { return false }
        for index in progress.stepIndex..<match { progress.completedStepIDs.insert(route.steps[index].id) }
        progress.stepIndex = match
        progress.currentAreaID = areaID
        progress.updatedAt = Date()
        pendingAreaID = nil
        pendingCount = 0
        return true
    }

    mutating func consume(_ detection: AreaDetection, confirmationCount: Int = 2, forwardWindow: Int = 6) -> Bool {
        guard detection.confidence >= 0.55, let areaID = detection.areaID else {
            pendingAreaID = nil
            pendingCount = 0
            return false
        }

        if pendingAreaID == areaID { pendingCount += 1 } else {
            pendingAreaID = areaID
            pendingCount = 1
        }
        guard pendingCount >= confirmationCount else { return false }

        let end = min(route.steps.count, progress.stepIndex + forwardWindow + 1)
        guard progress.stepIndex < end,
              let match = route.steps[progress.stepIndex..<end].firstIndex(where: { $0.expectedAreaID == areaID }),
              match >= progress.stepIndex else { return false }

        for index in progress.stepIndex..<match { progress.completedStepIDs.insert(route.steps[index].id) }
        progress.stepIndex = match
        progress.currentAreaID = areaID
        progress.updatedAt = Date()
        pendingAreaID = nil
        pendingCount = 0
        return true
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
