import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {

    private static let panelStyleKey = "panel.visual.style"
    private static let startupPromptShownKey = "startup.prompt.shown"

    private var statusItem: NSStatusItem!
    private var historyStore: ClipboardHistoryStore!
    private var clipboardMonitor: ClipboardMonitor!
    private var historyPanel: HistoryPanel!
    private var hotKeyManager: HotKeyManager!
    private var previousApp: NSRunningApplication?
    private var blurryStyleItem: NSMenuItem?
    private var liquidStyleItem: NSMenuItem?
    private var launchAtLoginMenuItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityPermission()

        historyStore = ClipboardHistoryStore()
        let initialStyle = preferredPanelStyle()

        historyPanel = HistoryPanel(store: historyStore, visualStyle: initialStyle) { [weak self] item in
            self?.paste(item: item)
        }

        clipboardMonitor = ClipboardMonitor(store: historyStore)
        clipboardMonitor.start()

        hotKeyManager = HotKeyManager { [weak self] in
            self?.togglePanel()
        }
        hotKeyManager.start()

        setupStatusItem()
        maybePromptLaunchAtLoginOnFirstRun()
    }

    // MARK: - Status Bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "Clipboard History")
            button.action = #selector(togglePanel)
            button.target = self
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show History  ⌃⌘V", action: #selector(togglePanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let appearanceMenuItem = NSMenuItem(title: "Appearance", action: nil, keyEquivalent: "")
        let appearanceMenu = NSMenu(title: "Appearance")

        let blurry = NSMenuItem(title: "Blurry", action: #selector(selectAppearance(_:)), keyEquivalent: "")
        blurry.tag = 0
        blurry.target = self
        appearanceMenu.addItem(blurry)

        let liquid = NSMenuItem(title: "Liquid Glass", action: #selector(selectAppearance(_:)), keyEquivalent: "")
        liquid.tag = 1
        liquid.target = self
        appearanceMenu.addItem(liquid)

        blurryStyleItem = blurry
        liquidStyleItem = liquid
        appearanceMenuItem.submenu = appearanceMenu
        menu.addItem(appearanceMenuItem)

        updateAppearanceMenuState()
        menu.addItem(NSMenuItem.separator())

        let launchAtLoginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        launchAtLoginMenuItem = launchAtLoginItem
        menu.addItem(launchAtLoginItem)
        updateLaunchAtLoginMenuState()

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear History", action: #selector(clearHistory), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc func togglePanel() {
        if historyPanel.isVisible {
            historyPanel.dismiss()
        } else {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate(ignoringOtherApps: true)
            historyPanel.showNearMouse()
        }
    }

    @objc func clearHistory() {
        historyStore.clear()
    }

    @objc private func toggleLaunchAtLogin() {
        guard LaunchAtLoginManager.shared.canConfigureForCurrentRun() else { return }
        let enable = !LaunchAtLoginManager.shared.isEnabled()
        LaunchAtLoginManager.shared.setEnabled(enable)
        updateLaunchAtLoginMenuState()
    }

    @objc private func selectAppearance(_ sender: NSMenuItem) {
        let style: PanelVisualStyle = sender.tag == 1 ? .liquidGlass : .blurry
        savePreferredPanelStyle(style)
        historyPanel.setVisualStyle(style)
        updateAppearanceMenuState()
    }

    private func preferredPanelStyle() -> PanelVisualStyle {
        let raw = UserDefaults.standard.string(forKey: Self.panelStyleKey)
        return PanelVisualStyle(rawValue: raw ?? "") ?? .blurry
    }

    private func savePreferredPanelStyle(_ style: PanelVisualStyle) {
        UserDefaults.standard.set(style.rawValue, forKey: Self.panelStyleKey)
    }

    private func updateAppearanceMenuState() {
        let style = preferredPanelStyle()
        blurryStyleItem?.state = style == .blurry ? .on : .off
        liquidStyleItem?.state = style == .liquidGlass ? .on : .off
    }

    private func updateLaunchAtLoginMenuState() {
        let canConfigure = LaunchAtLoginManager.shared.canConfigureForCurrentRun()
        launchAtLoginMenuItem?.isEnabled = canConfigure
        launchAtLoginMenuItem?.state = LaunchAtLoginManager.shared.isEnabled() ? .on : .off
    }

    private func maybePromptLaunchAtLoginOnFirstRun() {
        guard LaunchAtLoginManager.shared.canConfigureForCurrentRun() else { return }
        guard !UserDefaults.standard.bool(forKey: Self.startupPromptShownKey) else { return }

        UserDefaults.standard.set(true, forKey: Self.startupPromptShownKey)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { [weak self] in
            let alert = NSAlert()
            alert.messageText = "Start Clipboardy at Login?"
            alert.informativeText = "Clipboardy can start automatically when you sign in, so clipboard history is always ready."
            alert.alertStyle = .informational
            alert.addButton(withTitle: "Enable")
            alert.addButton(withTitle: "Not Now")

            if alert.runModal() == .alertFirstButtonReturn {
                LaunchAtLoginManager.shared.setEnabled(true)
                self?.updateLaunchAtLoginMenuState()
            }
        }
    }

    private func paste(item: ClipboardItem) {
        historyStore.copyToClipboard(item: item)
        historyPanel.dismiss()

        // Re-activate the app that was previously focused, then simulate ⌘V
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in
            self?.previousApp?.activate(options: .activateIgnoringOtherApps)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Self.simulatePaste()
            }
        }
    }

    private static func simulatePaste() {
        let src = CGEventSource(stateID: .hidSystemState)
        let vKeyCode: CGKeyCode = 9
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: vKeyCode, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - Permissions

    private func requestAccessibilityPermission() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options: CFDictionary = [key: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                let alert = NSAlert()
                alert.messageText = "Accessibility Permission Required"
                alert.informativeText = "Clipboardy needs Accessibility access to register the global hotkey (⌃⌘V) and to simulate paste.\n\nPlease enable it in System Settings → Privacy & Security → Accessibility, then restart the app."
                alert.alertStyle = .warning
                alert.addButton(withTitle: "Open System Settings")
                alert.addButton(withTitle: "Later")
                if alert.runModal() == .alertFirstButtonReturn {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
            }
        }
    }
}
