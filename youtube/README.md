# YouTube (Mac)

The youtube-webos script (ad blocking, SponsorBlock, best quality, no Shorts) inside a web view on YouTube's TV page.

- `./build.sh` builds the app with the script kept in `Resources/` and installs it in `/Applications`. `./build.sh script` first rebuilds the script from https://github.com/webosbrew/youtube-webos (GPL-3.0), cloned into `upstream/` (not committed).
- The tvOS Mac app (`../tvos`) opens it from the remote's app switcher and sends it the coloured buttons.
- The web view presents itself as an LG TV browser, which YouTube's TV page requires. `Resources/shim.js` stands in for what webOS provides.
- Keys: arrows, Return, Esc as on a remote; F1 to F4 are the red, green, yellow and blue buttons (Cmd+S opens the script's settings from the menu; best quality is on by default).
- `YT_WINDOWED=1` keeps it out of full screen.
- The TV page lays out in 16:9 and leaves bars on a 16:10 screen (none on a 16:9 TV). F5 stretches the interface to fill; it is off by default because the stretch distorts the menu icons.
