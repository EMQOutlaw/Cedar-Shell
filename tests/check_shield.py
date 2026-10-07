#!/usr/bin/env python3
"""Offscreen: Shield's derived protections from fixture provider data, and the page at three widths.

Optional argv[1]: a directory for the renders. Test mode never runs shield.py;
the fixture stands in for a real snapshot.
"""
from pathlib import Path
import json, os, re, shutil, subprocess, sys, tempfile
ROOT = Path(__file__).resolve().parents[1]
FIXTURE = {
    "firewall": {"available": True, "provider": "ufw", "owner": "ufw", "active": True, "unit": "ufw.service", "competing": False,
                 "providers": [{"provider": "ufw", "active": True, "enabled": True, "unit": "ufw.service", "configured": True}]},
    "dns": {"resolver": "systemd-resolved", "supported": True, "mode": "off", "provider": "custom", "providerLabel": "Custom", "servers": ["192.0.2.1"], "link": "eno1",
            "connection": {"name": "Wired connection 1", "uuid": "x", "dnsOverTls": "-1", "dns": "", "ignoreAutoDns": "no"}, "reason": ""},
    "wifi": {"available": True, "device": "wlp8s0", "connected": False, "connection": "Home", "policy": "stable", "raw": "stable"},
    "exposure": {"listeners": [{"proto": "udp", "port": 5353, "bind": "0.0.0.0", "scope": "all", "process": "avahi"}, {"proto": "tcp", "port": 22, "bind": "0.0.0.0", "scope": "all", "process": ""},
                               {"proto": "tcp", "port": 631, "bind": "127.0.0.1", "scope": "local", "process": "cupsd"}], "local": 1, "lan": 0, "all": 2, "exposed": 2, "truncated": False},
    "privilege": {"helper": "pkexec", "agent": True}
}
with tempfile.TemporaryDirectory(prefix='cedar-shield-') as tmp:
    p = Path(tmp); source = p / 'shell'; shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
    runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
    shots = Path(sys.argv[1]).resolve() if len(sys.argv) > 1 else p / 'shots'; shots.mkdir(parents=True, exist_ok=True)
    (source / 'preview.qml').write_text('''
import QtQuick
import Quickshell
import "."
import "modules"
import "services"
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1200
        implicitHeight: 900
        color: Theme.background
        property int step: 0
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function state(id) { const p = Shield.protections.find(p => p.id === id); return p ? p.state : "missing"; }
        Flickable { id: flick; x: 24; y: 24; width: 1152; height: parent.height - 48; contentHeight: page.implicitHeight; clip: true
            ShieldSettings { id: page; width: 1152; active: true } }
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                switch (window.step++) {
                case 0:
                    window.check(!Shield.ready && Shield.headline === "Reading your protections…", "Before data the headline says so (" + Shield.headline + ")");
                    window.check(window.state("firewall") === "unavailable" && window.state("exposure") === "unavailable", "No data reads as unavailable, never as off");
                    Shield.data = %s; Shield.ready = true;
                    break;
                case 1:
                    window.check(window.state("firewall") === "on" && Shield.protections[0].detail === "Managed by ufw", "Firewall on, managed by ufw (" + JSON.stringify(Shield.protections[0]) + ")");
                    window.check(window.state("dns") === "off" && Shield.protections[1].value.startsWith("Plain DNS"), "Plain DNS reads as off, never as encrypted (" + Shield.protections[1].value + ")");
                    window.check(window.state("wifi") === "on" && Shield.protections[2].value === "Stable private", "Stable private address is on");
                    window.check(window.state("exposure") === "warn" && Shield.protections[3].value === "2 services visible to your network", "Exposure translated to plain words (" + Shield.protections[3].value + ")");
                    window.check(Shield.offCount >= 1 && /protection(s)? (is|are) off/.test(Shield.headline), "Headline counts what is off (" + Shield.headline + ")");
                    flick.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/shield-wide.png"));
                    break;
                case 2:
                    Shield.data = Object.assign({}, Shield.data, { dns: Object.assign({}, Shield.data.dns, { mode: "strict", provider: "cloudflare", providerLabel: "Cloudflare", servers: ["1.1.1.1#cloudflare-dns.com"] }) });
                    window.check(window.state("dns") === "on" && Shield.protections[1].value === "DNS-over-TLS · Cloudflare", "Strict DoT with a known provider is on (" + Shield.protections[1].value + ")");
                    Shield.data = Object.assign({}, Shield.data, { dns: Object.assign({}, Shield.data.dns, { supported: false, reason: "static resolv.conf" }) });
                    window.check(window.state("dns") === "unavailable" && Shield.protections[1].value === "Not supported by current resolver", "An unsupported resolver is unavailable, not off");
                    page.width = 760 - 48; flick.width = 760 - 48;
                    break;
                case 3:
                    flick.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/shield-normal.png"));
                    page.width = 520 - 48; flick.width = 520 - 48;
                    break;
                case 4:
                    flick.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/shield-narrow.png"));
                    break;
                case 5:
                    console.log("PASS: Shield protections from provider data and the page at three widths");
                    Qt.quit();
                }
            }
        }
    }
}
''' % json.dumps(FIXTURE))
    env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QSG_RHI_BACKEND': 'software', 'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state'), 'CEDAR_SCREENSHOT_DIR': str(shots)}
    result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=60)
    output = result.stdout + result.stderr
    if result.returncode or 'PASS: Shield' not in output or re.search(r'Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|is not defined|Unable to assign|FAIL:', output):
        print(output[-6000:]); raise SystemExit(1)
    print('PASS: Shield protections from provider data and the page at three widths')
