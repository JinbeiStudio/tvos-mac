import AppKit
import ApplicationServices

/// After a click from the remote, shows the on-screen keyboard when the app in front has a text field focused, and hides it otherwise.
enum TextFocus {
    private static let roles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]

    /// Called right after the remote's click, while the pointer is still where it clicked.
    static func clicked() {
        // A click on the keyboard itself leaves the field focused; it must not reopen what a key just closed.
        if AppKeyboard.shared.contains(NSEvent.mouseLocation) { return }
        // The app needs a moment to move its focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard AXIsProcessTrusted() else { return }
            if focusedIsText() {
                if !AppKeyboard.shared.isOpen { AppKeyboard.shared.open() }
            } else if AppKeyboard.shared.isOpen {
                AppKeyboard.shared.close()
            }
        }
    }

    private static func focusedIsText() -> Bool {
        var elements = [AXUIElementCreateSystemWide()]
        if let app = NSWorkspace.shared.frontmostApplication {
            let element = AXUIElementCreateApplication(app.processIdentifier)
            // Browser engines only build their page's accessibility tree once asked.
            AXUIElementSetAttributeValue(element, "AXManualAccessibility" as CFString, kCFBooleanTrue)
            elements.append(element)
        }
        for source in elements {
            AXUIElementSetMessagingTimeout(source, 0.5)
            var focused: CFTypeRef?
            guard AXUIElementCopyAttributeValue(source, kAXFocusedUIElementAttribute as CFString, &focused) == .success,
                  let element = focused else { continue }
            let target = element as! AXUIElement
            if let role = text(target, kAXRoleAttribute), roles.contains(role) { return true }
            if text(target, kAXSubroleAttribute) == "AXSearchField" { return true }
        }
        return false
    }

    private static func text(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value as? String
    }
}
