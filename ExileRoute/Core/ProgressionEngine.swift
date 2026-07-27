import Foundation

struct ProgressionEngine: Sendable {
    private(set) var route: CampaignRoute
    private(set) var progress: ProgressState
    private var pendingAreaID: String?
    private var pendingCount = 0
    private var recentSkippedReturnIndex: Int?
    private var suppressedAreaID: String?

    init(route: CampaignRoute, progress: ProgressState = ProgressState()) {
        self.route = route
        self.progress = progress
        self.progress.stepIndex = min(max(progress.stepIndex, 0), max(route.steps.count - 1, 0))
        normalizeProgress()
    }

    var currentStep: RouteStep? { route.steps[safe: progress.stepIndex] }
    var nextStep: RouteStep? { route.steps[safe: progress.stepIndex + 1] }
    var currentVisit: RouteVisit? { route.visit(containing: progress.stepIndex) }

    var currentObjectives: [RouteObjective] {
        guard let currentVisit else { return [] }
        return objectives(in: currentVisit)
    }

    var currentVisitExpectedAreaIDs: [String] {
        guard let currentVisit else { return [] }
        let lowerBound = max(progress.stepIndex, currentVisit.stepRange.lowerBound)
        guard lowerBound < currentVisit.stepRange.upperBound else { return [] }
        return route.steps[lowerBound..<currentVisit.stepRange.upperBound].compactMap(\.expectedAreaID)
    }

    var immediateExpectedAreaID: String? {
        guard let currentVisit else { return nil }
        let lowerBound = max(progress.stepIndex, currentVisit.stepRange.lowerBound)
        guard lowerBound < currentVisit.stepRange.upperBound else { return nil }
        return route.steps[lowerBound..<currentVisit.stepRange.upperBound]
            .first(where: { $0.expectedAreaID != nil })?
            .expectedAreaID
    }

    func objectives(in visit: RouteVisit) -> [RouteObjective] {
        visit.stepRange.compactMap { index in
            guard let step = route.steps[safe: index] else { return nil }
            let state: RouteObjectiveState
            if index == progress.stepIndex {
                state = .active
            } else if progress.skippedStepIDs.contains(step.id) {
                state = .skipped
            } else if progress.completedStepIDs.contains(step.id) || index < progress.stepIndex {
                state = .completed
            } else {
                state = .pending
            }
            return RouteObjective(stepIndex: index, step: step, state: state)
        }
    }

    func suppressesJump(to areaID: String) -> Bool {
        areaID == progress.currentAreaID || areaID == suppressedAreaID
    }

    mutating func moveNext() {
        guard progress.stepIndex + 1 < route.steps.count else { return }
        if let currentStep {
            progress.completedStepIDs.insert(currentStep.id)
            progress.skippedStepIDs.remove(currentStep.id)
            if let destination = currentStep.expectedAreaID {
                progress.currentAreaID = destination
                if destination == suppressedAreaID { suppressedAreaID = nil }
            }
        }
        progress.stepIndex += 1
        if let currentStep {
            progress.skippedStepIDs.remove(currentStep.id)
            progress.currentAreaID = currentStep.contextAreaID
        }
        recentSkippedReturnIndex = nil
        progress.updatedAt = Date()
    }

    mutating func movePrevious() {
        if let returnIndex = recentSkippedReturnIndex, returnIndex < progress.stepIndex {
            suppressedAreaID = progress.currentAreaID
            progress.stepIndex = returnIndex
            recentSkippedReturnIndex = nil
        } else {
            guard progress.stepIndex > 0 else { return }
            progress.stepIndex -= 1
        }
        let step = route.steps[progress.stepIndex]
        progress.completedStepIDs.remove(step.id)
        progress.skippedStepIDs.remove(step.id)
        progress.currentAreaID = step.contextAreaID
        progress.updatedAt = Date()
    }

    @discardableResult
    mutating func jumpForward(toAreaID areaID: String) -> AreaProgressionResult? {
        guard !suppressesJump(to: areaID) else { return nil }
        guard let match = route.steps[progress.stepIndex...].firstIndex(where: { $0.expectedAreaID == areaID }),
              match >= progress.stepIndex else { return nil }
        return advance(toAreaID: areaID, transitionIndex: match)
    }

    mutating func consume(
        _ detection: AreaDetection,
        confirmationCount: Int = 2,
        forwardWindow: Int = 6
    ) -> AreaProgressionResult? {
        guard detection.confidence >= 0.55, let areaID = detection.areaID else {
            pendingAreaID = nil
            pendingCount = 0
            return nil
        }

        if areaID == progress.currentAreaID {
            pendingAreaID = nil
            pendingCount = 0
            suppressedAreaID = nil
            return nil
        }

        if areaID == suppressedAreaID {
            pendingAreaID = nil
            pendingCount = 0
            return nil
        }

        guard immediateExpectedAreaID == areaID else {
            pendingAreaID = nil
            pendingCount = 0
            return nil
        }

        if pendingAreaID == areaID { pendingCount += 1 } else {
            pendingAreaID = areaID
            pendingCount = 1
        }
        guard pendingCount >= confirmationCount else { return nil }

        let visitEnd = currentVisit?.stepRange.upperBound ?? route.steps.count
        let end = min(visitEnd, progress.stepIndex + forwardWindow + 1)
        guard progress.stepIndex < end,
              let match = route.steps[progress.stepIndex..<end].firstIndex(where: { $0.expectedAreaID == areaID }),
              match >= progress.stepIndex else { return nil }

        return advance(toAreaID: areaID, transitionIndex: match)
    }

    private mutating func advance(toAreaID areaID: String, transitionIndex: Int) -> AreaProgressionResult {
        let previousAreaID = progress.currentAreaID
        let skippedIndices = progress.stepIndex..<transitionIndex
        let skippedIDs = skippedIndices.compactMap { index -> String? in
            let id = route.steps[index].id
            guard !progress.completedStepIDs.contains(id) else { return nil }
            progress.skippedStepIDs.insert(id)
            return id
        }

        let transition = route.steps[transitionIndex]
        progress.completedStepIDs.insert(transition.id)
        progress.skippedStepIDs.remove(transition.id)
        progress.stepIndex = min(transitionIndex + 1, route.steps.count - 1)
        progress.currentAreaID = areaID
        progress.updatedAt = Date()
        recentSkippedReturnIndex = skippedIndices.first { index in
            skippedIDs.contains(route.steps[index].id)
        }
        suppressedAreaID = nil
        pendingAreaID = nil
        pendingCount = 0
        return AreaProgressionResult(
            previousAreaID: previousAreaID,
            areaID: areaID,
            skippedStepIDs: skippedIDs
        )
    }

    private mutating func normalizeProgress() {
        guard !route.steps.isEmpty else { return }
        if let areaID = progress.currentAreaID,
           currentStep?.expectedAreaID == areaID,
           progress.stepIndex + 1 < route.steps.count {
            progress.completedStepIDs.insert(route.steps[progress.stepIndex].id)
            progress.stepIndex += 1
        }
        if progress.currentAreaID == nil {
            progress.currentAreaID = currentStep?.contextAreaID
        }
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
