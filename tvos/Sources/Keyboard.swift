import AppKit
import SwiftUI

final class KeyboardState: ObservableObject {
    @Published var row = 0
    @Published var col = 0
    @Published var shift = false
}

/// An AZERTY bar over whatever is in front; the remote's arrows pick a key and OK types it into the app behind.
final class AppKeyboard {
    static let shared = AppKeyboard()
    static let rows: [[String]] = [
        ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"],
        ["a", "z", "e", "r", "t", "y", "u", "i", "o", "p"],
        ["q", "s", "d", "f", "g", "h", "j", "k", "l", "m"],
        ["⇧", "w", "x", "c", "v", "b", "n", ".", ",", "⌫"],
        ["é", "è", "à", "ç", "-", "@", "?", "'", "📱", "␣", "↵"],
    ]
    let state = KeyboardState()
    private var panel: NSPanel?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func contains(_ point: NSPoint) -> Bool { isOpen && panel?.frame.contains(point) == true }

    func close() { panel?.orderOut(nil) }

    func open() {
        state.shift = false
        // Key 42, gap 4, inner padding 14, outer padding 10.
        let width: CGFloat = 550, height: CGFloat = 274
        let panel = self.panel ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if self.panel == nil {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            // Above a full-screen app, on whichever Space is showing; it never takes the typing focus.
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = FirstClickHostingView(rootView: KeyboardView(state: state))
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(NSRect(x: screen.frame.midX - width / 2, y: screen.frame.minY + 16, width: width, height: height), display: true)
        panel.orderFrontRegardless()
    }

    func move(dx: Int, dy: Int) {
        state.row = min(max(state.row + dy, 0), Self.rows.count - 1)
        state.col = min(max(state.col + dx, 0), Self.rows[state.row].count - 1)
    }

    func tap(row: Int, col: Int) {
        state.row = row
        state.col = col
        press()
    }

    func press() {
        let key = Self.rows[state.row][state.col]
        let remote = RemoteReceiver.shared
        switch key {
        case "⇧": state.shift.toggle()
        case "⌫": remote.press(51, down: true); remote.press(51, down: false)
        case "↵": remote.press(36, down: true); remote.press(36, down: false); close()
        case "␣": remote.type(32)
        case "📱": PhoneBridge.shared.notify(); close()
        default:
            let text = state.shift ? key.uppercased() : key
            state.shift = false
            if let unit = text.utf16.first { remote.type(unit) }
        }
    }
}

struct KeyboardView: View {
    @ObservedObject var state: KeyboardState

    var body: some View {
        VStack(spacing: 4) {
            ForEach(0..<AppKeyboard.rows.count, id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(0..<AppKeyboard.rows[r].count, id: \.self) { c in
                        key(r, c)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 22).fill(Color.black.opacity(0.96)))
        .padding(10)
    }

    private func key(_ r: Int, _ c: Int) -> some View {
        let label = AppKeyboard.rows[r][c]
        let picked = r == state.row && c == state.col
        let shown = label.count == 1 && state.shift && label.uppercased() != label ? label.uppercased() : label
        return Text(shown)
            .font(.system(size: 19, weight: .medium))
            .foregroundColor(picked ? .black : .white)
            .frame(width: 42, height: 42)
            .background(RoundedRectangle(cornerRadius: 9).fill(picked ? Color.white : Color.white.opacity(label == "⇧" && state.shift ? 0.35 : 0.12)))
            .scaleEffect(picked ? 1.08 : 1)
            .contentShape(Rectangle())
            .onTapGesture { AppKeyboard.shared.tap(row: r, col: c) }
    }
}

/// Takes the click even though the panel never becomes the active window.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
