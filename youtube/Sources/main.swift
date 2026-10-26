import AppKit

let app = NSApplication.shared
// A kill from outside (a rebuild stopping the app) quits properly, so the web view saves its sign-in first.
signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
stop.setEventHandler { NSApp.terminate(nil) }
stop.resume()
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.regular)
app.run()
