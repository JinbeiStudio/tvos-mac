import AppKit
import ApplicationServices

/// The apps this layer drives: AIOStreams (the tvOS-style web app) and YouTube, each full screen.
enum Launcher {
    static let aiostreams = URL(fileURLWithPath: "/Applications/AIOStreams.app")
    static let youtube = URL(fileURLWithPath: "/Applications/YouTube.app")

    /// The tvOS style's web build the AIOStreams app is started on, when one is kept there.
    private static let webDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/tvOS/aiostreams-web")

    /// Brings AIOStreams to the front, starting it on the fork's web app when it isn't running.
    static func openAIOStreams(then: (() -> Void)? = nil) {
        open(aiostreams, arguments: webArguments(), then: then)
    }

    static func openYouTube() { open(youtube, arguments: [], then: nil) }

    /// Gives the AIOStreams app the Jinbei Studio icon, as a Finder custom icon, which leaves its signature
    /// alone; put back at each launch, since an update of the app replaces it.
    static func brandAIOStreams() {
        guard let path = Bundle.main.path(forResource: "JinbeiIcon", ofType: "icns"),
              let icon = NSImage(contentsOfFile: path),
              FileManager.default.fileExists(atPath: aiostreams.path) else { return }
        let marker = aiostreams.appendingPathComponent("Icon\r")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        NSWorkspace.shared.setIcon(icon, forFile: aiostreams.path, options: [])
    }

    /// The remote's red button and Control Center's home tile: AIOStreams, at its home.
    static func home() {
        openAIOStreams { RemoteReceiver.shared.typeText("h") }
    }

    /// Any other app, full screen.
    static func open(_ app: URL) { open(app, arguments: [], then: nil) }

    /// Control Center's search tile: AIOStreams' search, which "/" opens.
    static func search() {
        openAIOStreams { RemoteReceiver.shared.typeText("/") }
    }

    /// A copy already running keeps what it was started with: arguments would make LaunchServices ignore it.
    private static func webArguments() -> [String] {
        if running(aiostreams) != nil { return [] }
        return FileManager.default.fileExists(atPath: webDir.appendingPathComponent("index.html").path)
            ? ["--web-dir", webDir.path] : []
    }

    static func running(_ app: URL) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleURL?.path == app.path }
    }

    private static func open(_ app: URL, arguments: [String], then: (() -> Void)?) {
        if let already = running(app) {
            already.unhide()
            already.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { then?() }
            return
        }
        guard FileManager.default.fileExists(atPath: app.path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.arguments = arguments
        NSWorkspace.shared.openApplication(at: app, configuration: config) { started, _ in
            guard let pid = started?.processIdentifier else { return }
            DispatchQueue.main.async {
                goFullScreen(pid: pid)
                // A fresh start draws its page first; the key waits for it.
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { then?() }
            }
        }
    }

    /// Puts the app's window in full screen once it has one; apps that cannot are left as they open.
    static func goFullScreen(pid: pid_t, attempts: Int = 10) {
        guard attempts > 0, AXIsProcessTrusted() else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            let app = AXUIElementCreateApplication(pid)
            var focused: CFTypeRef?
            let key = "AXFullScreen" as CFString
            if AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute as CFString, &focused) == .success,
               let window = focused {
                let win = window as! AXUIElement
                var state: CFTypeRef?
                if AXUIElementCopyAttributeValue(win, key, &state) == .success {
                    if let flag = state, CFBooleanGetValue((flag as! CFBoolean)) { return }
                    AXUIElementSetAttributeValue(win, key, kCFBooleanTrue)
                    return
                }
            }
            // The window is not there yet.
            goFullScreen(pid: pid, attempts: attempts - 1)
        }
    }

    /// The remote's coloured buttons meant for YouTube, which runs as its own app.
    static func toYouTube(_ info: [String: Any]) {
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.jinbeistudio.tvos.youtube"), object: nil,
            userInfo: info, deliverImmediately: true)
    }
}
