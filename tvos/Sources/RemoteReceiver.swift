import AppKit
import ApplicationServices
import Network

/// The Mac end of MagicRemoteService: the LG Magic Remote's TV app sends its pointer, clicks, wheel and keys here as small binary
/// WebSocket messages (port 41230), and they come out as mouse and keyboard events on this Mac.
final class RemoteReceiver: ObservableObject {
    static let shared = RemoteReceiver()
    /// What arrived last, shown for a moment so the remote can be tested by eye.
    @Published var note = ""

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var noteTimer: Timer?
    private var lastLogged: [UInt8: Date] = [:]
    private var leftDown = false
    private var rightDown = false

    /// Every step of a connection goes to a log file, for working out why a TV cannot connect.
    private func log(_ text: String) {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/tvOS-remote.log")
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(text)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            handle.closeFile()
        } else {
            try? line.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    func start() {
        guard listener == nil else { return }
        log("listening on 41230")
        let socket = NWProtocolWebSocket.Options()
        socket.autoReplyPing = true
        let params = NWParameters.tcp
        params.defaultProtocolStack.applicationProtocols.insert(socket, at: 0)
        guard let port = NWEndpoint.Port(rawValue: 41230), let found = try? NWListener(using: params, on: port) else {
            show("Remote: port 41230 is taken")
            return
        }
        found.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        found.start(queue: .main)
        listener = found
    }

    // MARK: - Connections

    /// Only the home network may drive this Mac: the protocol has no password.
    private func isLocal(_ endpoint: NWEndpoint) -> Bool {
        guard case let .hostPort(host, _) = endpoint else { return false }
        let text = "\(host)".replacingOccurrences(of: "::ffff:", with: "")
        if text.hasPrefix("192.168.") || text.hasPrefix("10.") || text.hasPrefix("127.") { return true }
        if text.hasPrefix("172."), let second = text.split(separator: ".").dropFirst().first, let n = Int(second) { return (16...31).contains(n) }
        return text.lowercased().hasPrefix("fe80") || text == "::1"
    }

    private var ready = Set<ObjectIdentifier>()

    private func accept(_ connection: NWConnection) {
        log("connection attempt from \(connection.endpoint)")
        guard isLocal(connection.endpoint) else {
            log("refused: not a local address")
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        connection.stateUpdateHandler = { [weak self] state in
            self?.log("connection \(state)")
            switch state {
            case .ready:
                self?.ready.insert(id)
                self?.show("Remote connected")
            case .failed, .cancelled:
                self?.connections[id] = nil
                self?.releaseButtons()
                // Only a connection that worked counts; refused or half-open attempts say nothing.
                if self?.ready.remove(id) != nil, self?.ready.isEmpty == true { self?.show("Remote disconnected") }
            default: break
            }
        }
        connection.start(queue: .main)
        listen(connection)
    }

    private func listen(_ connection: NWConnection) {
        connection.receiveMessage { [weak self] data, context, _, error in
            guard let self = self else { return }
            if let data = data, !data.isEmpty,
               let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata,
               meta.opcode == .binary {
                self.handle([UInt8](data))
            }
            if error == nil { self.listen(connection) } else { connection.cancel() }
        }
    }

    private func show(_ text: String) {
        note = text
        noteTimer?.invalidate()
        noteTimer = Timer.scheduledTimer(withTimeInterval: 2.5, repeats: false) { [weak self] _ in self?.note = "" }
    }

    // MARK: - Messages

    private func int16(_ b: [UInt8], _ at: Int) -> Int { Int(Int16(bitPattern: UInt16(b[at]) | UInt16(b[at + 1]) << 8)) }
    private func uint16(_ b: [UInt8], _ at: Int) -> Int { Int(UInt16(b[at]) | UInt16(b[at + 1]) << 8) }

    private func handle(_ b: [UInt8]) {
        // Pointer moves come by the hundred, so each kind of message is noted once a second.
        if b[0] != 4, Date().timeIntervalSince(lastLogged[b[0]] ?? .distantPast) > 1 {
            lastLogged[b[0]] = Date()
            log("message type \(b[0]) length \(b.count)")
        }
        if b[0] == 4, b.count >= 4 { log("key \(uint16(b, 1)) down=\(b[3] & 1) accessibility=\(AXIsProcessTrusted())") }
        guard AXIsProcessTrusted() else {
            show("Remote: allow tvOS in Accessibility settings")
            return
        }
        switch b[0] {
        case 0x00 where b.count >= 5: moveBy(dx: int16(b, 1), dy: int16(b, 3))
        case 0x01 where b.count >= 5: moveTo(x: uint16(b, 1), y: uint16(b, 3))
        case 0x02 where b.count >= 3: scroll(int16(b, 1))
        case 0x04 where b.count >= 4: key(code: uint16(b, 1), down: b[3] & 1 == 1)
        case 0x05 where b.count >= 3: type(UInt16(uint16(b, 1)))
        default: break // cursor visibility and shutdown mean nothing here
        }
    }

    // MARK: - Mouse

    private var bounds: CGRect { CGDisplayBounds(CGMainDisplayID()) }
    private var position: CGPoint { CGEvent(source: nil)?.location ?? .zero }

    private func moveBy(dx: Int, dy: Int) {
        move(to: CGPoint(x: position.x + CGFloat(dx), y: position.y + CGFloat(dy)))
    }

    /// The TV reports a place on its 1920 by 1080 picture.
    private func moveTo(x: Int, y: Int) {
        let area = bounds
        move(to: CGPoint(x: area.minX + area.width * CGFloat(x) / 1920, y: area.minY + area.height * CGFloat(y) / 1080))
    }

    private func move(to point: CGPoint) {
        let area = bounds
        let at = CGPoint(x: min(max(point.x, area.minX), area.maxX - 1), y: min(max(point.y, area.minY), area.maxY - 1))
        let kind: CGEventType = leftDown ? .leftMouseDragged : (rightDown ? .rightMouseDragged : .mouseMoved)
        CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: at, mouseButton: rightDown ? .right : .left)?.post(tap: .cghidEventTap)
    }

    private func click(_ button: CGMouseButton, down: Bool) {
        if button == .left { leftDown = down } else { rightDown = down }
        let kind: CGEventType = button == .left ? (down ? .leftMouseDown : .leftMouseUp) : (down ? .rightMouseDown : .rightMouseUp)
        let event = CGEvent(mouseEventSource: nil, mouseType: kind, mouseCursorPosition: position, mouseButton: button)
        event?.setIntegerValueField(.mouseEventClickState, value: 1)
        event?.post(tap: .cghidEventTap)
        // Only the remote's clicks look for a text field; the Mac's own mouse never opens the keyboard.
        if button == .left && !down { DispatchQueue.main.async { TextFocus.clicked() } }
    }

    private func releaseButtons() {
        if leftDown { click(.left, down: false) }
        if rightDown { click(.right, down: false) }
    }

    private func scroll(_ amount: Int) {
        CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 1, wheel1: Int32(-amount * 2), wheel2: 0, wheel3: 0)?.post(tap: .cghidEventTap)
    }

