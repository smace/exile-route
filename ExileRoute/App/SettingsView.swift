import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedSection: Section = .overlay

    enum Section: String, CaseIterable, Identifiable {
        case overlay = "Overlay"
        case route = "Route"
        case recognition = "Recognition"
        case about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overlay: "rectangle.on.rectangle"
            case .route: "point.topleft.down.to.point.bottomright.curvepath"
            case .recognition: "viewfinder"
            case .about: "seal"
            }
        }
    }

    var body: some View {
        ZStack {
            Theme.obsidian.ignoresSafeArea()
            HStack(spacing: 0) {
                sidebar
                Rectangle().fill(Theme.brass.opacity(0.28)).frame(width: 1)
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        title
                        content
                    }
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("EXILE ROUTE")
                .font(Theme.titleFont(size: 17))
                .tracking(1.7)
                .foregroundStyle(Theme.agedGold)
                .padding(.bottom, 18)
            ForEach(Section.allCases) { section in
                Button {
                    selectedSection = section
                } label: {
                    Label(section.rawValue, systemImage: section.icon)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selectedSection == section ? Theme.ivory : Theme.muted)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(selectedSection == section ? Theme.brass.opacity(0.14) : .clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            Spacer()
            Text(String(model.snapshotCommit.prefix(8)))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.muted.opacity(0.7))
        }
        .padding(20)
        .frame(width: 158)
        .background(Theme.smokedSurface.opacity(0.72))
    }

    private var title: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(selectedSection.rawValue.uppercased())
                .font(Theme.titleFont(size: 22))
                .tracking(1.8)
                .foregroundStyle(Theme.agedGold)
            Text(sectionSubtitle)
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
        }
    }

    @ViewBuilder private var content: some View {
        switch selectedSection {
        case .overlay: overlaySettings
        case .route: routeSettings
        case .recognition: recognitionSettings
        case .about: about
        }
    }

    private var overlaySettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Visibility") {
                Toggle("Show preview outside GeForce NOW", isOn: Binding(
                    get: { model.forceVisible }, set: { _ in model.toggleOverlay() }
                ))
                Toggle("Expanded route", isOn: Binding(
                    get: { model.isExpanded }, set: { _ in model.toggleExpanded() }
                ))
                Toggle("Interaction mode", isOn: Binding(
                    get: { model.isInteractionEnabled }, set: { _ in model.toggleInteraction() }
                ))
            }
            SettingsCard(title: "Appearance") {
                LabeledSlider(title: "Opacity", value: Binding(
                    get: { model.overlayOpacity }, set: { model.setOverlayOpacity($0) }
                ), range: 0.55...1)
                LabeledSlider(title: "Text size", value: Binding(
                    get: { model.textScale }, set: { model.setTextScale($0) }
                ), range: 0.8...1.35)
            }
            SettingsCard(title: "Global shortcuts") {
                shortcut("Previous step", "⌃⌥←")
                shortcut("Next step", "⌃⌥→")
                shortcut("Compact / expanded", "⌃⌥Space")
                shortcut("Overlay visibility", "⌃⌥O")
                shortcut("Interaction mode", "⌃⌥I")
            }
        }
    }

    private var routeSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Campaign options") {
                Toggle("League start route", isOn: routeConfigurationBinding(\.leagueStart))
                Toggle("Include Library quest", isOn: routeConfigurationBinding(\.includeLibrary))
                Picker("Bandit choice", selection: Binding(
                    get: { model.routeConfiguration.bandit },
                    set: { value in var config = model.routeConfiguration; config.bandit = value; model.applyRouteConfiguration(config) }
                )) {
                    ForEach(BanditChoice.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
            }
            SettingsCard(title: "Custom route") {
                HStack {
                    ActionButton("Import file", icon: "doc.badge.plus", action: importFile)
                    ActionButton("Import clipboard", icon: "clipboard", action: importClipboard)
                }
                HStack {
                    ActionButton("Export…", icon: "square.and.arrow.up", action: exportRoute)
                    ActionButton("Restore bundled", icon: "arrow.counterclockwise") { model.restoreBundledRoute() }
                }
            }
            SettingsCard(title: "Upstream snapshot") {
                Text("Current commit: \(model.snapshotCommit)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.muted)
                ActionButton("Check for route updates", icon: "arrow.triangle.2.circlepath") {
                    Task { await model.updateRoutes() }
                }
                ActionButton("Reset campaign progress", icon: "flag.checkered") { model.resetProgress() }
            }
        }
    }

    private var recognitionSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Local area recognition") {
                Toggle("OCR auto-progress", isOn: Binding(
                    get: { model.isOCRActive }, set: { model.setOCRActive($0) }
                ))
                Text("Only the GeForce NOW window is sampled. Frames are processed by Apple Vision and are never stored or uploaded.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Circle().fill(ocrColor).frame(width: 7, height: 7)
                    Text(ocrDescription)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.ivory)
                }
            }
            SettingsCard(title: "Calibration") {
                Text("The default capture region targets the upper-center area title. Use calibration while Path of Exile is visible if your stream layout differs.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                ActionButton("Calibrate capture region", icon: "viewfinder") {
                    model.statusText = "Calibration opens when GeForce NOW is active"
                }
            }
        }
    }

    private var about: some View {
        SettingsCard(title: "Exile Route 1.0.0") {
            Text("A native campaign companion for Path of Exile on GeForce NOW.")
                .foregroundStyle(Theme.ivory)
            Text("Original interface and icons by the Exile Route project. Route data derived from HeartofPhos/exile-leveling under the MIT license. Not affiliated with Grinding Gear Games.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Link("View source on GitHub", destination: URL(string: "https://github.com/smace/exile-route")!)
                .foregroundStyle(Theme.waypointCyan)
        }
    }

    private var sectionSubtitle: String {
        switch selectedSection {
        case .overlay: "A quiet guide above the stream."
        case .route: "Shape the road through Wraeclast."
        case .recognition: "Private, on-device zone detection."
        case .about: "Open source, original, and built for macOS."
        }
    }

    private func routeConfigurationBinding(_ keyPath: WritableKeyPath<RouteConfiguration, Bool>) -> Binding<Bool> {
        Binding(
            get: { model.routeConfiguration[keyPath: keyPath] },
            set: { value in
                var config = model.routeConfiguration
                config[keyPath: keyPath] = value
                model.applyRouteConfiguration(config)
            }
        )
    }

    private func shortcut(_ name: String, _ keys: String) -> some View {
        HStack { Text(name); Spacer(); Text(keys).foregroundStyle(Theme.agedGold) }
            .font(.system(size: 11, design: .rounded))
    }

    private func importClipboard() {
        guard let source = NSPasteboard.general.string(forType: .string), !source.isEmpty else {
            model.statusText = "Clipboard does not contain a route"
            return
        }
        Task { await model.importRoute(source) }
    }

    private func importFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        Task { await model.importRoute(source) }
    }

    private func exportRoute() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "exile-route.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportRoute(to: url); model.statusText = "Route exported" }
        catch { model.statusText = error.localizedDescription }
    }

    private var ocrDescription: String {
        switch model.ocrStatus {
        case .disabled: "Manual mode"
        case .waitingForGeForceNow: "Waiting for GeForce NOW"
        case .permissionRequired: "Screen Recording permission required"
        case .scanning: "Scanning for an area title"
        case .recognized(let name): "Recognized \(name)"
        case .lowConfidence: "Area title confidence is too low"
        case .failed(let message): message
        }
    }

    private var ocrColor: Color {
        switch model.ocrStatus {
        case .recognized, .scanning: Theme.waypointCyan
        case .permissionRequired, .failed: Theme.danger
        case .lowConfidence: Theme.ember
        default: Theme.muted
        }
    }
}

private struct SettingsCard<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title.uppercased())
                .font(Theme.titleFont(size: 11))
                .tracking(1.2)
                .foregroundStyle(Theme.brass)
            content
        }
        .font(.system(size: 12))
        .foregroundStyle(Theme.ivory)
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.smokedSurface.opacity(0.7))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.brass.opacity(0.2), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct LabeledSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        HStack {
            Text(title).frame(width: 68, alignment: .leading)
            Slider(value: $value, in: range).tint(Theme.brass)
            Text("\(Int(value * 100))%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(Theme.muted)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

private struct ActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    init(_ title: String, icon: String, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.ivory)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(Theme.brass.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.brass.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .buttonStyle(.plain)
    }
}
