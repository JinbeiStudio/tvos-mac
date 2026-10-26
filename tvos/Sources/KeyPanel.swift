import AppKit

/// An overlay that can take the Mac keyboard while the app underneath stays in front, as Spotlight's does.
final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}
