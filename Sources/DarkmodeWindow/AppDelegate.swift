import AppKit
import Carbon

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    private let settings = Settings.shared
    private var statusItem: NSStatusItem!
    private var overlay: OverlayController!
    private var hotKeys: [HotKey] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = makeMainMenu()
        overlay = OverlayController()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "moon.fill", accessibilityDescription: "DarkmodeWindow")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu

        hotKeys.append(HotKey(keyCode: kVK_ANSI_D, modifiers: controlKey | optionKey | cmdKey, id: 1) { [weak self] in
            self?.overlay.toggle()
        })
        hotKeys.append(HotKey(keyCode: kVK_ANSI_A, modifiers: controlKey | optionKey | cmdKey, id: 2) { [weak self] in
            self?.toggleAutoPosition()
        })

        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
        overlay.show()
    }

    /// Clicking the Dock icon brings the overlay back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !overlay.isShown { overlay.show() }
        return false
    }

    // MARK: Main menu (Dock app)

    private func makeMainMenu() -> NSMenu {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "DarkmodeWindow ausblenden", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "DarkmodeWindow beenden", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Fenster")
        let toggle = item("Fenster ein-/ausblenden", #selector(toggleWindow), key: "d")
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        windowMenu.addItem(toggle)
        windowMenu.addItem(.separator())
        windowMenu.addItem(autoPositionItem())
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        return main
    }

    // MARK: Status menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let toggle = item(overlay.isShown ? "Fenster ausblenden" : "Fenster anzeigen", #selector(toggleWindow))
        toggle.keyEquivalent = "d"
        toggle.keyEquivalentModifierMask = [.control, .option, .command]
        menu.addItem(toggle)
        menu.addItem(.separator())

        let smart = item("Smart Dark", #selector(selectSmartDark))
        smart.state = settings.mode == .smartDark ? .on : .off
        menu.addItem(smart)
        let dim = item("Abdunkeln", #selector(selectDim))
        dim.state = settings.mode == .dim ? .on : .off
        menu.addItem(dim)
        let adaptive = item("Dunkle Bereiche beibehalten", #selector(toggleAdaptive))
        adaptive.state = settings.adaptive ? .on : .off
        adaptive.toolTip = "Nur helle Flächen werden umgewandelt – dunkle Oberflächen, Videos und dunkle Bilder bleiben unverändert."
        menu.addItem(adaptive)
        menu.addItem(sliderItem())
        menu.addItem(.separator())

        menu.addItem(autoPositionItem())
        menu.addItem(dockMenuItem())
        menu.addItem(.separator())

        if !CGPreflightScreenCaptureAccess() || overlay.captureFailed {
            menu.addItem(item("⚠︎ Bildschirmaufnahme erlauben …", #selector(openPrivacySettings)))
            menu.addItem(item("App neu starten", #selector(relaunch)))
            menu.addItem(.separator())
        }
        menu.addItem(item("Beenden", #selector(quit), key: "q"))
    }

    private func autoPositionItem() -> NSMenuItem {
        let auto = item("Automatisch auf hellen Bereich ausrichten", #selector(toggleAutoPosition), key: "a")
        auto.keyEquivalentModifierMask = [.control, .option, .command]
        auto.state = overlay?.autoPositionEnabled == true ? .on : .off
        auto.toolTip = "Sucht alle 2 Sekunden die größte helle Fläche (z. B. geteilte Präsentation) und legt das Fenster darüber."
        return auto
    }

    /// Keeps checkmarks in the (static) main menu up to date.
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(toggleAutoPosition) {
            menuItem.state = overlay.autoPositionEnabled ? .on : .off
        }
        return true
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    private func sliderItem() -> NSMenuItem {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 240, height: 44))
        let label = NSTextField(labelWithString: "Helligkeit")
        label.font = .menuFont(ofSize: 0)
        label.textColor = .secondaryLabelColor
        label.frame = NSRect(x: 20, y: 24, width: 200, height: 16)
        view.addSubview(label)
        let slider = NSSlider(value: settings.brightness, minValue: 0.3, maxValue: 1.0,
                              target: self, action: #selector(brightnessChanged(_:)))
        slider.isContinuous = true
        slider.frame = NSRect(x: 18, y: 2, width: 204, height: 22)
        view.addSubview(slider)
        let item = NSMenuItem()
        item.view = view
        return item
    }

    private func dockMenuItem() -> NSMenuItem {
        let parent = NSMenuItem(title: "An Meeting-Fenster andocken", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        if let docked = overlay.dockedWindow {
            parent.title = "Angedockt: \(docked.owner)"
            sub.addItem(item("Andocken lösen", #selector(undock)))
            sub.addItem(.separator())
        }
        let all = WindowDocking.allWindows()
        let meetings = WindowDocking.meetingWindows(in: all)
        if meetings.isEmpty {
            let none = NSMenuItem(title: "Kein Teams-/Meet-/Zoom-Fenster gefunden", action: nil, keyEquivalent: "")
            none.isEnabled = false
            sub.addItem(none)
        }
        for w in meetings { sub.addItem(dockItem(for: w)) }

        let others = all.filter { w in !meetings.contains { $0.id == w.id } }
        if !others.isEmpty {
            sub.addItem(.separator())
            let otherItem = NSMenuItem(title: "Andere Fenster", action: nil, keyEquivalent: "")
            let otherMenu = NSMenu()
            for w in others { otherMenu.addItem(dockItem(for: w)) }
            otherItem.submenu = otherMenu
            sub.addItem(otherItem)
        }
        parent.submenu = sub
        return parent
    }

    private func dockItem(for window: TargetWindow) -> NSMenuItem {
        let title = window.menuTitle.count > 70 ? String(window.menuTitle.prefix(69)) + "…" : window.menuTitle
        let item = item(title, #selector(dockToWindow(_:)))
        item.representedObject = window
        item.state = overlay.dockedWindow?.id == window.id ? .on : .off
        return item
    }

    // MARK: Actions

    @objc private func toggleWindow() { overlay.toggle() }

    @objc private func selectSmartDark() {
        settings.mode = .smartDark
        overlay.retryCapture()
    }

    @objc private func selectDim() {
        settings.mode = .dim
        overlay.applyMode()
    }

    @objc private func toggleAdaptive() {
        settings.adaptive.toggle()
        overlay.applyMode()
    }

    @objc private func brightnessChanged(_ sender: NSSlider) {
        settings.brightness = sender.doubleValue
        overlay.applyMode()
    }

    @objc private func dockToWindow(_ sender: NSMenuItem) {
        guard let target = sender.representedObject as? TargetWindow else { return }
        overlay.dock(to: target)
    }

    @objc private func undock() { overlay.undock() }

    @objc private func toggleAutoPosition() {
        overlay.setAutoPosition(!overlay.autoPositionEnabled)
    }

    @objc private func openPrivacySettings() {
        CGRequestScreenCaptureAccess()
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        task.arguments = ["-c", "sleep 1; /usr/bin/open \"$0\"", Bundle.main.bundlePath]
        try? task.run()
        NSApp.terminate(nil)
    }

    @objc private func quit() { NSApp.terminate(nil) }
}
