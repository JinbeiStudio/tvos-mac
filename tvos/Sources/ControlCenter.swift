import AppKit
import CoreAudio
import SwiftUI

/// tvOS's Control Center over whatever is in front, with each tile doing the Mac's version of it.
final class ControlCenter: ObservableObject {
    static let shared = ControlCenter()

    enum Tile: Int, CaseIterable { case sleep, network, screen, audio, timer, search, apps, keyboard, settings }

    @Published var focus: Tile = .sleep
    @Published var outputs: [(id: AudioDeviceID, name: String)] = []
    /// The output list is open in place of the tiles; its focused row.
    @Published var outputFocus: Int? = nil
    @Published var timerEnd: Date? = nil
    @Published var now = Date()
    private var panel: NSPanel?
    private var ticker: Timer?
    private var sleepTimer: Timer?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : open() }

    func open() {
        focus = .sleep
        outputFocus = nil
        now = Date()
        let width: CGFloat = 470, height: CGFloat = 454
        let panel = self.panel ?? KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        if self.panel == nil {
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            panel.contentView = FirstClickHostingView(rootView: ControlCenterView(center: self))
            self.panel = panel
        }
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main ?? NSScreen.screens[0]
        panel.setFrame(NSRect(x: screen.frame.maxX - width - 40, y: screen.frame.maxY - height - 50, width: width, height: height), display: true)
        panel.orderFrontRegardless()
        // Takes the Mac keyboard's arrows, without leaving the app in front.
        panel.makeKey()
        if let path = ProcessInfo.processInfo.environment["TVHOME_CONTROL"], path.hasSuffix(".png") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                guard let view = panel.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
        }
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in self?.now = Date() }
        // A click anywhere else, in this app or another, closes it, as tvOS does.
        let outside: (NSEvent) -> Void = { [weak self] _ in
            guard let self = self, let frame = self.panel?.frame, !frame.contains(NSEvent.mouseLocation) else { return }
            self.close()
        }
        clickMonitors = [
            NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown], handler: outside),
            NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { outside($0); return $0 },
        ].compactMap { $0 }
    }

    private var clickMonitors: [Any] = []

    func close() {
        panel?.orderOut(nil)
        ticker?.invalidate()
        clickMonitors.forEach(NSEvent.removeMonitor)
        clickMonitors = []
    }

    // MARK: - Remote

    /// Where each arrow goes from each tile, following the tvOS layout.
    func move(_ dx: Int, _ dy: Int) {
        if let row = outputFocus {
            outputFocus = min(max(row + dy, 0), max(outputs.count - 1, 0))
            return
        }
        let grid: [Tile: (left: Tile?, right: Tile?, up: Tile?, down: Tile?)] = [
            .sleep: (nil, .network, nil, .audio),
            .network: (.sleep, nil, nil, .screen),
            .screen: (.sleep, nil, .network, .timer),
            .audio: (nil, .timer, .sleep, .search),
            .timer: (.audio, nil, .screen, .keyboard),
            .search: (nil, .apps, .audio, nil),
            .apps: (.search, .keyboard, .audio, nil),
            .keyboard: (.apps, .settings, .timer, nil),
            .settings: (.keyboard, nil, .timer, nil),
        ]
        guard let way = grid[focus] else { return }
        let next = dx < 0 ? way.left : dx > 0 ? way.right : dy < 0 ? way.up : way.down
        if let next = next { focus = next }
    }

    func back() {
        if outputFocus != nil { outputFocus = nil } else { close() }
    }

    func press(_ tile: Tile? = nil) {
        if let row = outputFocus {
            if row < outputs.count { setOutput(outputs[row].id) }
            outputFocus = nil
            return
        }
        let tile = tile ?? focus
        focus = tile
        switch tile {
        case .sleep:
            close()
            run("/usr/bin/pmset", "sleepnow")
        case .screen:
            close()
            Launcher.home()
        case .network: break
        case .audio:
            outputs = ControlCenter.outputDevices()
            outputFocus = outputs.firstIndex { $0.id == ControlCenter.defaultOutput() } ?? 0
        case .timer: cycleTimer()
        case .search:
            close()
            Launcher.search()
        case .apps:
            close()
            AppSwitcher.shared.open()
        case .keyboard:
            close()
            AppKeyboard.shared.open()
        case .settings:
            close()
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
        }
    }

    private func run(_ path: String, _ args: String...) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try? process.run()
    }

    // MARK: - Sleep timer

    /// Off, then 15, 30, 60 and 90 minutes, then off again; the Mac sleeps when it runs out.
    private func cycleTimer() {
        let steps: [TimeInterval] = [15, 30, 60, 90].map { $0 * 60 }
        let left = timerEnd.map { $0.timeIntervalSinceNow } ?? 0
        let next = steps.first { $0 > left + 30 }
        sleepTimer?.invalidate()
        guard let duration = next else { timerEnd = nil; return }
        timerEnd = Date().addingTimeInterval(duration)
        sleepTimer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.timerEnd = nil
            self?.run("/usr/bin/pmset", "sleepnow")
        }
    }

    var timerText: String {
        guard let end = timerEnd else { return "Sleep Timer" }
        let left = max(0, Int(end.timeIntervalSince(now)))
        return String(format: "%d:%02d", left / 60, left % 60)
    }

    // MARK: - Network

    var networkText: (title: String, detail: String) {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0, let first = list else { return ("Network", "Offline") }
        defer { freeifaddrs(list) }
        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let item = pointer.pointee
            guard item.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: item.ifa_name)
            guard name.hasPrefix("en") else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(item.ifa_addr, socklen_t(item.ifa_addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            return (name == "en0" ? "Network" : "Network", String(cString: host))
        }
        return ("Network", "Offline")
    }

    // MARK: - Audio output

    static func defaultOutput() -> AudioDeviceID {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return id
    }

    static func outputDevices() -> [(id: AudioDeviceID, name: String)] {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        var size: UInt32 = 0
        AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size)
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &ids)
        return ids.compactMap { id in
            var streams = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyStreams, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMaster)
            var count: UInt32 = 0
            AudioObjectGetPropertyDataSize(id, &streams, 0, nil, &count)
            guard count > 0 else { return nil }
            var nameAddress = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
            var name: CFString = "" as CFString
            var nameSize = UInt32(MemoryLayout<CFString>.size)
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &nameSize, &name)
            return (id, name as String)
        }
    }

    private func setOutput(_ id: AudioDeviceID) {
        var device = id
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMaster)
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, UInt32(MemoryLayout<AudioDeviceID>.size), &device)
    }

    var outputName: String {
        let current = ControlCenter.defaultOutput()
        return ControlCenter.outputDevices().first { $0.id == current }?.name ?? "Audio"
    }
}

