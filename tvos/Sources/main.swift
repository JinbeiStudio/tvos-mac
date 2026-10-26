import AppKit

let app = NSApplication.shared
// A kill from outside (a rebuild stopping it) quits properly.
signal(SIGTERM, SIG_IGN)
let stop = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
stop.setEventHandler { NSApp.terminate(nil) }
stop.resume()
let delegate = AppDelegate()
app.delegate = delegate
// In the background, as a menu bar app: the apps it opens are the ones on screen.
app.setActivationPolicy(.accessory)
app.run()