    // MARK: - Keys

    /// A Mac virtual key, with its modifiers.
    func press(_ virtualKey: CGKeyCode, down: Bool, flags: CGEventFlags = []) {
        let event = CGEvent(keyboardEventSource: nil, virtualKey: virtualKey, keyDown: down)
        event?.flags = flags
        event?.post(tap: .cghidEventTap)
    }

    /// A character typed whatever the keyboard layout.
    func type(_ unit: UInt16) {
        var character = unit
        for down in [true, false] {
            let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
            event?.keyboardSetUnicodeString(stringLength: 1, unicodeString: &character)
            event?.post(tap: .cghidEventTap)
        }
    }

    /// Whole text typed into the app in front; a line break presses Return.
    func typeText(_ text: String) {
        for (index, line) in text.components(separatedBy: "\n").enumerated() {
            if index > 0 { press(36, down: true); press(36, down: false) }
            var units = Array(line.utf16)
            while !units.isEmpty {
                let chunk = Array(units.prefix(16))
                units.removeFirst(chunk.count)
                for down in [true, false] {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: 0, keyDown: down)
                    event?.keyboardSetUnicodeString(stringLength: chunk.count, unicodeString: chunk)
                    event?.post(tap: .cghidEventTap)
                }
            }
        }
    }

    /// The Magic Remote's key codes, as MagicRemoteService's own defaults use them.
    private func key(code: Int, down: Bool) {
        // While the app switcher is open it takes the arrows, OK and back.
        // Control Center takes the arrows, OK and back while it shows.
        if ControlCenter.shared.isOpen, [0x25, 0x26, 0x27, 0x28, 0x0D, 0x1CD, 0x193, 0x196].contains(code) {
            if down {
                DispatchQueue.main.async {
                    let center = ControlCenter.shared
                    switch code {
                    case 0x25: center.move(-1, 0)
                    case 0x27: center.move(1, 0)
                    case 0x26: center.move(0, -1)
                    case 0x28: center.move(0, 1)
                    case 0x0D: center.press()
                    // Blue again closes it, as it opened it.
                    case 0x196: center.close()
                    default: center.back()
                    }
                }
            }
            return
        }
        if AppSwitcher.shared.isOpen {
            if down {
                DispatchQueue.main.async {
                    switch code {
                    case 0x25: AppSwitcher.shared.move(-1)
                    case 0x27: AppSwitcher.shared.move(1)
                    case 0x0D: AppSwitcher.shared.confirm()
                    case 0x1CD, 0x194, 0x193: AppSwitcher.shared.close()
                    default: break
                    }
                }
            }
            return
        }
        // The keyboard takes the arrows and OK; the number keys and delete still go through to type normally.
        if AppKeyboard.shared.isOpen, code == 0x25 || code == 0x26 || code == 0x27 || code == 0x28 || code == 0x0D || code == 0x1CD || code == 0x195 {
            if down {
                DispatchQueue.main.async {
                    switch code {
                    case 0x25: AppKeyboard.shared.move(dx: -1, dy: 0)
                    case 0x27: AppKeyboard.shared.move(dx: 1, dy: 0)
                    case 0x26: AppKeyboard.shared.move(dx: 0, dy: -1)
                    case 0x28: AppKeyboard.shared.move(dx: 0, dy: 1)
                    case 0x0D: AppKeyboard.shared.press()
                    default: AppKeyboard.shared.close()
                    }
                }
            }
            return
        }
        switch code {
        case 0x01: click(.left, down: down)
        case 0x02: click(.right, down: down)
        case 0x08: press(51, down: down)
        case 0x0D: press(36, down: down)
        case 0x25: press(123, down: down)
        case 0x26: press(126, down: down)
        case 0x27: press(124, down: down)
        case 0x28: press(125, down: down)
        case 0x30...0x39: if down { type(UInt16(code)) }
        case 0x1CD: press(53, down: down)
        case 0x193:
            // Red goes to AIOStreams' home.
            if down { DispatchQueue.main.async { Launcher.home() } }
        case 0x194:
            // Green opens the app switcher; held, it opens YouTube's extended settings.
            hold(code, down: down, short: { AppSwitcher.shared.toggle() },
                 long: { Launcher.toYouTube(["code": 404]) })
        case 0x196:
            // Blue opens Control Center, in one press.
            if down { DispatchQueue.main.async { ControlCenter.shared.toggle() } }
        case 0x195:
            // Yellow shows the keyboard; held, it fills the screen in YouTube.
            hold(code, down: down, short: { AppKeyboard.shared.toggle() },
                 long: { Launcher.toYouTube(["fill": true]) })
        case 0x21: press(8, down: down, flags: .maskCommand)
        case 0x22: press(9, down: down, flags: .maskCommand)
        default: break
        }
    }

    private var holds: [Int: DispatchWorkItem] = [:]

    /// Runs `short` on release, or `long` once the button has been held for half a second.
    private func hold(_ code: Int, down: Bool, short: @escaping () -> Void, long: @escaping () -> Void) {
        DispatchQueue.main.async {
            if down {
                guard self.holds[code] == nil else { return }
                let item = DispatchWorkItem { [weak self] in
                    self?.holds[code] = nil
                    long()
                    self?.fired.insert(code)
                }
                self.holds[code] = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
            } else if let item = self.holds.removeValue(forKey: code) {
                item.cancel()
                short()
            } else {
                self.fired.remove(code)
            }
        }
    }

    private var fired = Set<Int>()
}
