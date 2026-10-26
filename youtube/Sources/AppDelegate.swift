import AppKit
import WebKit

/// YouTube's TV page in a full-screen window, with the youtube-webos script injected.
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow!
    private var web: WKWebView!

    /// A TV's browser, which is what YouTube's TV page serves its leanback interface to.
    private let userAgent = "Mozilla/5.0 (Web0S; Linux/SmartTV) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/94.0.4606.128 Safari/537.36 WebAppManager"

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMenu()
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        // The stand-ins go in first; the script itself waits for the page's body, which it writes into.
        for (name, time) in [("shim", WKUserScriptInjectionTime.atDocumentStart), ("userScript", .atDocumentEnd)] {
            guard let path = Bundle.main.path(forResource: name, ofType: "js"),
                  let source = try? String(contentsOfFile: path, encoding: .utf8) else { continue }
            config.userContentController.addUserScript(WKUserScript(source: source, injectionTime: time, forMainFrameOnly: true))
        }
        web = WKWebView(frame: .zero, configuration: config)
        web.customUserAgent = userAgent
        web.setValue(false, forKey: "drawsBackground")
        web.load(URLRequest(url: URL(string: "https://www.youtube.com/tv")!))

        // The screen the pointer is on, so it opens on the display being used, whatever its size.
        let here = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }
        let frame = (here ?? NSScreen.main)?.frame ?? NSRect(x: 0, y: 0, width: 1920, height: 1080)
        window = NSWindow(
            contentRect: frame,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false
        )
        window.contentView = web
        window.backgroundColor = .black
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.collectionBehavior = [.fullScreenPrimary]
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(web)
        NSApp.activate(ignoringOtherApps: true)
        if ProcessInfo.processInfo.environment["YT_WINDOWED"] == nil { window.toggleFullScreen(nil) }
        // The remote's coloured buttons, sent by the tvOS Mac app (../tvos) while this app is in front.
        DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.jinbeistudio.tvos.youtube"), object: nil, queue: .main
        ) { [weak self] note in
            guard NSApp.isActive, let web = self?.web else { return }
            if note.userInfo?["fill"] != nil {
                web.evaluateJavaScript("window.__ytToggleFill && window.__ytToggleFill()", completionHandler: nil)
            } else if let code = note.userInfo?["code"] as? Int {
                web.evaluateJavaScript("window.__ytKey && window.__ytKey(\(code))", completionHandler: nil)
            }
        }
        // YT_EVAL runs a script on the page after it has loaded and prints the result, for checking things from outside.
        if let script = ProcessInfo.processInfo.environment["YT_EVAL"] {
            DispatchQueue.main.asyncAfter(deadline: .now() + (Double(ProcessInfo.processInfo.environment["YT_DELAY"] ?? "") ?? 14)) { [web] in
                web?.evaluateJavaScript(script) { result, error in
                    FileHandle.standardError.write(Data("EVAL \(result ?? "nil") \(error?.localizedDescription ?? "")\n".utf8))
                }
            }
        }
    }

    /// The script's own settings panel, which the remote's green button opens on a TV.
    @objc private func showSettings() {
        web.evaluateJavaScript("window.ytaf_showOptionsPanel && window.ytaf_showOptionsPanel(true)", completionHandler: nil)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// Switched away (to AIOStreams, say), the video stops rather than playing on behind.
    func applicationDidResignActive(_ notification: Notification) {
        web?.evaluateJavaScript("document.querySelectorAll('video').forEach(function(v){v.pause()})", completionHandler: nil)
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        main.addItem(appItem)
        let menu = NSMenu()
        let settings = NSMenuItem(title: "YouTube Settings…", action: #selector(showSettings), keyEquivalent: "s")
        settings.target = self
        menu.addItem(settings)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit YouTube", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        appItem.submenu = menu
        NSApp.mainMenu = main
    }
}
