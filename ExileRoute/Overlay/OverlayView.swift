import SwiftUI

struct OverlayView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            OccultPanelBackground(opacity: model.overlayOpacity)
            VStack(spacing: 0) {
                header
                OrnamentalDivider().padding(.vertical, 10)
                if let step = model.currentStep {
                    current(step)
                    if model.isExpanded { expandedRoute }
                    else if let next = model.nextStep { nextStep(next) }
                } else {
                    unavailable
                }
                footer
            }
            .padding(16)
        }
        .frame(width: model.isExpanded ? 460 : 390, height: model.isExpanded ? 560 : nil)
        .fixedSize(horizontal: false, vertical: !model.isExpanded)
        .environment(\.sizeCategory, sizeCategory)
        .animation(.easeInOut(duration: 0.18), value: model.stepIndex)
        .animation(.easeInOut(duration: 0.18), value: model.isExpanded)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Exile Route, Act \(model.currentAct)")
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
                Text(zoneTitle)
                    .font(.system(size: 11 * model.textScale, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            OCRStatusPill(status: model.ocrStatus)
        }
    }

    private var zoneTitle: String {
        model.currentAreaName.uppercased()
    }

    private func current(_ step: RouteStep) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RouteGlyph(step: step).padding(.top, 2)
            VStack(alignment: .leading, spacing: 8) {
                Text(step.displayText)
                    .font(.system(size: 16 * model.textScale, weight: .semibold))
                    .foregroundStyle(Theme.ivory)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(step.hints.prefix(model.isExpanded ? 6 : 2).enumerated()), id: \.offset) { _, hint in
                    HStack(alignment: .top, spacing: 7) {
                        Circle().fill(Theme.brass.opacity(0.75)).frame(width: 3, height: 3).padding(.top, 6)
                        Text(hint)
                            .font(.system(size: 12 * model.textScale, weight: .regular))
                            .foregroundStyle(Theme.muted)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .id(step.id)
        .transition(.opacity.combined(with: .move(edge: .bottom)))
    }

    private func nextStep(_ step: RouteStep) -> some View {
        VStack(spacing: 9) {
            OrnamentalDivider().opacity(0.65).padding(.top, 12)
            HStack(alignment: .top, spacing: 10) {
                Text("NEXT")
                    .font(Theme.titleFont(size: 9 * model.textScale))
                    .tracking(1.2)
                    .foregroundStyle(Theme.brass.opacity(0.8))
                    .padding(.top, 2)
                Text(step.displayText)
                    .font(.system(size: 12 * model.textScale))
                    .foregroundStyle(Theme.ivory.opacity(0.66))
                    .lineLimit(2)
                Spacer(minLength: 0)
            }
        }
    }

    private var expandedRoute: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 7) {
                    ForEach(visibleSteps) { step in
                        HStack(alignment: .top, spacing: 9) {
                            RouteGlyph(step: step).scaleEffect(0.72)
                            Text(step.displayText)
                                .font(.system(size: 12 * model.textScale, weight: step.id == model.currentStep?.id ? .semibold : .regular))
                                .foregroundStyle(step.id == model.currentStep?.id ? Theme.ivory : Theme.muted)
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .padding(.horizontal, 6)
                        .background(step.id == model.currentStep?.id ? Theme.brass.opacity(0.12) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .id(step.id)
                    }
                }
            }
            .scrollIndicators(.hidden)
            .padding(.top, 14)
            .onChange(of: model.stepIndex) { _, _ in
                if let id = model.currentStep?.id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
            }
        }
    }

    private var visibleSteps: [RouteStep] {
        guard let steps = model.route?.steps, !steps.isEmpty else { return [] }
        let lower = max(0, model.stepIndex - 3)
        let upper = min(steps.count, model.stepIndex + 10)
        return Array(steps[lower..<upper])
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
        .padding(.vertical, 20)
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
            HStack {
                Text("\(model.stepIndex + 1) / \(max(model.totalSteps, 1))")
                Spacer()
                if model.isInteractionEnabled { Label("INTERACT", systemImage: "hand.point.up.left") }
                else {
                    Text("\(model.hotKeys[.previous]?.display ?? "")  \(model.hotKeys[.next]?.display ?? "")")
                }
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Theme.muted.opacity(0.78))
        }
        .padding(.top, 12)
    }

    private func roman(_ value: Int) -> String {
        ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"][safe: value] ?? "\(value)"
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

#if DEBUG
struct OverlayView_Previews: PreviewProvider {
    static var previews: some View {
        OverlayView().environmentObject(AppModel())
    }
}
#endif
