import AppKit
import SwiftUI

/// In the menu bar: opens AIOStreams, and adds the remote, the coloured buttons' overlays (your row of apps,
/// Control Center, the keyboard) and the iPhone keyboard over every app, with the same on the Mac's keyboard.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var status: NSStatusItem?
    private var editor: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        RemoteReceiver.shared.start()
        PhoneBridge.shared.start()
        installStatusItem()
        Launcher.brandAIOStreams()
        Launcher.openAIOStreams()
        // The coloured buttons from any app, with Control+Option and a letter.
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in _ = self?.shortcut(event) }
        // In an overlay or the editor, the Mac keyboard moves and picks as the remote does.
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self else { return event }
            if self.shortcut(event) || self.overlayKey(event) { return nil }
            if NSApp.keyWindow === self.editor, HomeModel.shared.handleEditor(event) { return nil }
            return event
        }
    }

    /// Opening tvOS again (Launchpad, Finder) brings AIOStreams back.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Launcher.openAIOStreams()
        return false
    }

    /// Control+Option with H (home), A (apps), K (keyboard) or C (Control Center), as the remote's red, green,
    /// yellow and blue. Read by the letter typed, not the key's place, so AZERTY's A is A.
    private func shortcut(_ event: NSEvent) -> Bool {
        if event.keyCode == 53, AppKeyboard.shared.isOpen { AppKeyboard.shared.close(); return true }
        let mods = event.modifierFlags.intersection([.control, .option, .command, .shift])
        guard mods == [.control, .option] else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "h": Launcher.home()
        case "a": AppSwitcher.shared.toggle()
        case "k": AppKeyboard.shared.toggle()
        case "c": ControlCenter.shared.toggle()
        default: return false
        }
        return true
    }

    private func overlayKey(_ event: NSEvent) -> Bool {
        let code = event.keyCode
        if AppSwitcher.shared.isOpen {
            switch code {
            case 123: AppSwitcher.shared.move(-1)
            case 124: AppSwitcher.shared.move(1)
            case 36, 76, 49: AppSwitcher.shared.confirm()
            case 53, 51: AppSwitcher.shared.close()
            default: return false
            }
            return true
        }
        if ControlCenter.shared.isOpen {
            let center = ControlCenter.shared
            switch code {
            case 123: center.move(-1, 0)
            case 124: center.move(1, 0)
            case 126: center.move(0, -1)
            case 125: center.move(0, 1)
            case 36, 76, 49: center.press()
            case 53, 51: center.back()
            default: return false
            }
            return true
        }
        return false
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "appletv", accessibilityDescription: "tvOS")
        let menu = NSMenu()
        let entries: [(String, Selector, String)] = [
            ("Home", #selector(openHome), "h"),
            ("Apps", #selector(openApps), "a"),
            ("Keyboard", #selector(openKeyboard), "k"),
            ("Control Center", #selector(openControlCenter), "c"),
            ("YouTube", #selector(openYouTube), ""),
        ]
        for (title, action, key) in entries {
            let entry = NSMenuItem(title: title, action: action, keyEquivalent: key)
            entry.keyEquivalentModifierMask = [.control, .option]
            entry.target = self
            menu.addItem(entry)
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Edit Apps…", action: #selector(editApps), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit tvOS", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.menu = menu
        status = item
    }

    @objc private func openHome() { Launcher.home() }
    @objc private func openYouTube() { Launcher.openYouTube() }
    @objc private func openApps() { AppSwitcher.shared.open() }
    @objc private func openControlCenter() { ControlCenter.shared.open() }
    @objc private func openKeyboard() { AppKeyboard.shared.open() }

    /// Every app on the Mac, to pick and order the row's.
    @objc private func editApps() {
        if editor == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 820),
                styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.title = "Edit Apps"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: Editor(model: HomeModel.shared))
            window.center()
            editor = window
        }
        HomeModel.shared.editRow = 0
        NSApp.activate(ignoringOtherApps: true)
        editor?.makeKeyAndOrderFront(nil)
    }
}
