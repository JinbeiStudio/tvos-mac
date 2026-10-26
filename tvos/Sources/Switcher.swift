import AppKit
import SwiftUI

/// Your row of apps as an overlay over whatever is in front, Apple TV's glass dock at the foot of the screen;
/// the remote's arrows pick one and OK opens it full screen. The row is edited from the menu bar.
final class AppSwitcher {
    static let shared = AppSwitcher()
    private var panel: NSPanel?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        let model = HomeModel.shared
        guard !model.shelf.isEmpty else { return }
        // Starts on the app after the one in front, so green then OK flips between two.
        let front = NSWorkspace.shared.frontmostApplication?.bundleURL?.path
        let at = model.shelf.firstIndex { $0.url.path == front }
        model.focus = at.map { ($0 + 1) % model.shelf.count } ?? 0
        show(count: model.shelf.count)
    }

    func move(_ step: Int) {
        let model = HomeModel.shared
        model.focus = max(0, min(model.shelf.count - 1, model.focus + step))
    }

    func confirm() {
        let model = HomeModel.shared
        guard model.focus < model.shelf.count else { return close() }
        model.launch(model.shelf[model.focus])
    }

    func close() { panel?.orderOut(nil) }

    private func show(count: Int) {
        let panel = self.panel ?? KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if self.panel == nil {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Above a full-screen app, on whichever Space is showing.
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = NSHostingView(rootView: DockOverlay(model: HomeModel.shared))
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        // Drawn on the dock's 1920-wide scale, then shrunk to the screen, as the TV's own home is.
        let scale = screen.frame.width / 1920
        let width = min(CGFloat(count) * 240 + 68 + 220, 1920) * scale
        let height = 300 * scale
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.minY + 60 * scale, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        // Takes the Mac keyboard's arrows, without leaving the app in front.
        panel.makeKey()
    }
}

/// The dock, scaled from its 1920-wide drawing to the panel.
struct DockOverlay: View {
    @ObservedObject var model: HomeModel

    var body: some View {
        GeometryReader { geo in
            let scale = geo.size.height / 300
            Dock(model: model)
                .frame(width: geo.size.width / scale, height: 300)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
        }
    }
}
