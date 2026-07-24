import AppKit
import Carbon
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
        let controller = SettingsWindowController(model: model)
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
        let statusBar = StatusBarController(model: model) {
            openCount += 1
        }

        let settingsItem = statusBar.menuItems.first(where: { $0.title == "Settings…" })
        XCTAssertNotNil(settingsItem)
        if let settingsItem, let action = settingsItem.action {
            NSApp.sendAction(action, to: settingsItem.target, from: settingsItem)
        }
        XCTAssertEqual(openCount, 1)
    }
}
