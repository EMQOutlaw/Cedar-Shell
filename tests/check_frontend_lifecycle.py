#!/usr/bin/env python3
"""Frontend lifecycle regressions; --native also exercises the real Canopy window.

All preferences/state are disposable and CEDAR_TEST prevents hardware actions.
Only the copied AudioSpectrum test-mode gate is removed to exercise its demand
binding; Pulse's test-mode guard still prevents starting CAVA. In --native mode
the copied CanopyWindow's test-mode motion gate is removed to exercise the real
animations while services remain in test mode. No installed shell is reloaded.
"""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--native', action='store_true')
parser.add_argument('--output', type=Path)
args = parser.parse_args()

HARNESS = '''
import QtQuick
import QtTest
import Quickshell
import "."
import "components"
import "components/trailwatch"
import "services"
ShellRoot {
    settings.watchFiles: false
    QtObject { id: auth; property bool busy: false; property string status: "Enter your password"; signal clearInputs() }
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 600; implicitHeight: 300
        color: Theme.background
        Loader { id: pulse; active: false; sourceComponent: CanopyPulse { active: true } }
        Loader { id: spectrum; active: false; sourceComponent: AudioSpectrum { active: true } }
        Loader { id: host; active: false }
        Loader { id: overview; active: false; width: 500; height: 700; source: "modules/WorkspaceCanopy.qml" }
        Loader { id: sample; active: false; width: 400; height: 300 }
        TestCase {
            name: "FrontendLifecycle"
            when: window.visible
            property int failures: 0
            function check(ok, message) {
                if (!ok) { failures++; console.error("FAIL: " + message); }
                verify(ok, message);
            }
            function init() {
                Config.saved.performanceMode = "off";
                Config.saved.reducedMotion = false;
                Config.saved.motionPreset = "balanced";
                Config.saved.canopyEnabled = true;
                Canopy.close();
            }
            function cleanup() { pulse.active = false; spectrum.active = false; overview.active = false; sample.active = false; Canopy.close(); wait(50); }
            function canvases(item) {
                let found = typeof item.requestPaint === "function" ? [item] : [];
                for (const child of item.children || []) found = found.concat(canvases(child));
                return found;
            }
            function test_atmosphere_backing_bounds() {
                Config.saved.reducedMotion = true;
                for (const size of [[1200, 900], [480, 800], [400, 100]]) {
                    window.implicitWidth = size[0]; window.implicitHeight = size[1];
                    sample.width = size[0]; sample.height = size[1];
                    sample.setSource(Qt.resolvedUrl("components/CedarAtmosphere.qml"), {active: false});
                    sample.active = true; wait(150);
                    const canvas = canvases(sample.item)[0];
                    check(canvas.height === Math.min(156, size[1]), "Atmosphere bounds its transparent backing at " + size);
                    const cropped = grabImage(sample.item);
                    // Restore the old full-height backing on the same production
                    // painter: both versions must render identical pixels.
                    canvas.height = size[1]; canvas.requestPaint(); wait(150);
                    check(cropped.equals(grabImage(sample.item)), "Cropping the atmosphere preserves every rendered pixel at " + size);
                    sample.active = false;
                }
                window.implicitWidth = 600; window.implicitHeight = 300;
                sample.width = 400; sample.height = 300;
                console.log("PASS: atmosphere backing bounds and exact rendered-pixel equivalence");
            }
            function test_canvas_palette() {
                Config.saved.reducedMotion = true;
                const original = Theme.palette;
                const rows = [
                    ["components/ArcGauge.qml", { active: false }],
                    ["components/CedarAtmosphere.qml", { active: false }],
                    ["components/HudPanel.qml", { accent: "#123456", fillColor: "#080f0d" }],
                    ["components/StationCore.qml", { active: false }],
                    ["components/TransactionHudCard.qml", {}],
                    ["components/trailwatch/Topo.qml", {}],
                    ["components/trailwatch/WatchFace.qml", { active: false, date: new Date(2026, 5, 1, 12, 0, 0) }],
                    ["modules/DisplaySettings.qml", {}],
                    ["modules/TrailwatchView.qml", { active: false, auth: auth, preview: true, date: new Date(2026, 5, 1, 12, 0, 0) }],
                    ["modules/WorkspaceCanopy.qml", { active: false }]
                ];
                for (const row of rows) {
                    Theme.palette = original;
                    sample.setSource(Qt.resolvedUrl(row[0]), row[1]); sample.active = true; wait(150);
                    check(sample.item !== null, "Palette sample loaded: " + row[0]);
                    const painted = canvases(sample.item);
                    check(painted.length > 0, "Sample contains a Canvas: " + row[0]);
                    Theme.palette = { border: "#ee22bb", green: "#ff4466", teal: "#ddaa22", muted: "#7788ff", amber: "#ccddff" };
                    wait(150);
                    const automatic = grabImage(sample.item);
                    for (const canvas of painted) canvas.requestPaint();
                    wait(100);
                    const explicit = grabImage(sample.item);
                    let matches = automatic.equals(explicit);
                    // Native fractional-scale raster uploads can round a few
                    // channels differently on an otherwise identical repaint.
                    // Keep offscreen exact; native permits one 8-bit step only.
                    if (!matches && Quickshell.env("CEDAR_AUDIT_NATIVE") === "1") {
                        matches = true;
                        for (let y = 0; y < automatic.height && matches; y++) {
                            for (let x = 0; x < automatic.width; x++) {
                                if (Math.abs(automatic.red(x,y) - explicit.red(x,y)) > 1
                                        || Math.abs(automatic.green(x,y) - explicit.green(x,y)) > 1
                                        || Math.abs(automatic.blue(x,y) - explicit.blue(x,y)) > 1
                                        || Math.abs(automatic.alpha(x,y) - explicit.alpha(x,y)) > 1) {
                                    matches = false; break;
                                }
                            }
                        }
                        if (matches) console.log("NOTE: native repaint differs only by one 8-bit channel step: " + row[0]);
                    }
                    if (!matches && Quickshell.env("CEDAR_AUDIT_OUTPUT")) {
                        const name = row[0].split("/").join("-");
                        automatic.save(Quickshell.env("CEDAR_AUDIT_OUTPUT") + "/" + name + "-automatic.png");
                        explicit.save(Quickshell.env("CEDAR_AUDIT_OUTPUT") + "/" + name + "-explicit.png");
                    }
                    if (!matches) { failures++; console.error("FAIL: Canvas palette stale until forced repaint: " + row[0]); }
                    sample.active = false; wait(20);
                }
                Theme.palette = original;
                console.log("PASS: Canvas theme invalidation comparisons completed");
            }
            function findWindow(item) {
                if (item.address === "fixture") return item;
                for (const child of item.children || []) {
                    const found = findWindow(child);
                    if (found) return found;
                }
                return null;
            }
            function test_workspace_drag() {
                overview.active = true; wait(100);
                const tile = findWindow(overview.item);
                check(tile !== null, "Fixture window is represented in the actual workspace overview");
                const originalX = tile.x, originalY = tile.y;
                const at = tile.mapToItem(overview.item, tile.width / 2, tile.height / 2);
                mousePress(overview.item, at.x, at.y);
                mouseMove(overview.item, at.x + 35, at.y + 20, 30);
                mouseMove(overview.item, at.x + 50, at.y + 30, 30);
                check(tile.x !== originalX || tile.y !== originalY, "Pointer movement actually drags the thumbnail");
                mouseRelease(overview.item, at.x + 50, at.y + 30);
                wait(50);
                check(Math.abs(tile.x - originalX) < .01 && Math.abs(tile.y - originalY) < .01, "Dropping in the same workspace restores compositor geometry");
                tile.modelData.lastIpcObject = { at: [160, 140], size: [600, 400], class: "Fixture" };
                wait(30);
                check(tile.x !== originalX && tile.y !== originalY, "Compositor geometry updates still reach a previously dragged thumbnail");
                const expectedX = tile.x, expectedY = tile.y;
                const area = tile.children.find(child => child.drag && child.drag.target === tile);
                check(area !== undefined, "Thumbnail has its production drag handler");
                const next = tile.mapToItem(overview.item, tile.width / 2, tile.height / 2);
                mousePress(overview.item, next.x, next.y);
                mouseMove(overview.item, next.x + 35, next.y + 20, 30);
                mouseMove(overview.item, next.x + 50, next.y + 30, 30);
                // Removing input eligibility cancels the real pointer grab.
                area.enabled = false; wait(30);
                mouseRelease(overview.item, next.x + 50, next.y + 30);
                check(Math.abs(tile.x - expectedX) < .01 && Math.abs(tile.y - expectedY) < .01, "Canceled pointer grabs also restore geometry");
                console.log("PASS: workspace pointer drag restores reactive geometry");
            }
            function test_feed_lifetime() {
                const baseline = Pulse.demand;
                for (const loader of [pulse, spectrum]) {
                    for (let i = 0; i < 100; i++) {
                        loader.active = true;
                        check(Pulse.demand === baseline + 1, "Exactly one feed hold per component, cycle " + i + ": " + Pulse.demand);
                        loader.item.visible = false;
                        check(Pulse.demand === baseline, "A hidden visualizer releases its hold");
                        loader.item.visible = true;
                        check(Pulse.demand === baseline + 1, "Showing it reacquires one hold");
                        loader.item.active = false;
                        check(Pulse.demand === baseline, "An inactive visualizer releases its hold");
                        loader.item.active = true;
                        loader.active = false;
                        check(Pulse.demand === baseline, "Destruction releases the last hold");
                    }
                }
                pulse.active = true; spectrum.active = true;
                check(Pulse.demand === baseline + 2, "Two consumers share one feed independently");
                pulse.active = false;
                check(Pulse.demand === baseline + 1, "Removing one consumer retains the other");
                spectrum.active = false;
                check(Pulse.demand === baseline, "No demand survives all consumers");
                console.log("PASS: 200 visualizer lifecycles, visibility, activation and shared ownership");
            }
            function test_native_canopy() {
                if (Quickshell.env("CEDAR_AUDIT_NATIVE") !== "1") {
                    console.log("SKIP: native Canopy geometry and transitions (use --native)");
                    return;
                }
                host.setSource(Qt.resolvedUrl("modules/CanopyWindow.qml"), { modelData: Quickshell.screens[0], implicitHeight: 740 });
                host.active = true;
                check(host.item !== null, "CanopyWindow initialized");
                const canopy = host.item;
                const output = Quickshell.screens[0].name;
                Canopy.open("power", output); wait(900);
                check(canopy.mapped && Canopy.surfaceState === "expanded", "Canopy opens and settles");
                const initialHeight = Canopy.surfaceRect.height;
                canopy.implicitHeight = 300; wait(650);
                check(Canopy.surfaceRect.height <= canopy.height - canopy.barJoin - 16, "Vertical resize retargets the open Canopy");
                canopy.implicitHeight = 740; wait(650);
                check(Canopy.surfaceRect.height === initialHeight, "Restoring height restores original geometry");
                canopy.implicitHeight = 340; wait(650);
                Config.saved.barHeight = 72; wait(650);
                check(Canopy.surfaceRect.height <= canopy.height - canopy.barJoin - 16, "Bar-height change retargets available space");
                Config.saved.barHeight = 44;
                canopy.implicitHeight = 740;
                const left = () => ({ x: 20, width: 32 });
                const right = () => ({ x: canopy.width - 52, width: 32 });
                Canopy.setAnchorProvider("quick", output, left);
                Canopy.setAnchorProvider("power", output, right);
                for (let i = 0; i < 30; i++) {
                    Canopy.close(); wait(15);
                    Canopy.open("quick", output); wait(15);
                    Canopy.open("power", output); wait(15);
                }
                wait(1000);
                check(canopy.mapped && Canopy.surfaceState === "expanded", "Rapid reopen and cross-origin switches settle");
                check(Canopy.surfaceRect.x + Canopy.surfaceRect.width <= canopy.width - 12, "Final panel stays inside the screen");
                Canopy.close(); wait(650);
                check(!canopy.mapped && Canopy.surfaceState === "collapsed", "Closing releases the mapped surface");
                Canopy.clearAnchorProvider("quick", output, left);
                Canopy.clearAnchorProvider("power", output, right);
                host.active = false;
                // Recreate the host, as when its output is replaced on reload.
                host.active = true;
                Canopy.open("power", output); wait(900);
                check(host.item.mapped && Canopy.surfaceState === "expanded", "A recreated host opens correctly");
                Canopy.close(); wait(650); host.active = false;
                console.log("PASS: native Canopy resize, bar height, 30 rapid switches, close and host recreation");
            }
            function cleanupTestCase() {
                wait(100);
                if (failures) { console.error("FAIL: lifecycle assertions: " + failures); Qt.exit(1); }
                else console.log("PASS: frontend lifecycle assertions completed");
            }
        }
    }
}
'''

