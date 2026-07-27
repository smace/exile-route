import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.isSnapshotRendering) private var isSnapshotRendering

    var body: some View {
        ZStack {
            OccultPanelBackground(opacity: model.overlayOpacity)
            VStack(spacing: 0) {
                header
                    .reportCompactLayoutHeight(.header)
                OrnamentalDivider()
                    .padding(.vertical, 10)
                    .reportCompactLayoutHeight(.divider)
                if let visit = model.currentVisit {
                    if let notice = model.transitionNotice {
                        transitionNotice(notice)
                            .transition(.opacity)
                            .padding(.bottom, 8)
                            .reportCompactLayoutHeight(.notice)
                    }
                    objectiveContent(currentVisit: visit)
                } else {
                    unavailable
                }
                footer
                    .reportCompactLayoutHeight(.footer)
            }
            .padding(16)
        }
        .frame(
            width: model.isExpanded ? 460 : 390,
            height: model.isExpanded ? 560 : model.compactOverlayHeight
        )
        .environment(\.sizeCategory, sizeCategory)
        .animation(.easeInOut(duration: 0.18), value: model.stepIndex)
        .animation(.easeInOut(duration: 0.18), value: model.isExpanded)
        .animation(.easeInOut(duration: 0.18), value: model.transitionNotice)
        .onPreferenceChange(CompactLayoutHeightPreferenceKey.self) { measurements in
            guard !model.isExpanded, !isSnapshotRendering,
                  let objectivesHeight = measurements[.objectives] else { return }
            let measuredHeight = CompactLayoutPart.chrome
                .compactMap { measurements[$0] }
                .reduce(objectivesHeight + 32, +)
            model.setMeasuredCompactOverlayHeight(measuredHeight)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exile Route, Act \(model.currentAct), \(model.currentAreaName)")
    }

    private var sizeCategory: ContentSizeCategory {
        model.textScale > 1.22 ? .accessibilityMedium : model.textScale > 1.08 ? .extraExtraExtraLarge : .large
    }

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("ACT \(roman(model.currentAct))")
                    .font(Theme.titleFont(size: 14 * model.textScale))
                    .tracking(2.2)
                    .foregroundStyle(Theme.agedGold)
                Text(model.currentAreaName.uppercased())
                    .font(.system(size: 11 * model.textScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            OCRStatusPill(status: model.ocrStatus)
        }
    }

    @ViewBuilder
    private func objectiveContent(currentVisit: RouteVisit) -> some View {
        if model.isExpanded {
            if isSnapshotRendering {
                expandedChecklist(currentVisit: currentVisit)
            } else {
                ScrollView {
                    expandedChecklist(currentVisit: currentVisit)
                }
                .scrollIndicators(.hidden)
            }
        } else if isSnapshotRendering {
            compactChecklist
                .reportCompactLayoutHeight(.objectives)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    compactChecklist
                        .reportCompactLayoutHeight(.objectives)
                }
                .scrollIndicators(.hidden)
                .onChange(of: model.stepIndex) { _, _ in
                    if let active = model.currentZoneObjectives.first(where: { $0.state == .active }) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            proxy.scrollTo(active.id, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func expandedChecklist(currentVisit: RouteVisit) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            visitSection(
                title: "CURRENT OBJECTIVES",
                areaName: model.areaName(for: currentVisit.areaID),
                objectives: model.objectives(in: currentVisit),
                isCurrent: true,
                showAllHints: true
            )

            ForEach(Array(model.upcomingVisits.enumerated()), id: \.element.id) { offset, visit in
                OrnamentalDivider().opacity(0.5)
                visitSection(
                    title: offset == 0 ? "NEXT AREA" : "THEN",
                    areaName: model.areaName(for: visit.areaID),
                    objectives: model.objectives(in: visit),
                    isCurrent: false,
                    showAllHints: true
                )
            }
        }
    }

    private var compactChecklist: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.currentZoneObjectives) { objective in
                objectiveRow(objective, showHints: objective.state == .active)
                    .id(objective.id)
            }
        }
    }

    private func visitSection(
        title: String,
        areaName: String,
        objectives: [RouteObjective],
        isCurrent: Bool,
        showAllHints: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(title)
                    .font(Theme.titleFont(size: 9 * model.textScale))
                    .tracking(1.2)
                    .foregroundStyle(isCurrent ? Theme.agedGold : Theme.brass.opacity(0.72))
                Text(areaName.uppercased())
                    .font(.system(size: 9 * model.textScale, weight: .medium, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            ForEach(objectives) { objective in
                objectiveRow(objective, showHints: showAllHints)
            }
        }
    }

    private func objectiveRow(_ objective: RouteObjective, showHints: Bool) -> some View {
        HStack(alignment: .top, spacing: 10) {
            ObjectiveStateGlyph(objective: objective)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text(objective.step.displayText)
                        .font(.system(
                            size: 12.5 * model.textScale,
                            weight: objective.state == .active ? .semibold : .regular
                        ))
                        .foregroundStyle(objectiveColor(objective.state))
                        .fixedSize(horizontal: false, vertical: true)
                    if objective.state == .skipped {
                        Text("SKIPPED")
                            .font(.system(size: 7.5 * model.textScale, weight: .bold, design: .monospaced))
                            .foregroundStyle(Theme.ember)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Theme.ember.opacity(0.12), in: Capsule())
                    }
                }

                if showHints {
                    ForEach(Array(objective.step.hints.enumerated()), id: \.offset) { _, hint in
                        HStack(alignment: .top, spacing: 6) {
                            Circle()
                                .fill(Theme.brass.opacity(0.72))
                                .frame(width: 3, height: 3)
                                .padding(.top, 6)
                            Text(hint)
                                .font(.system(size: 10.5 * model.textScale))
                                .foregroundStyle(Theme.muted)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 7)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(objective.state == .active ? Theme.brass.opacity(0.12) : .clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .strokeBorder(
                    objective.state == .active ? Theme.agedGold.opacity(0.42) : .clear,
                    lineWidth: 0.8
                )
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(stateLabel(objective.state)): \(objective.step.displayText)")
    }

    private func transitionNotice(_ notice: ZoneTransitionNotice) -> some View {
        HStack(spacing: 7) {
            ObjectiveCrossIndicator()
                .stroke(Theme.ember, style: StrokeStyle(lineWidth: 1.3, lineCap: .round))
                .frame(width: 10, height: 10)
            Text("\(notice.skippedCount) \(notice.skippedCount == 1 ? "OBJECTIVE" : "OBJECTIVES") SKIPPED")
            Spacer(minLength: 4)
            Text("\(model.hotKeys[.previous]?.display ?? "") TO RETURN")
        }
        .font(.system(size: 8.5 * model.textScale, weight: .bold, design: .monospaced))
        .foregroundStyle(Theme.ember)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Theme.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("\(notice.skippedCount) objectives skipped in \(notice.previousAreaName). Use Previous to return.")
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Text("THE WAY IS VEILED")
                .font(Theme.titleFont(size: 15))
                .foregroundStyle(Theme.agedGold)
            Text(model.statusText)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .frame(maxHeight: .infinity)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.brass.opacity(0.12)).frame(height: 2)
                    Capsule().fill(Theme.agedGold.opacity(0.8))
                        .frame(width: geometry.size.width * model.progressFraction, height: 2)
                }
            }
            .frame(height: 2)
            HStack(spacing: 6) {
                Text("\(model.zoneObjectivePosition) / \(max(model.currentZoneObjectives.count, 1)) OBJECTIVES")
                Text("•")
                Text("\(model.stepIndex + 1) / \(max(model.totalSteps, 1)) ROUTE")
                Spacer(minLength: 4)
                if model.isInteractionEnabled {
                    Label(
                        "DRAG ANYWHERE • \(model.hotKeys[.interact]?.display ?? "") TO LOCK",
                        systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                    )
                    .foregroundStyle(Theme.agedGold.opacity(0.9))
                } else {
                    Text("\(model.hotKeys[.previous]?.display ?? "")  \(model.hotKeys[.next]?.display ?? "")")
                }
            }
            .font(.system(size: 8.5, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.muted.opacity(0.78))
        }
        .padding(.top, 10)
    }

    private func objectiveColor(_ state: RouteObjectiveState) -> Color {
        switch state {
        case .active: Theme.ivory
        case .pending: Theme.ivory.opacity(0.68)
        case .completed: Theme.muted.opacity(0.62)
        case .skipped: Theme.ember.opacity(0.92)
        }
    }

    private func stateLabel(_ state: RouteObjectiveState) -> String {
        switch state {
        case .active: "Active"
        case .pending: "Upcoming"
        case .completed: "Completed"
        case .skipped: "Skipped"
        }
    }

    private func roman(_ value: Int) -> String {
        ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][safe: value] ?? "\(value)"
    }
}

