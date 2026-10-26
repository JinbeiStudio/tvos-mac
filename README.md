# tvOS for the Mac

Turns a Mac plugged into a TV into an Apple TV-like box, driven by the LG Magic Remote, around
[AIOStreams](https://github.com/Viren070/AIOStreams) in its tvOS style
([`feat/tvos-style`](https://github.com/JinbeiStudio/AIOStreams/tree/feat/tvos-style)).

| Folder | What it is |
| --- | --- |
| [`tvos/`](tvos) | The Mac app: in the menu bar, it opens AIOStreams full screen and adds the remote, a row of your apps, Control Center, an on-screen keyboard and an iPhone keyboard over every app. |
| [`youtube/`](youtube) | YouTube's TV interface as a Mac app, with [youtube-webos](https://github.com/webosbrew/youtube-webos) (ad blocking, SponsorBlock). |
| [`magic-remote/`](magic-remote) | The webOS app that sends the Magic Remote to the Mac, from [MagicRemoteService](https://github.com/Cathwyler/MagicRemoteService). |

Each folder has its own README and build script. Building needs the Xcode command-line tools (Swift) and, for the TV app, Node.js.

## Licence

GPL-3.0, as the projects it builds on (youtube-webos, MagicRemoteService).