/// A real blur of what is behind the panel, which is what makes the tiles read as glass.
struct PanelGlass: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

struct ControlCenterView: View {
    @ObservedObject var center: ControlCenter

    var body: some View {
        VStack(alignment: .trailing, spacing: 18) {
            if center.outputFocus != nil { outputs } else { tiles }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 470, height: 454, alignment: .top)
    }

    private var tiles: some View {
        VStack(spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                tile(.sleep, width: 190, height: 190, round: 40) {
                    VStack(spacing: 14) {
                        Image(systemName: "power").font(.system(size: 64, weight: .light))
                        Text("Sleep").font(.system(size: 18, weight: .medium))
                    }
                }
                VStack(spacing: 14) {
                    wide(.network, icon: "network", title: center.networkText.title, detail: center.networkText.detail)
                    wide(.screen, icon: "house.fill", title: "Home", detail: "AIOStreams")
                }
            }
            HStack(spacing: 14) {
                wide(.audio, icon: "hifispeaker.fill", title: "Audio", detail: center.outputName)
                wide(.timer, icon: "timer", title: center.timerText, detail: center.timerEnd == nil ? "Off" : "until sleep")
            }
            HStack(spacing: 14) {
                circle(.search, "magnifyingglass")
                circle(.apps, "square.on.square")
                circle(.keyboard, "keyboard")
                circle(.settings, "gearshape")
            }
        }
    }

    private var outputs: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Audio Output").font(.system(size: 20, weight: .bold)).foregroundColor(.white).padding(.leading, 8)
            ForEach(0..<center.outputs.count, id: \.self) { i in
                let picked = center.outputFocus == i
                let current = center.outputs[i].id == ControlCenter.defaultOutput()
                HStack {
                    Text(center.outputs[i].name).lineLimit(1)
                    Spacer()
                    if current { Image(systemName: "checkmark") }
                }
                .font(.system(size: 18, weight: .medium))
                .foregroundColor(picked ? .black : .white)
                .padding(.horizontal, 18)
                .frame(height: 46)
                .background(glass(picked: picked, shape: Capsule()))
                .onTapGesture { center.outputFocus = i; center.press() }
            }
        }
    }

    private func wide(_ kind: ControlCenter.Tile, icon: String, title: String, detail: String) -> some View {
        tile(kind, width: 190, height: 88, round: 44) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 26, weight: .medium)).frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 17, weight: .semibold)).lineLimit(1)
                    Text(detail).font(.system(size: 14, weight: .medium)).opacity(0.75).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
        }
    }

    private func circle(_ kind: ControlCenter.Tile, _ icon: String) -> some View {
        tile(kind, width: 88, height: 88, round: 44) {
            Image(systemName: icon).font(.system(size: 28, weight: .medium))
        }
    }

    private func tile<Content: View>(_ kind: ControlCenter.Tile, width: CGFloat, height: CGFloat, round: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let picked = center.focus == kind
        let shape = RoundedRectangle(cornerRadius: round, style: .continuous)
        return content()
            .foregroundColor(picked ? .black : .white)
            .frame(width: width, height: height)
            .background(glass(picked: picked, shape: shape))
            .scaleEffect(picked ? 1.06 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.8), value: picked)
            .contentShape(shape)
            .onTapGesture { center.press(kind) }
    }

    /// Glass when idle, solid white when focused, as tvOS shows it.
    private func glass<S: Shape>(picked: Bool, shape: S) -> some View {
        ZStack {
            PanelGlass().clipShape(shape)
            shape.fill(Color.white.opacity(picked ? 0.95 : 0.06))
            GlassEdge(shape: shape)
        }
        .shadow(color: Color.black.opacity(0.3), radius: 14, y: 6)
    }
}
