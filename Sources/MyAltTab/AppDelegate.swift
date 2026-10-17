import AppKit
import ApplicationServices
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem!
    private var loginMenuItem: NSMenuItem!
    private var settingsWindow: NSWindow?
    private let switcher = SwitcherController()
    private var monitor: HotkeyMonitor!
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [Settings.includeMinimized: true, Settings.showPreviews: true,
                                                  Settings.previewIconSize: SwitcherLayout.badgeRange.upperBound])
        setUpStatusItem()

        monitor = HotkeyMonitor { [weak self] event in self?.handle(event) }
        switcher.onClick = { [weak self] index in
            self?.monitor.endSession()
            self?.switcher.select(index)
            self?.switcher.commit()
        }
        startWhenTrusted()

        if UserDefaults.standard.bool(forKey: Settings.showPreviews) && !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func handle(_ event: HotkeyMonitor.Event) {
        switch event {
        case .start(let reverse):
            // Nothing to switch to: stop swallowing keys right away.
            if !switcher.start(reverse: reverse) { monitor.endSession() }
        case .next: switcher.move(by: 1)
        case .previous: switcher.move(by: -1)
        case .up: switcher.moveRow(by: -1)
        case .down: switcher.moveRow(by: 1)
        case .cancel: switcher.cancel()
        case .commit: switcher.commit()
        }
    }

    private func startWhenTrusted() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options), monitor.start() { return }

        // Wait for the user to grant Accessibility access, then start without needing a relaunch.
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted(), self.monitor.start() else { return }
            timer.invalidate()
            self.permissionTimer = nil
        }
    }

    // MARK: - Menu bar

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "rectangle.on.rectangle", accessibilityDescription: "MyAltTab")

        let menu = NSMenu()
        menu.delegate = self
        loginMenuItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        loginMenuItem.target = self
        menu.addItem(loginMenuItem)

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit MyAltTab", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        switch LoginItem.status {
        case .enabled: loginMenuItem.state = .on
        case .requiresApproval: loginMenuItem.state = .mixed // registered, waiting for approval in System Settings
        default: loginMenuItem.state = .off
        }
    }

    @objc private func toggleLaunchAtLogin() {
        do {
            try LoginItem.setEnabled(!LoginItem.isRegistered)
        } catch {
            NSApp.activate(ignoringOtherApps: true)
            NSAlert(error: error).runModal()
        }
    }

    @objc private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView(model: SettingsModel())))
            window.title = "MyAltTab Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            settingsWindow = window
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    /// Drop the window so its SwiftUI view (and refresh timer) is torn down while closed.
    func windowWillClose(_ notification: Notification) {
        if (notification.object as? NSWindow) === settingsWindow { settingsWindow = nil }
    }
}
