import AppKit
import SwiftUI

struct OccultPanelBackground: View {
    let opacity: Double

    var body: some View {
        ZStack {
            VisualEffectView(material: .hudWindow, blendingMode: .behindWindow)
            LinearGradient(
                colors: [Theme.obsidian.opacity(opacity), Theme.smokedSurface.opacity(opacity * 0.96)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GrainTexture()
                .opacity(0.16)
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Theme.agedGold.opacity(0.88), Theme.brass.opacity(0.25), Theme.agedGold.opacity(0.64)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
            CornerOrnaments()
                .stroke(Theme.brass.opacity(0.7), style: StrokeStyle(lineWidth: 0.8, lineCap: .round))
                .padding(5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct VisualEffectView: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
    }
}

struct GrainTexture: View {
    var body: some View {
        Canvas { context, size in
            var generator = SeededGenerator(seed: 0xE11E)
            for _ in 0..<120 {
                let x = Double.random(in: 0...size.width, using: &generator)
                let y = Double.random(in: 0...size.height, using: &generator)
                let alpha = Double.random(in: 0.03...0.11, using: &generator)
                context.fill(
                    Path(ellipseIn: CGRect(x: x, y: y, width: 0.7, height: 0.7)),
                    with: .color(.white.opacity(alpha))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return state
    }
}

struct CornerOrnaments: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let length: CGFloat = 19
        let notch: CGFloat = 6
        let corners = [
            (CGPoint(x: rect.minX, y: rect.minY), CGFloat(1), CGFloat(1)),
            (CGPoint(x: rect.maxX, y: rect.minY), CGFloat(-1), CGFloat(1)),
            (CGPoint(x: rect.minX, y: rect.maxY), CGFloat(1), CGFloat(-1)),
            (CGPoint(x: rect.maxX, y: rect.maxY), CGFloat(-1), CGFloat(-1))
        ]
        for (origin, sx, sy) in corners {
            path.move(to: CGPoint(x: origin.x + sx * length, y: origin.y))
            path.addLine(to: CGPoint(x: origin.x + sx * notch, y: origin.y))
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + sy * notch))
            path.addLine(to: CGPoint(x: origin.x, y: origin.y + sy * length))
            path.move(to: CGPoint(x: origin.x + sx * 8, y: origin.y + sy * 3))
            path.addLine(to: CGPoint(x: origin.x + sx * 3, y: origin.y + sy * 8))
        }
        return path
    }
}

struct WaypointSigil: Shape {
    func path(in rect: CGRect) -> Path {
        let inset = rect.insetBy(dx: rect.width * 0.18, dy: rect.height * 0.18)
        var path = Path(ellipseIn: inset)
        path.addEllipse(in: rect.insetBy(dx: rect.width * 0.34, dy: rect.height * 0.34))
        path.move(to: CGPoint(x: rect.midX, y: rect.minY + 1))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.minY + rect.height * 0.18))
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY - 1))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.18))
        return path
    }
}

struct RouteGlyph: View {
    let step: RouteStep

    private var color: Color {
        if step.fragments.contains(where: { $0.kind == .kill || $0.kind == .arena }) { return Theme.ember }
        if step.fragments.contains(where: { $0.kind == .waypoint || $0.kind == .waypointGet }) { return Theme.waypointCyan }
        return Theme.brass
    }

    var body: some View {
        ZStack {
            Diamond()
                .stroke(color.opacity(0.8), lineWidth: 1)
            if step.fragments.contains(where: { $0.kind == .waypoint || $0.kind == .waypointGet }) {
                WaypointSigil().stroke(color, lineWidth: 1)
                    .padding(4)
            } else if step.fragments.contains(where: { $0.kind == .kill || $0.kind == .arena }) {
                Circle().fill(color).frame(width: 5, height: 5)
            } else {
                Circle().stroke(color, lineWidth: 1).frame(width: 7, height: 7)
            }
        }
        .frame(width: 22, height: 22)
        .accessibilityHidden(true)
    }
}

struct ObjectiveStateGlyph: View {
    let objective: RouteObjective

    var body: some View {
        RouteGlyph(step: objective.step)
            .opacity(objective.state == .completed ? 0.46 : objective.state == .pending ? 0.72 : 1)
            .overlay {
                switch objective.state {
                case .completed:
                    ObjectiveCheckmark()
                        .stroke(Theme.waypointCyan, style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                        .padding(5)
                case .skipped:
                    ObjectiveCross()
                        .stroke(Theme.ember, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                        .padding(6)
                case .active, .pending:
                    EmptyView()
                }
            }
            .shadow(
                color: objective.state == .active ? Theme.ember.opacity(0.55) : .clear,
                radius: objective.state == .active ? 5 : 0
            )
            .animation(.easeInOut(duration: 0.18), value: objective.state)
            .accessibilityHidden(true)
    }
}

private struct ObjectiveCheckmark: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

private struct ObjectiveCross: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        return path
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}

struct OrnamentalDivider: View {
    var body: some View {
        HStack(spacing: 7) {
            Rectangle().fill(Theme.brass.opacity(0.34)).frame(height: 1)
            Diamond().fill(Theme.agedGold.opacity(0.9)).frame(width: 6, height: 6)
            Rectangle().fill(Theme.brass.opacity(0.34)).frame(height: 1)
        }
        .accessibilityHidden(true)
    }
}
