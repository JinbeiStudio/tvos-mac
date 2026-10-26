# tvOS (Mac)

The Mac app. It lives in the menu bar: at launch it opens the AIOStreams desktop app full screen, in its tvOS
style, where everything to watch lives; YouTube (`../youtube`) is a separate app.
On top of every app it adds what a web page can't:

| Remote | Mac keyboard | Does |
| --- | --- | --- |
| Red | ⌃⌥H | AIOStreams' home |
| Green | ⌃⌥A | Your row of apps, as an overlay (held on the remote: YouTube's settings) |
| Yellow | ⌃⌥K | The on-screen keyboard (held on the remote: YouTube fills the screen) |
| Blue | ⌃⌥C | Control Center: sound output, sleep timer, search, keyboard, settings |

In the row of apps and Control Center, the arrows move, OK (Return) picks and Back (Esc) closes, on the remote or the
Mac keyboard. The row is edited from the menu bar (Edit Apps…).

- **Magic Remote**: the LG remote's pointer, clicks, wheel and keys, sent by the Magic Remote TV app (`remote-mac`) over port 41230.
- **Keyboards**: the on-screen one, also opened by a click in a text field from the remote, and the iPhone one (port 41231, offered through ntfy).
- AIOStreams opens on the web build kept in `~/Library/Application Support/tvOS/aiostreams-web`, when there is one: the
  `dist-standalone` folder of [the tvOS style](https://github.com/JinbeiStudio/AIOStreams/tree/feat/tvos-style)
  (`pnpm -F @aiostreams/web build:standalone`). Without it, the app's own pages show.
- Build: `./build.sh` (plain `swiftc`). It installs `/Applications/tvOS.app`, which needs the Accessibility permission (remote keys, shortcuts, full screen).
- `JinbeiIcon.icns` (put on the AIOStreams app as its icon) and a `profile.jpg` beside this file are used when present; they stay out of git.
