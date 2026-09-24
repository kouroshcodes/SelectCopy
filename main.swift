import Cocoa
import ApplicationServices
import ServiceManagement

// SelectCopy: copies selected text to the clipboard as soon as you finish selecting it.
// Detects a selection when the left mouse button is released after a drag or a double/triple click,
// reads the text through the Accessibility API, and falls back to a synthetic Cmd+C for apps
// (Chrome, Electron, …) that don't expose the selection.

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var enabledItem: NSMenuItem!
    private var loginItem: NSMenuItem!
    private var monitors: [Any] = []
    private var downPoint = NSPoint.zero
    private var enabled = UserDefaults.standard.object(forKey: "enabled") as? Bool ?? true
    private var toastEnabled = UserDefaults.standard.object(forKey: "toast") as? Bool ?? true
    private var toastItem: NSMenuItem!
    private var permissionItem: NSMenuItem!
    private var flashGeneration = 0
    private let noFallbackBundles: Set<String> = [
        "com.apple.finder",        // Cmd+C there copies files, not text
        "com.github.wez.wezterm",  // copies on select itself; an injected Cmd+C races it and can clobber the clipboard
    ]

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        permissionItem = NSMenuItem(title: "⚠︎ Grant Accessibility access…", action: #selector(openAccessibilitySettings), keyEquivalent: "")
        permissionItem.target = self
        menu.addItem(permissionItem)
        enabledItem = NSMenuItem(title: "Copy on Select", action: #selector(toggleEnabled), keyEquivalent: "")
        enabledItem.target = self
        menu.addItem(enabledItem)
        toastItem = NSMenuItem(title: "Flash ✅ on Copy", action: #selector(toggleToast), keyEquivalent: "")
        toastItem.target = self
        menu.addItem(toastItem)
        loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit SelectCopy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
        refreshUI()

        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            installMonitors()
        } else {
            // Wait until the user grants Accessibility access in System Settings.
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.installMonitors()
                    self?.refreshUI()
                }
            }
        }
    }

    private func installMonitors() {
        guard monitors.isEmpty else { return }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            self?.downPoint = NSEvent.mouseLocation
        }) { monitors.append(m) }
        if let m = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp, handler: { [weak self] event in
            self?.mouseUp(event)
        }) { monitors.append(m) }
    }

    private func mouseUp(_ event: NSEvent) {
        guard enabled else { return }
        let p = NSEvent.mouseLocation
        let dragged = hypot(p.x - downPoint.x, p.y - downPoint.y) > 4
        guard dragged || event.clickCount >= 2 else { return }
        // Let the app finish updating its selection first.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) { [weak self] in self?.copySelection() }
    }

    private func copySelection() {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }

        if let text = selectedTextViaAX(pid: app.processIdentifier) {
            if !text.isEmpty { write(text); showToast() }
            return
        }
        if let id = app.bundleIdentifier, noFallbackBundles.contains(id) { return }
        let before = NSPasteboard.general.changeCount
        sendCmdC()
        // Only confirm if the app actually put something on the clipboard.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            if NSPasteboard.general.changeCount != before { self?.showToast() }
        }
    }

    /// Briefly swaps the menu bar icon for a green checkmark.
    private func showToast() {
        guard toastEnabled else { return }
        flashGeneration += 1
        let gen = flashGeneration
        let config = NSImage.SymbolConfiguration(paletteColors: [.white, .systemGreen])
        let check = NSImage(systemSymbolName: "checkmark.square.fill", accessibilityDescription: "Copied")?
            .withSymbolConfiguration(config)
        check?.isTemplate = false
        statusItem.button?.image = check
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self, gen == self.flashGeneration else { return }
            self.refreshUI()
        }
    }

    /// nil = app doesn't expose the selection via Accessibility; "" = it does, and nothing is selected.
    private func selectedTextViaAX(pid: pid_t) -> String? {
        let appEl = AXUIElementCreateApplication(pid)
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appEl, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
              let focusedEl = focused, CFGetTypeID(focusedEl) == AXUIElementGetTypeID() else { return nil }
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(focusedEl as! AXUIElement, kAXSelectedTextAttribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        // Chrome-style web areas can report "" even with a visible selection; let the fallback try.
        return text.isEmpty ? nil : text
    }

    private func write(_ text: String) {
        let pb = NSPasteboard.general
        if pb.string(forType: .string) == text { return }
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func sendCmdC() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let keyC: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: keyC, keyDown: false)
        down?.flags = .maskCommand
        up?.flags = .maskCommand
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    @objc private func toggleEnabled() {
        enabled.toggle()
        UserDefaults.standard.set(enabled, forKey: "enabled")
        refreshUI()
    }

    @objc private func openAccessibilitySettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }

    @objc private func toggleToast() {
        toastEnabled.toggle()
        UserDefaults.standard.set(toastEnabled, forKey: "toast")
        refreshUI()
    }

    @objc private func toggleLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
        refreshUI()
    }

    private func refreshUI() {
        let trusted = AXIsProcessTrusted()
        permissionItem.isHidden = trusted
        enabledItem.state = enabled ? .on : .off
        toastItem.state = toastEnabled ? .on : .off
        loginItem.state = SMAppService.mainApp.status == .enabled ? .on : .off
        let symbol = !trusted ? "exclamationmark.triangle" : enabled ? "doc.on.clipboard.fill" : "doc.on.clipboard"
        statusItem.button?.image = NSImage(systemSymbolName: symbol,
                                           accessibilityDescription: "SelectCopy")
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
