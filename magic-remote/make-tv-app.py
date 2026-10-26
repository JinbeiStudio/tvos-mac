#!/usr/bin/env python3
"""Packages MagicRemoteService's webOS app for one or all HDMI ports, with this Mac as the receiver.

Does what the project's Windows installer does before it installs (its Setting.AppExtract), then runs ares-package.
Usage: make-tv-app.py [mac-ip] [subnet-mask]   (defaults: this Mac's Wi-Fi address)
First run `npm install` here; MagicRemoteService (GPL-3.0) is cloned into upstream/ on first use.
"""
import os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
SRC = os.path.join(HERE, "upstream/MagicRemoteService/Resources/TV")
OUT = os.path.join(HERE, "out")
# LG's packager, installed by `npm install` beside this script.
CLI = os.path.join(HERE, "node_modules/@webos-tools/cli/bin/ares-package.js")
VERSION = "1.3.2"

if not os.path.isdir(SRC):
    subprocess.run(["git", "clone", "--depth", "1", "https://github.com/Cathwyler/MagicRemoteService", os.path.join(HERE, "upstream")], check=True)

def sh(*args):
    return subprocess.run(args, capture_output=True, text=True).stdout.strip()

args = [a for a in sys.argv[1:] if not a.startswith('--')]
ip = args[0] if len(args) > 0 else sh("ipconfig", "getifaddr", "en0")
mask = args[1] if len(args) > 1 else "255.255.255.0"
mac = (sh("sh", "-c", "ifconfig en0 | awk '/ether/{print $2}'") or "AA:AA:AA:AA:AA:AA").upper()

def sub(text, old, new):
    if old not in text:
        raise SystemExit("template changed, not found: " + old)
    return text.replace(old, new)

def put_icons(app):
    # The Apple TV icon, so the TV app matches the tvOS launcher.
    r = subprocess.run(["node", os.path.join(HERE, "icons.mjs"), app], capture_output=True, text=True)
    if r.returncode: raise SystemExit(r.stdout + r.stderr)

def build(n, debug=False, novideo=False):
    short, name = "hdmi%d" % n, "HDMI %d" % n
    work = tempfile.mkdtemp()
    shutil.copytree(os.path.join(SRC, "MagicRemoteService"), os.path.join(work, "MagicRemoteService"))
    shutil.copytree(os.path.join(SRC, "Service"), os.path.join(work, "Service"))
    app, svc = os.path.join(work, "MagicRemoteService"), os.path.join(work, "Service")
    # A fresh id, so the TV shows the current icon instead of the one it cached for the old id.
    appid = "com.jinbeistudio.tvapp." + short
    put_icons(app)

    def edit(path, pairs):
        with open(path, encoding="utf-8") as f: text = f.read()
        for old, new in pairs: text = sub(text, old, new)
        with open(path, "w", encoding="utf-8") as f: f.write(text)

    edit(os.path.join(app, "main.js"), [
        ('const strInputId = "HDMI"', 'const strInputId = "HDMI_%d"' % n),
        ('const strInputAppId = "com.webos.app.hdmi"', 'const strInputAppId = "com.webos.app.%s"' % short),
        ('const strInputName = "HDMI"', 'const strInputName = "%s"' % name),
        ('const strInputSource = "ext://hdmi"', 'const strInputSource = "ext://hdmi:%d"' % n),
        ('const strIP = "127.0.0.1"', 'const strIP = "%s"' % ip),
        ('const strMask = "255.255.255.0"', 'const strMask = "%s"' % mask),
        ('const strMac = "AA:AA:AA:AA:AA:AA"', 'const strMac = "%s"' % mac),
        ('const strAppId = "com.cathwyler.magicremoteservice"', 'const strAppId = "%s"' % appid),
    ] + ([('const bDebug = false;', 'const bDebug = true;')] if debug else [])
      # For trying the keys with no cable: connect without waiting for the HDMI input to be active, and say nothing when it is not.
      + ([('\t\tSubscriptionInputStatus();\n\t\tSubscriptionGetSensorData();',
           '\t\tSubscriptionInputStatus();\n\t\tsetTimeout(function() { if(socClient === null) { Open(); } }, 3000);\n\t\tInputDisconnected = function() {};\n\t\tSubscriptionGetSensorData();')] if novideo else []))
    edit(os.path.join(app, "appinfo.json"), [
        ('"id": "com.cathwyler.magicremoteservice"', '"id": "%s"' % appid),
        ('"title": "MagicRemoteService"', '"title": "tvOS"'),
        # No mini icon, like the AIOStreams app.
        ('\t"miniIcon": "miniIcon.png",\n', ''),
        # The launcher shows the icon a little inset on this colour, so it matches the icon's own grey.
        ('"bgColor": "#575E66"', '"bgColor": "#2f2f2f"'),
        ('"iconColor": "#575E66"', '"iconColor": "#2f2f2f"'),
        ('"version": "1.0.0"', '"version": "%s"' % VERSION),
        ('"appDescription": "HDMI"', '"appDescription": "%s"' % name),
    ])
    edit(os.path.join(app, "appstring.json"), [
        ('"strAppTittle": "MagicRemoteService"', '"strAppTittle": "tvOS"'),
        ('"strAppDescription": "HDMI"', '"strAppDescription": "%s"' % name)])
    edit(os.path.join(svc, "package.json"), [
        ('"name": "com.cathwyler.magicremoteservice.service"', '"name": "%s.service"' % appid)])
    edit(os.path.join(svc, "service.js"), [
        ('var strInputAppId = "com.webos.app.hdmi"', 'var strInputAppId = "com.webos.app.%s"' % short),
        ('var strAppId = "com.cathwyler.magicremoteservice"', 'var strAppId = "%s"' % appid)]
        + ([('var bDebug = false;', 'var bDebug = true;')] if debug else []))
    edit(os.path.join(svc, "services.json"), [
        ('"id": "com.cathwyler.magicremoteservice.service"', '"id": "%s.service"' % appid),
        ('"name": "com.cathwyler.magicremoteservice.service"', '"name": "%s.service"' % appid)])
    os.makedirs(os.path.join(svc, "WebSocket"), exist_ok=True)

    out = OUT + ("-debug" if debug else "") + ("-novideo" if novideo else "")
    os.makedirs(out, exist_ok=True)
    r = subprocess.run(["node", CLI, app, svc, "-n", "-o", out], capture_output=True, text=True)
    if r.returncode: raise SystemExit(r.stdout + r.stderr)
    shutil.rmtree(work)
    return os.path.join(out, "%s_%s_all.ipk" % (appid, VERSION))

print("Mac %s, mask %s" % (ip, mask))
if "--novideo" in sys.argv:
    print(build(int(os.environ.get("HDMI", "1")), debug="--debug" in sys.argv, novideo=True))
elif "--debug" in sys.argv:
    # One port, with the app's own error notices switched on.
    print(build(int(os.environ.get("HDMI", "1")), debug=True))
else:
    for n in (1, 2, 3, 4):
        print(build(n))
