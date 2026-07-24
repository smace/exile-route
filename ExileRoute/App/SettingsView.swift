import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var updater: ApplicationUpdater
    @State private var selectedSection: Section = .overlay
    @State private var customRouteInput = ""
    @State private var pobInput = ""
    private let buildIdentity = BuildIdentity()

    init(initialSection: Section = .overlay) {
        _selectedSection = State(initialValue: initialSection)
    }

    enum Section: String, CaseIterable, Identifiable {
        case overlay = "Overlay"
        case route = "Route"
        case build = "Build"
        case recognition = "Recognition"
        case updates = "Updates"
        case about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .overlay: "rectangle.on.rectangle"
            case .route: "point.topleft.down.to.point.bottomright.curvepath"
            case .build: "wand.and.stars"
            case .recognition: "viewfinder"
            case .updates: "arrow.triangle.2.circlepath"
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
            Text(buildIdentity.compactDescription)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(Theme.muted.opacity(0.7))
                .help(buildIdentity.accessibleDescription)
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
        case .build: buildSettings
        case .recognition: recognitionSettings
        case .updates: updateSettings
        case .about: about
        }
    }

    private var buildSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: "Path of Building") {
                TextEditor(text: $pobInput)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 78)
                    .padding(7)
                    .background(Theme.obsidian.opacity(0.58))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.brass.opacity(0.22)))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Paste a PoB code or a supported pobb.in, poe.ninja, Maxroll, or Pastebin HTTPS URL.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    ActionButton("Import code / URL", icon: "wand.and.stars") {
                        guard !pobInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            model.statusText = "Enter a Path of Building code or URL"
                            return
                        }
                        Task { await model.importBuild(pobInput) }
                    }
                    ActionButton("Import file", icon: "doc.badge.plus", action: importPoBFile)
                }
                ActionButton("Import clipboard", icon: "clipboard", action: importPoBClipboard)
            }

            if let build = model.importedBuild {
                SettingsCard(title: "Active build") {
                    LabeledContent("Class", value: build.characterClass)
                    LabeledContent("Skill sets", value: "\(build.skillSets.count)")
                    LabeledContent("Campaign gems", value: "\(build.requiredGems.count)")
                    Divider().overlay(Theme.brass.opacity(0.3))
                    ForEach(build.skillSets) { skillSet in
                        HStack {
                            Text(skillSet.name)
                                .foregroundStyle(Theme.ivory)
                                .lineLimit(1)
                            Spacer()
                            Text("\(skillSet.gemIDs.count) \(skillSet.gemIDs.count == 1 ? "gem" : "gems")")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(Theme.muted)
                        }
                        .font(.system(size: 11))
                    }
                    if !model.buildWarnings.isEmpty {
                        Divider().overlay(Theme.brass.opacity(0.3))
                        ForEach(model.buildWarnings) { warning in
                            Label(warning.message, systemImage: "exclamationmark.triangle")
                                .font(.system(size: 10))
                                .foregroundStyle(Theme.ember)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    ActionButton("Remove build", icon: "trash") { model.removeBuild() }
                }
            } else {
                SettingsCard(title: "No active build") {
                    Text("Importing a build adds its quest rewards and vendor purchases directly to the campaign checklist. Campaign options and current progress remain unchanged.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
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
                Toggle("Move overlay freely", isOn: Binding(
                    get: { model.isInteractionEnabled }, set: { _ in model.toggleInteraction() }
                ))
                Text("Enable, then drag anywhere on the overlay. Disable again to lock its position and restore click-through.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
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
                ForEach(HotKeyAction.allCases, id: \.self) { action in
                    hotKeyRow(action)
                }
                Text("Click a shortcut, then press a key with at least two modifiers. Escape cancels.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if let message = model.hotKeyValidationMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Theme.ember)
                        .fixedSize(horizontal: false, vertical: true)
                }
                ActionButton("Restore defaults", icon: "arrow.counterclockwise") {
                    model.resetHotKeys()
                }
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
                TextEditor(text: $customRouteInput)
                    .font(.system(size: 11, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 78)
                    .padding(7)
                    .background(Theme.obsidian.opacity(0.58))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.brass.opacity(0.22)))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                Text("Paste route text, an HTTPS URL, or a Pastebin URL.")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.muted)
                HStack {
                    ActionButton("Import text / URL", icon: "text.badge.plus") {
                        guard !customRouteInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            model.statusText = "Enter route text or an HTTPS URL"
                            return
                        }
                        Task { await model.importRoute(customRouteInput) }
                    }
                    ActionButton("Import file", icon: "doc.badge.plus", action: importFile)
                }
                HStack {
                    ActionButton("Import clipboard", icon: "clipboard", action: importClipboard)
                    ActionButton("Export clipboard", icon: "doc.on.clipboard", action: exportClipboard)
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
                if let suggestion = model.suggestedAreaDetection {
                    Divider().overlay(Theme.brass.opacity(0.3))
                    Text("A distant area was recognized: \(suggestion.text). Exile Route will never jump there automatically.")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.ember)
                    HStack {
                        ActionButton("Jump to area", icon: "arrow.forward.to.line") { model.acceptSuggestedAreaJump() }
                        ActionButton("Dismiss", icon: "xmark") { model.dismissSuggestedAreaJump() }
                    }
                }
            }
            SettingsCard(title: "Calibration") {
                Text("The rectangle uses normalized window coordinates, so one calibration remains valid across resolutions. It targets Path of Exile's persistent area label in the upper-right corner.")
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.muted)
                OCRCalibrationPreview(rect: model.ocrCrop)
                    .frame(height: 150)
                HStack {
                    ActionButton("16:9 fullscreen", icon: "rectangle.ratio.16.to.9") {
                        model.setOCRCrop(.defaultAreaTitle)
                    }
                    ActionButton("16:10 / windowed", icon: "macwindow") {
                        model.setOCRCrop(NormalizedRect(x: 0.68, y: 0.84, width: 0.31, height: 0.15))
                    }
                }
                calibrationSlider("Horizontal", keyPath: \.x, range: 0...0.8)
                calibrationSlider("Vertical", keyPath: \.y, range: 0...0.9)
                calibrationSlider("Width", keyPath: \.width, range: 0.15...0.8)
                calibrationSlider("Height", keyPath: \.height, range: 0.08...0.45)
                ActionButton("Reset calibration", icon: "arrow.counterclockwise") { model.resetOCRCrop() }
            }
        }
    }

    private var about: some View {
        SettingsCard(title: "Exile Route \(buildIdentity.version)") {
            Text(buildIdentity.compactDescription)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(Theme.agedGold)
                .textSelection(.enabled)
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

    private var updateSettings: some View {
        VStack(spacing: 14) {
            SettingsCard(title: updater.updatesEnabled ? "Application updates" : "Dev build") {
                if updater.updatesEnabled {
                    if updater.distributionFlavor == .beta {
                        LabeledContent("Channel", value: "Beta")
                        Text("This pre-release build always follows the Beta channel. A later Stable release can supersede it.")
                            .font(.system(size: 10))
                            .foregroundStyle(Theme.ember)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        HStack {
                            Text("Channel")
                            Spacer()
                            HStack(spacing: 4) {
                                ForEach(UpdateChannel.allCases, id: \.self) { channel in
                                    Button {
                                        model.setUpdateChannel(channel)
                                        updater.selectChannel(channel)
                                    } label: {
                                        Text(channel.title)
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(updater.channel == channel ? Theme.ivory : Theme.muted)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                updater.channel == channel
                                                    ? Theme.brass.opacity(0.28)
                                                    : Theme.obsidian.opacity(0.5)
                                            )
                                            .clipShape(RoundedRectangle(cornerRadius: 5))
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityAddTraits(
                                        updater.channel == channel ? .isSelected : []
                                    )
                                }
                            }
                        }
                    }
                    Toggle("Automatically check for updates", isOn: Binding(
                        get: { updater.automaticallyChecksForUpdates },
                        set: { updater.automaticallyChecksForUpdates = $0 }
                    ))
                    if updater.distributionFlavor != .beta {
                        Text(updateChannelDescription)
                            .font(.system(size: 10))
                            .foregroundStyle(updater.channel == .beta ? Theme.ember : Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    ActionButton("Check now", icon: "arrow.triangle.2.circlepath") {
                        updater.checkForUpdates()
                    }
                } else {
                    Label("Automatic updates are disabled for local Dev builds.", systemImage: "hammer")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Theme.agedGold)
                    Text("Dev uses a separate application identity and Application Support directory, so it can coexist with Stable without changing user data or update preferences.")
                        .font(.system(size: 10))
                        .foregroundStyle(Theme.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            SettingsCard(title: "Build identity") {
                Text(buildIdentity.compactDescription)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Theme.ivory)
                    .textSelection(.enabled)
                Text("Distribution: \(updater.distributionFlavor.rawValue.uppercased())")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var sectionSubtitle: String {
        switch selectedSection {
        case .overlay: "A quiet guide above the stream."
        case .route: "Shape the road through Wraeclast."
        case .build: "Carry the right gems into exile."
        case .recognition: "Private, on-device zone detection."
        case .updates: "Choose how close to the edge you travel."
        case .about: "Open source, original, and built for macOS."
        }
    }

    private var updateChannelDescription: String {
        switch updater.channel {
        case .stable:
            "Stable receives tested public releases only."
        case .beta:
            "Beta also receives pre-release builds. A later Stable release will always supersede its beta."
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

    private func calibrationSlider(
        _ title: String,
        keyPath: WritableKeyPath<NormalizedRect, Double>,
        range: ClosedRange<Double>
    ) -> some View {
        LabeledSlider(title: title, value: Binding(
            get: { model.ocrCrop[keyPath: keyPath] },
            set: { value in
                var crop = model.ocrCrop
                crop[keyPath: keyPath] = value
                model.setOCRCrop(crop)
            }
        ), range: range)
    }

    private func hotKeyRow(_ action: HotKeyAction) -> some View {
        let definition = model.hotKeys[action] ?? HotKeyDefinition.defaults[action]!
        return HStack {
            Text(action.title)
            Spacer()
            HotKeyRecorder(
                definition: definition,
                accessibilityLabel: "\(action.title) shortcut"
            ) { candidate in
                model.setHotKey(candidate, for: action)
            }
            .frame(width: 122, height: 28)
        }
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

    private func importPoBClipboard() {
        guard let source = NSPasteboard.general.string(forType: .string), !source.isEmpty else {
            model.statusText = "Clipboard does not contain a Path of Building code"
            return
        }
        pobInput = source
        Task { await model.importBuild(source) }
    }

    private func importPoBFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .xml]
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url,
              let source = try? String(contentsOf: url, encoding: .utf8) else { return }
        pobInput = source
        Task { await model.importBuild(source) }
    }

    private func exportRoute() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "exile-route.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do { try model.exportRoute(to: url); model.statusText = "Route exported" }
        catch { model.statusText = error.localizedDescription }
    }

    private func exportClipboard() {
        guard let source = model.route?.source else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(source, forType: .string)
        model.statusText = "Route copied to clipboard"
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

private struct OCRCalibrationPreview: View {
    let rect: NormalizedRect

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                LinearGradient(
                    colors: [Theme.smokedSurface, Theme.obsidian],
                    startPoint: .top,
                    endPoint: .bottom
                )
                VStack(spacing: 5) {
                    Text("GEFORCE NOW WINDOW")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(Theme.muted.opacity(0.55))
                    Spacer()
                }
                .padding(8)
                Path { path in
                    let width = geometry.size.width * rect.width
                    let height = geometry.size.height * rect.height
                    let x = geometry.size.width * rect.x
                    let y = geometry.size.height * (1 - rect.y - rect.height)
                    path.addRoundedRect(in: CGRect(x: x, y: y, width: width, height: height), cornerSize: CGSize(width: 5, height: 5))
                }
                .fill(Theme.waypointCyan.opacity(0.12))
                Path { path in
                    let width = geometry.size.width * rect.width
                    let height = geometry.size.height * rect.height
                    let x = geometry.size.width * rect.x
                    let y = geometry.size.height * (1 - rect.y - rect.height)
                    path.addRoundedRect(in: CGRect(x: x, y: y, width: width, height: height), cornerSize: CGSize(width: 5, height: 5))
                }
                .stroke(Theme.waypointCyan, style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
                Text("AREA TITLE")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.waypointCyan)
                    .position(
                        x: geometry.size.width * (rect.x + rect.width / 2),
                        y: geometry.size.height * (1 - rect.y - rect.height / 2)
                    )
            }
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).stroke(Theme.brass.opacity(0.25)))
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
