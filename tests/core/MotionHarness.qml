import QtQuick
import Quickshell
import "../.."
import "../../components"
import "../../components/core"
import "../../services"
ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 900
        implicitHeight: 760
        color: Theme.background
        CedarAtmosphere { id: atmosphere; anchors.fill: parent; active: true }
        StationCore { x: 20; y: 200; time: "10:42"; active: true }
        ArcGauge { id: gauge; x: 320; y: 230; value: 0.72; pulse: true; active: true }
        CoreSurface { id: core; x: 200; maximumWidth: 480; maximumHeight: 690 }
        Breath { id: breath; running: Motion.active; from: 0; to: 1; rise: 300 }
        // Production instruments, with explicit event inputs rather than a
        // decorative loop. Inspect their intermediate and fully rested states.
        CedarRootlines {
            id: roots; y: 680; width: parent.width; height: 44; eventOnly: true; flowing: false
            tone: VisualQuality.preset > 1 ? Theme.green : Theme.strataAccent
            intensity: VisualQuality.effectIntensity * (VisualQuality.preset > 1 ? 1 : .8)
        }
        Item {
            id: effectsSample
            x: 640; y: 300; width: 240; height: 330
            Rectangle { anchors.fill: parent; color: Theme.background }
            CedarHeartwood { id: heart; x: 100; y: 20; size: 44 }
            DropFrame { id: drop; x: 20; y: 130; width: 180; height: 180 }
        }
        property real breathSeen: 0
        property int stage: 0
        property int sizes: 0
        property int frames: 0
        Connections {
            target: core
            function onWindowHeightChanged() { window.sizes++; }
            function onHeightChanged() { window.frames++; }
        }
        function check(ok, message) {
            if (!ok) { console.error("FAIL: " + message); Qt.exit(1); }
        }
        Timer {
            interval: 500; running: true; repeat: true
            onTriggered: {
                switch (window.stage++) {
                case 0:
                    Config.set("reducedMotion", false);
                    window.sizes = 0; window.frames = 0;
                    ShellState.osd("VOLUME", 0.72, "72%");
                    break;
                case 1:
                    // Volume lives inside the pill: it widens smoothly and never grows a second row.
                    window.check(core.height === core.restingHeight, "Volume stays inside the resting pill");
                    window.check(Motion.active, "Ambience is active while motion is allowed");
                    window.check(breath.value > 0.05 && breath.value <= 1, "Breath steps its value without an animator: " + breath.value);
                    window.breathSeen = breath.value;
                    window.check(window.sizes <= 3, "Core does not resize its window each animation frame: " + window.sizes);
                    window.check(core.windowHeight === Math.ceil(core.height) + 2, "Window fits settled Core");
                    window.sizes = 0; window.frames = 0;
                    CoreService.expand();
                    break;
                case 2:
                    window.check(window.frames > 2 && window.sizes <= 3, "Expanded hub animates without per-frame window resize");
                    CoreService.collapse();
                    CoreService.remove("osd", false);
                    ShellState.osdOpen = false;
                    window.sizes = 0; window.frames = 0;
                    break;
                case 3:
                    window.check(window.frames > 2 && window.sizes <= 3, "Collapse retains allocation until settled");
                    window.check(core.windowHeight === core.restingHeight + 2, "Collapse releases unused window area");
                    gauge.grabToImage(r => r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/motion.png"));
                    Config.set("reducedMotion", true);
                    break;
                case 4:
                    window.check(!atmosphere.moving, "Reduced Motion stops ambience");
                    window.check(!Motion.active && !breath.running, "Reduced Motion rests the breath driver");
                    CoreService.expand();
                    break;
                case 5:
                    window.check(core.height === core.implicitHeight, "Reduced Motion uses immediate geometry");
                    window.check(core.windowHeight === Math.ceil(core.height) + 2, "Reduced Motion allocation is correct");
                    ShellState.osdCoreDragging = true;
                    ShellState.osd("VOLUME", 0.6, "60%");
                    break;
                case 6:
                    window.check(CoreService.model.heldId === "osd", "Active interaction holds volume");
                    CoreService.publish({id: "motion-warning", type: "warning", title: "Test", priority: "critical", sticky: true, persistent: true});
                    break;
                case 7:
                    window.check(CoreService.foreground?.id === "motion-warning" && CoreService.model.heldId !== "osd", "Critical preemption releases or transfers volume interaction without a binding loop");
                    ShellState.osdCoreDragging = false;
                    CoreService.remove("motion-warning", false);
                    CoreService.collapse();
                    Config.set("motionPreset", "balanced");
                    Config.set("reducedMotion", false);
                    Config.set("performanceMode", "off");
                    roots.grow(); heart.hovered = true; drop.lit = true;
                    break;
                case 8:
                    window.check(roots.animating && roots.opacity > 0, "Balanced awakening visibly grows the roots");
                    window.check(heart.turn2 > 0 && !heart.animating, "Balanced hover advances and rests while held");
                    roots.grabToImage(r => window.check(r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/strata-balanced.png"), "Saved balanced roots"));
                    break;
                case 9:
                    break;
                case 10:
                    window.check(!roots.animating && roots.opacity === 0, "Event-only roots leave the idle bar clear");
                    window.check(!heart.animating && !drop.animating && drop.runner === -1, "Heartwood and Living Edge settle");
                    Config.set("motionPreset", "expressive");
                    heart.hovered = false; heart.hovered = true; heart.pulse();
                    roots.pulse("centre", Theme.teal); roots.trace(12, 450, Theme.green);
                    drop.lit = false; drop.lit = true;
                    break;
                case 11:
                    window.check(heart.animating && heart.turn3 < 0 && Math.abs(heart.bloom - 1) > .005, "Expressive hover counter-turns and click blooms: " + [heart.animating, heart.turn3, heart.bloom]);
                    window.check(roots.animating && roots.opacity > 0 && roots.traceProgress > 0, "Event pulse and directional trace are visible");
                    effectsSample.grabToImage(r => window.check(r.saveToFile(Quickshell.env("CEDAR_SCREENSHOT_DIR") + "/strata-expressive.png"), "Saved expressive instruments"));
                    break;
                case 12:
                    break;
                case 13:
                    window.check(!roots.animating && roots.opacity === 0 && !heart.animating && !drop.animating, "Expressive decoration has no held-hover or open-panel loop");
                    roots.pulse("centre", Theme.green); heart.pulse();
                    drop.lit = false; drop.lit = true;
                    Config.set("reducedMotion", true);
                    break;
                case 14:
                    window.check(!roots.animating && roots.opacity === 0 && !heart.animating && heart.bloom === 1, "Reduced Motion cancels and resets in-flight instruments");
                    window.check(!drop.animating && drop.runner === -1 && drop.grainReveal === 1, "Reduced Motion completes the grain and removes its tracer");
                    Config.set("reducedMotion", false);
                    Config.set("motionPreset", "off");
                    roots.grow(); heart.pulse(); drop.lit = false; drop.lit = true;
                    break;
                case 15:
                    window.check(!roots.animating && !heart.animating && !drop.animating, "Off ignores new decorative events");
                    Config.set("motionPreset", "balanced");
                    roots.pulse("centre", Theme.teal); heart.pulse(); drop.lit = false; drop.lit = true;
                    roots.visible = false; heart.visible = false; drop.visible = false;
                    break;
                case 16:
                    window.check(!roots.animating && !heart.animating && !drop.animating, "Hidden instruments stop effects already in flight");
                    console.log("PASS: motion allocation, interpolation, vector gauges, finite Strata effects and reduced motion");
                    Qt.quit();
                }
            }
        }
    }
}