private enum CompactLayoutPart: Hashable {
    case header
    case divider
    case notice
    case objectives
    case footer

    static let chrome: [CompactLayoutPart] = [.header, .divider, .notice, .footer]
}

private struct CompactLayoutHeightPreferenceKey: PreferenceKey {
    static let defaultValue: [CompactLayoutPart: CGFloat] = [:]

    static func reduce(
        value: inout [CompactLayoutPart: CGFloat],
        nextValue: () -> [CompactLayoutPart: CGFloat]
    ) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private extension View {
    func reportCompactLayoutHeight(_ part: CompactLayoutPart) -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: CompactLayoutHeightPreferenceKey.self,
                    value: [part: geometry.size.height]
                )
            }
        }
    }
}

private struct ObjectiveCrossIndicator: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

private struct OCRStatusPill: View {
    let status: OCRStatus

    private var presentation: (String, Color) {
        switch status {
        case .disabled: ("MANUAL", Theme.muted)
        case .waitingForGeForceNow: ("WAIT", Theme.muted)
        case .permissionRequired: ("PERMISSION", Theme.danger)
        case .scanning: ("SCANNING", Theme.waypointCyan)
        case .returningToTown: ("RETURNING", Theme.ember)
        case .recovering: ("RECOVERING", Theme.ember)
        case .noFrames: ("NO FRAMES", Theme.danger)
        case .recognized: ("SYNCED", Theme.waypointCyan)
        case .lowConfidence: ("UNCERTAIN", Theme.ember)
        case .failed: ("ERROR", Theme.danger)
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(presentation.1).frame(width: 5, height: 5)
            Text(presentation.0)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(0.7)
        }
        .foregroundStyle(presentation.1)
        .padding(.horizontal, 7)
        .padding(.vertical, 4)
        .background(presentation.1.opacity(0.1), in: Capsule())
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? { indices.contains(index) ? self[index] : nil }
}

private struct SnapshotRenderingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    var isSnapshotRendering: Bool {
        get { self[SnapshotRenderingKey.self] }
        set { self[SnapshotRenderingKey.self] = newValue }
    }
}

#if DEBUG
struct OverlayView_Previews: PreviewProvider {
    static var previews: some View {
        OverlayView().environmentObject(AppModel())
    }
}
#endif
