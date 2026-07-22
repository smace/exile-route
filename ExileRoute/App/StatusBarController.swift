import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject {
    private let model: AppModel
    private let item: NSStatusItem
    private var cancellables: Set<AnyCancellable> = []

    init(model: AppModel) {
        self.model = model
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()
        item.button?.title = "◇"
        item.button?.font = NSFont(name: "Cinzel", size: 16) ?? .systemFont(ofSize: 15, weight: .medium)
        item.button?.toolTip = "Exile Route"
        rebuildMenu()
        model.$statusText.sink { [weak self] _ in self?.rebuildMenu() }.store(in: &cancellables)
    }

    private func rebuildMenu() {
        let menu = NSMenu()
        let status = NSMenuItem(title: model.statusText, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)
        menu.addItem(.separator())
        add("Previous step", action: #selector(previous), shortcut: "⌃⌥←", to: menu)
        add("Next step", action: #selector(next), shortcut: "⌃⌥→", to: menu)
        add(model.isExpanded ? "Compact overlay" : "Expand route", action: #selector(expand), shortcut: "⌃⌥Space", to: menu)
        add(model.forceVisible ? "Use automatic visibility" : "Show overlay preview", action: #selector(toggleOverlay), shortcut: "⌃⌥O", to: menu)
        add(model.isInteractionEnabled ? "Enable click-through" : "Interaction mode", action: #selector(interact), shortcut: "⌃⌥I", to: menu)
        menu.addItem(.separator())
        add("Settings…", action: #selector(openSettings), shortcut: "", to: menu)
        add("Check route updates", action: #selector(updateRoutes), shortcut: "", to: menu)
        add("Reset progress", action: #selector(reset), shortcut: "", to: menu)
        menu.addItem(.separator())
        add("Quit Exile Route", action: #selector(quit), shortcut: "⌘Q", to: menu)
        item.menu = menu
    }

    private func add(_ title: String, action: Selector, shortcut: String, to menu: NSMenu) {
        let entry = NSMenuItem(title: title, action: action, keyEquivalent: "")
        entry.target = self
        entry.toolTip = shortcut
        menu.addItem(entry)
    }

    @objc private func previous() { model.movePrevious() }
    @objc private func next() { model.moveNext() }
    @objc private func expand() { model.toggleExpanded(); rebuildMenu() }
    @objc private func toggleOverlay() { model.toggleOverlay(); rebuildMenu() }
    @objc private func interact() { model.toggleInteraction(); rebuildMenu() }
    @objc private func reset() { model.resetProgress() }
    @objc private func updateRoutes() { Task { await model.updateRoutes() } }
    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

