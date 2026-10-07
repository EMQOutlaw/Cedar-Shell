#!/usr/bin/env python3
"""Offscreen: Shield's derived protections and posture from fixture provider data, and the application window's pages at three widths.

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
    "ipv6": {"available": True, "setting": "-1", "kernel": "0", "effective": "0", "active": False, "partial": False},
    "discovery": {"available": True, "avahi": True, "mdns": False, "llmnr": False, "setting": {"mdns": "-1", "llmnr": "-1"}, "answering": True},
    "connection": {"name": "Wired connection 1", "uuid": "11111111-2222-3333-4444-555555555555", "type": "802-3-ethernet", "device": "eno1"},
    "privilege": {"helper": "pkexec", "agent": True},
    "verifiedAt": 1791342793.0
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
        implicitWidth: 1180
        implicitHeight: 820
        color: Theme.background
        property int step: 0
        function check(ok, msg) { if (!ok) { console.error("FAIL: " + msg); Qt.exit(1); } }
        function state(id) { const p = Shield.protection(id); return p ? p.state : "missing"; }
        function shot(name) { pages.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/" + name + ".png")); }
        property int pagesWidth: 1180
        ShieldPages { id: pages; width: window.pagesWidth; height: window.height }
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                switch (window.step++) {
                case 0:
                    window.check(!Shield.ready && Shield.posture === "reading", "Before data the posture is reading (" + Shield.posture + ")");
                    window.check(window.state("firewall") === "unavailable" && window.state("exposure") === "unavailable", "No data reads as unavailable, never as off");
                    window.check(Shield.protections.length === 12 && Shield.groups.length === 4, "Twelve protections in four groups");
                    Shield.data = %s; Shield.ready = true;
                    break;
                case 1:
                    window.check(window.state("firewall") === "on" && Shield.protection("firewall").provider === "ufw", "Firewall on, provider ufw");
                    window.check(window.state("dns") === "off" && Shield.protection("dns").value === "Plain DNS", "Plain DNS reads as off, never as encrypted (" + Shield.protection("dns").value + ")");
                    window.check(window.state("wifi") === "on" && window.state("ipv6") === "off" && window.state("discovery") === "off", "Wi-Fi stable on; IPv6 and discovery off on a trusted network (" + window.state("discovery") + ")");
                    window.check(window.state("exposure") === "warn" && Shield.protection("exposure").value === "2 services visible to your network", "Exposure in plain words");
                    window.check(Shield.posture === "protected" && Shield.headline === "Protected", "Trusted network with recommended protections on is protected (" + Shield.posture + ": " + Shield.subline + ")");
                    Shield.setProfile("public");
                    window.check(Shield.publicNetwork && Shield.profile === "public", "Profile stored per connection");
                    window.check(Shield.posture === "attention" && window.state("discovery") === "warn" && Shield.recommendedOff.length >= 2, "Public network recommends more and asks for attention (" + Shield.recommendedOff.map(p => p.id).join(",") + ")");
                    Shield.setProfile("trusted");
                    window.shot("shield-app-overview");
                    break;
                case 2:
                    Shield.data = Object.assign({}, Shield.data, { firewall: Object.assign({}, Shield.data.firewall, { active: false, owner: "ufw" }) });
                    window.check(Shield.posture === "risk" && Shield.headline === "At risk", "Services on every interface with the firewall off is at risk (" + Shield.posture + ")");
                    break;
                case 3:
                    window.check(Shield.activity.length > 0 && Shield.activity[0].title.indexOf("Firewall") === 0, "A protection change is recorded in the activity log (" + JSON.stringify(Shield.activity[0]) + ")");
                    Shield.data = Object.assign({}, Shield.data, { firewall: Object.assign({}, Shield.data.firewall, { active: true }) });
                    pages.navigate("protections");
                    window.shot("shield-app-protections");
                    pages.detail = "dns";
                    break;
                case 4:
                    window.shot("shield-app-detail");
                    pages.detail = ""; pages.navigate("network");
                    break;
                case 5:
                    window.shot("shield-app-network");
                    pages.navigate("activity"); window.pagesWidth = 640;
                    break;
                case 6:
                    window.check(!pages.sidebar, "Narrow windows use the tab strip");
                    pages.navigate("overview");
                    break;
                case 7:
                    window.shot("shield-app-narrow");
                    break;
                case 8:
                    console.log("PASS: Shield protections, posture, profiles, activity and the application pages");
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
    print('PASS: Shield protections, posture, profiles, activity and the application pages')
