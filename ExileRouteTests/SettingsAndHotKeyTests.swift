import AppKit
import Carbon
import SwiftUI
import XCTest
@testable import ExileRoute

final class SettingsAndHotKeyTests: XCTestCase {
    func testModifierPresetRecognizesSupportedCombinations() {
        XCTAssertEqual(
            HotKeyModifierPreset(eventModifiers: [.control, .option]),
            .controlOption
        )
        XCTAssertEqual(
            HotKeyModifierPreset(eventModifiers: [.control, .option, .command, .shift]),
            .controlOptionCommandShift
        )
        XCTAssertNil(HotKeyModifierPreset(eventModifiers: [.command]))
    }

    @MainActor
    func testRecorderAcceptsAnExtendedShortcut() {
        let button = HotKeyRecorderButton()
        var recorded: HotKeyDefinition?
        button.onRecord = {
            recorded = $0
            return true
        }
        button.beginRecording()

        let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .option, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "k",
            charactersIgnoringModifiers: "k",
            isARepeat: false,
            keyCode: UInt16(kVK_ANSI_K)
        )!
        button.keyDown(with: event)

        XCTAssertEqual(
            recorded,
            HotKeyDefinition(
                keyCode: UInt32(kVK_ANSI_K),
                modifiers: .controlOptionShift
            )
        )
        XCTAssertFalse(button.isRecording)
    }

    @MainActor
    func testModelRejectsDuplicateShortcutsAndRestoresDefaults() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let existing = model.hotKeys[.next]!

        XCTAssertFalse(model.setHotKey(existing, for: .previous))
        XCTAssertEqual(model.hotKeys[.previous], HotKeyDefinition.defaults[.previous])
        XCTAssertNotNil(model.hotKeyValidationMessage)

        let custom = HotKeyDefinition(
            keyCode: UInt32(kVK_ANSI_K),
            modifiers: .controlOptionShift
        )
        XCTAssertTrue(model.setHotKey(custom, for: .previous))
        XCTAssertEqual(model.hotKeys[.previous], custom)

        model.resetHotKeys()
        XCTAssertEqual(model.hotKeys, HotKeyDefinition.defaults)
    }

    @MainActor
    func testSettingsControllerCreatesOneReusablePopulatedWindow() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let updater = ApplicationUpdater(channel: .stable, distributionFlavor: .dev)
        let controller = SettingsWindowController(model: model, updater: updater)
        let window = controller.window

        XCTAssertEqual(window?.title, "Exile Route Settings")
        XCTAssertEqual(window?.contentMinSize, SettingsWindowController.minimumSize)
        XCTAssertNotNil(window?.contentViewController)

        controller.showSettings()
        XCTAssertTrue(window?.isVisible == true)
        controller.showSettings()
        XCTAssertTrue(controller.window === window)
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        if let contentView = window?.contentView,
           let representation = contentView.bitmapImageRepForCachingDisplay(in: contentView.bounds) {
            contentView.cacheDisplay(in: contentView.bounds, to: representation)
            if let data = representation.representation(using: .png, properties: [:]) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
                attachment.name = "settings-shortcut-editor"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        if ProcessInfo.processInfo.environment["EXILE_ROUTE_INTERACTIVE_QA"] == "1" {
            RunLoop.current.run(until: Date().addingTimeInterval(15))
        }
        controller.close()
    }

    @MainActor
    func testStatusMenuSettingsItemInvokesExplicitWindowAction() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        var openCount = 0
        let statusBar = StatusBarController(
            model: model,
            openSettings: { openCount += 1 }
        )

        let settingsItem = statusBar.menuItems.first(where: { $0.title == "Settings…" })
        XCTAssertNotNil(settingsItem)
        if let settingsItem, let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        }
        XCTAssertEqual(openCount, 1)
    }

    @MainActor
    func testStatusMenuAppUpdateItemInvokesExplicitUpdaterAction() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        var updateCount = 0
        let statusBar = StatusBarController(
            model: model,
            openSettings: {},
            checkForAppUpdates: { updateCount += 1 }
        )

        let updateItem = statusBar.menuItems.first(where: { $0.title == "Check for app updates…" })
        XCTAssertNotNil(updateItem)
        if let updateItem, let action = updateItem.action {
            NSApp.sendAction(action, to: updateItem.target, from: updateItem)
        }
        XCTAssertEqual(updateCount, 1)
    }

    @MainActor
    func testStatusMenuHidesAppUpdateActionWhenUpdaterIsDisabled() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let statusBar = StatusBarController(model: model, openSettings: {})

        XCTAssertNil(statusBar.menuItems.first(where: { $0.title == "Check for app updates…" }))
    }

    func testUpdateChannelsAndDevDataAreIsolated() {
        XCTAssertEqual(UpdateChannel.stable.allowedSparkleChannels, [])
        XCTAssertEqual(UpdateChannel.beta.allowedSparkleChannels, ["beta"])
        XCTAssertEqual(
            ApplicationDataLocation.directoryName(bundleIdentifier: "com.swannmace.ExileRoute"),
            "Exile Route"
        )
        XCTAssertEqual(
            ApplicationDataLocation.directoryName(bundleIdentifier: "com.swannmace.ExileRoute.Dev"),
            "Exile Route Dev"
        )
    }

    @MainActor
    func testDistributionFlavorSelectsSafeUpdateBehavior() {
        let stable = ApplicationUpdater(channel: .stable, distributionFlavor: .stable)
        let optedInStable = ApplicationUpdater(channel: .beta, distributionFlavor: .stable)
        let beta = ApplicationUpdater(channel: .stable, distributionFlavor: .beta)
        let dev = ApplicationUpdater(channel: .beta, distributionFlavor: .dev)

        XCTAssertEqual(stable.channel, .stable)
        XCTAssertEqual(optedInStable.channel, .beta)
        XCTAssertEqual(beta.channel, .beta)
        XCTAssertFalse(dev.updatesEnabled)
    }

    @MainActor
    func testProductionUpdaterIgnoresEnvironmentFeedOverride() {
        let bundledFeed = "https://example.com/stable-appcast.xml"
        let environment = ["EXILE_ROUTE_UPDATE_FEED_URL": "https://example.com/test-appcast.xml"]
        let stable = ApplicationUpdater(
            channel: .stable,
            distributionFlavor: .stable,
            environment: environment,
            bundledFeedURL: bundledFeed
        )
        let beta = ApplicationUpdater(
            channel: .stable,
            distributionFlavor: .beta,
            environment: environment,
            bundledFeedURL: bundledFeed
        )

        XCTAssertEqual(stable.resolvedFeedURLString, bundledFeed)
        XCTAssertEqual(beta.resolvedFeedURLString, bundledFeed)
    }

    @MainActor
    func testDevUpdaterMayUseEnvironmentFeedOverride() {
        let updater = ApplicationUpdater(
            channel: .stable,
            distributionFlavor: .dev,
            environment: ["EXILE_ROUTE_UPDATE_FEED_URL": "https://example.com/test-appcast.xml"],
            bundledFeedURL: "https://example.com/stable-appcast.xml"
        )

        XCTAssertEqual(updater.resolvedFeedURLString, "https://example.com/test-appcast.xml")
    }

    @MainActor
    func testUpdatesSettingsVisualReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let updater = ApplicationUpdater(channel: .beta, distributionFlavor: .stable)
        let view = SettingsView(initialSection: .updates)
            .environmentObject(model)
            .environmentObject(updater)
            .frame(width: 760, height: 560)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 560)
        for _ in 0..<5 {
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        let png = try XCTUnwrap(representation.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "settings-update-channels"
        attachment.lifetime = .keepAlways
        add(attachment)

        if let outputPath = ProcessInfo.processInfo.environment["EXILE_ROUTE_SETTINGS_REFERENCE_OUTPUT"] {
            try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    @MainActor
    func testBuildSettingsVisualReferences() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let updater = ApplicationUpdater(channel: .stable, distributionFlavor: .dev)

        let emptyPNG = try renderSettings(section: .build, model: model, updater: updater)
        let emptyAttachment = XCTAttachment(data: emptyPNG, uniformTypeIdentifier: "public.png")
        emptyAttachment.name = "settings-build-empty"
        emptyAttachment.lifetime = .keepAlways
        add(emptyAttachment)
        if let outputPath = ProcessInfo.processInfo.environment["EXILE_ROUTE_BUILD_EMPTY_REFERENCE_OUTPUT"] {
            try emptyPNG.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }

        await model.importBuild(TestPoBFixtures.multiSkillSet)

        let importedPNG = try renderSettings(section: .build, model: model, updater: updater)
        let importedAttachment = XCTAttachment(data: importedPNG, uniformTypeIdentifier: "public.png")
        importedAttachment.name = "settings-build-imported"
        importedAttachment.lifetime = .keepAlways
        add(importedAttachment)
        if let outputPath = ProcessInfo.processInfo.environment["EXILE_ROUTE_BUILD_REFERENCE_OUTPUT"] {
            try importedPNG.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    @MainActor
    func testRecognitionRecoverySettingsVisualReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = AppModel(persistence: PersistenceStore(baseURL: directory))
        let updater = ApplicationUpdater(channel: .stable, distributionFlavor: .dev)
        model.ocrStatus = .recovering
        model.updateTrackingHealth(lastFrameAt: Date().addingTimeInterval(-6), restartCount: 2)

        let png = try renderSettings(section: .recognition, model: model, updater: updater)
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "settings-recognition-recovering"
        attachment.lifetime = .keepAlways
        add(attachment)
        if let outputPath = ProcessInfo.processInfo.environment["EXILE_ROUTE_RECOGNITION_REFERENCE_OUTPUT"] {
            try png.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        }
    }

    @MainActor
    private func renderSettings(
        section: SettingsView.Section,
        model: AppModel,
        updater: ApplicationUpdater
    ) throws -> Data {
        let view = SettingsView(initialSection: section)
            .environmentObject(model)
            .environmentObject(updater)
            .frame(width: 760, height: 620)
        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = NSRect(x: 0, y: 0, width: 760, height: 620)
        for _ in 0..<5 {
            hostingView.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        let representation = try XCTUnwrap(
            hostingView.bitmapImageRepForCachingDisplay(in: hostingView.bounds)
        )
        hostingView.cacheDisplay(in: hostingView.bounds, to: representation)
        return try XCTUnwrap(representation.representation(using: .png, properties: [:]))
    }
}
