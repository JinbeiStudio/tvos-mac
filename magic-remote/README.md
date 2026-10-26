# Magic Remote TV app

Uses the LG Magic Remote as the Mac's mouse and keyboard, with [MagicRemoteService](https://github.com/Cathwyler/MagicRemoteService) (GPL-3.0).
Its webOS app runs on the TV and sends the remote's pointer, clicks, wheel and keys to the tvOS Mac app (`../tvos`),
which stands in for the project's Windows service.

- `npm install`, then `./make-tv-app.py [mac-ip] [subnet-mask]` (default: this Mac's Wi-Fi address). It clones MagicRemoteService
  into `upstream/` on first use and packages its TV app for HDMI 1 to 4 into `out/`, one `.ipk` per port, with the Apple TV icon.
- Install on the TV (Developer Mode) the one for the HDMI port the Mac is plugged into. Re-run it if the Mac's address changes:
  give the Mac a fixed address in the router.