with tempfile.TemporaryDirectory(prefix='cedar-frontend-') as temporary:
    base = Path(temporary)
    source = base / 'shell'
    shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('.git', '__pycache__'))
    for name in ('runtime', 'config', 'state', 'cache'):
        (base / name).mkdir(mode=0o700)
    # Supply compositor data only to the copied WorkspaceCanopy. Its actual
    # delegates and pointer handlers run unchanged, with no real dispatches.
    fixtures = source / 'audit-fixtures'
    fixtures.mkdir()
    (fixtures / 'qmldir').write_text('singleton Hyprland 1.0 Hyprland.qml\n')
    (fixtures / 'Hyprland.qml').write_text('''
pragma Singleton
import QtQuick
QtObject {
    property bool usingLua: false
    property QtObject monitor: QtObject { property string name: "Fixture"; property int x: 0; property int y: 0; property int width: 1920; property int height: 1080; property real scale: 1; property bool focused: true }
    property QtObject client: QtObject { property string address: "fixture"; property string title: "Fixture"; property bool activated: true; property var wayland: null; property var lastIpcObject: ({ at: [100, 100], size: [600, 400], class: "Fixture" }) }
    property QtObject workspace: QtObject { property int id: 1; property string name: "1"; property var monitor: Hyprland.monitor; property bool active: true; property bool hasFullscreen: false; property bool urgent: false; property var toplevels: ({ values: [Hyprland.client] }) }
    property var monitors: ({ values: [monitor] })
    property var workspaces: ({ values: [workspace] })
    property var focusedWorkspace: workspace
    signal activeToplevelChanged()
    function dispatch(command) { console.error("FAIL: unexpected compositor dispatch: " + command); }
}
''')
    workspace = source / 'modules/WorkspaceCanopy.qml'
    workspace.write_text(workspace.read_text().replace('import Quickshell.Hyprland', 'import "../audit-fixtures"'))
    path = source / 'components/AudioSpectrum.qml'
    original = path.read_text()
    assert original.count(' && !Config.testMode') == 1
    path.write_text(original.replace(' && !Config.testMode', '', 1))
    if args.native:
        path = source / 'modules/CanopyWindow.qml'
        original = path.read_text()
        gate = 'readonly property bool morphing: VisualQuality.functionalMotion && !Config.testMode'
        assert original.count(gate) == 1
        path.write_text(original.replace(gate, gate.replace(' && !Config.testMode', ''), 1))
    (source / 'audit.qml').write_text(HARNESS)
    env = {**os.environ, 'CEDAR_TEST': '1', 'CEDAR_LOCAL_ONLY': '1',
           'CEDAR_AUDIT_NATIVE': '1' if args.native else '0',
           'QT_QPA_PLATFORM': 'wayland' if args.native else 'offscreen',
           'QT_QPA_PLATFORMTHEME': 'basic', 'QT_QUICK_CONTROLS_STYLE': 'Basic',
           'XDG_CONFIG_HOME': str(base / 'config'), 'XDG_STATE_HOME': str(base / 'state'),
           'XDG_CACHE_HOME': str(base / 'cache')}
    if not args.native:
        env.update(XDG_RUNTIME_DIR=str(base / 'runtime'), QT_QUICK_BACKEND='software', QSG_RENDER_LOOP='basic')
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        env['CEDAR_AUDIT_OUTPUT'] = str(args.output.resolve())
    result = subprocess.run(['qs', '-p', str(source / 'audit.qml')], env=env,
                            capture_output=True, text=True, timeout=40)
    output = result.stdout + result.stderr
    if args.output:
        args.output.mkdir(parents=True, exist_ok=True)
        (args.output / 'lifecycle.log').write_text(output)
    print(output)
    required = ['PASS: atmosphere backing bounds', 'PASS: Canvas theme invalidation', 'PASS: 200 visualizer lifecycles', 'PASS: workspace pointer drag', 'PASS: frontend lifecycle assertions completed']
    if args.native:
        required.append('PASS: native Canopy resize')
    if result.returncode or any(marker not in output for marker in required) or re.search(
            r'FAIL[:!]|Failed to load configuration|ReferenceError|TypeError|Binding loop|Cannot assign|Unable to assign|recursive rearrange', output):
        raise SystemExit(1)
