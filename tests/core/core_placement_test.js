// node tests/core/core_placement_test.js components/core/StrataGeometry.js
// Where the Core pill's window sits. Production note: the pill is Strata
// (top-bar) ONLY — under the Understory (left) bar no pill exists at all
// (CoreHost's model, CoreService.available and Dictation.presenter all require
// !Config.barVertical; see SurfacePolicyHarness/CoveredCoreHarness/HostHarness).
// The floating branch below is therefore dormant, kept correct and tested in
// case a future placement needs it: it docks the pill just beside the bar with
// a small gutter and centres it vertically on the output.
const fs = require("fs"), vm = require("vm"), assert = require("assert");
const p = {}; vm.createContext(p);
vm.runInContext(fs.readFileSync(process.argv[2] || "components/core/StrataGeometry.js", "utf8").replace(".pragma library", ""), p);

function place(o) { return p.corePlacement(Object.assign({ screenWidth: 1920, screenHeight: 1080, barVertical: false, barWidth: 0, barMargin: 12, barDetached: false, barInset: 5, barHeight: 44, wantedWidth: 620 }, o)); }

// Top bar (Strata default): centred on the monitor, under the bar frame, unchanged.
let r = place({});
assert.strictEqual(r.left, Math.round((1920 - 620) / 2), "top bar centres on the whole monitor");
assert.strictEqual(r.top, 5, "integrated pill sits at the bar inset");
assert.strictEqual(r.width, 620);
assert.strictEqual(r.maxHeight, 1080 - 44 - 60, "max height exactly as the integrated pill always had it");

// Dormant floating branch: docked immediately beside the bar, vertically centred.
r = place({ barVertical: true, barWidth: 44 });
assert.strictEqual(r.left, 44 + 4, "floating pill docks just beside the bar, not centred across the usable width");
assert.strictEqual(r.width, 620);
assert.strictEqual(r.top, Math.round((1080 - 40) / 2), "floating pill is vertically centred using the default resting height (40)");
assert.ok(r.top !== 5, "the old top-anchored placement is gone");
assert.strictEqual(r.maxHeight, 1080 - r.top, "the box still ends inside the output");
// restingHeight is an input: a taller resting pill centres accordingly.
r = place({ barVertical: true, barWidth: 44, restingHeight: 60 });
assert.strictEqual(r.top, Math.round((1080 - 60) / 2), "resting height moves the centred top edge");
r = place({ barVertical: true, barWidth: 44, restingHeight: 0 });
assert.strictEqual(r.top, 520, "a zero/absent resting height degrades to the default 40");
r = place({ barVertical: true, barWidth: 44, restingHeight: NaN });
assert.strictEqual(r.top, 520, "non-finite resting height degrades to the default");

// Detached bar keeps its margin: on top for Strata, beside for the left bar.
r = place({ barDetached: true });
assert.strictEqual(r.top, 12 + 5, "detached top bar adds its margin");
r = place({ barVertical: true, barWidth: 44, barDetached: true });
assert.strictEqual(r.left, 44 + 12 + 4, "detached left bar reserves its margin, then docks");
r = place({ barVertical: true, barWidth: 44, barDetached: true, restingHeight: 40 });
assert.strictEqual(r.top, Math.round((1080 - 40) / 2), "detached left bar does not offset the centred top edge");

// Narrow / portrait / fractional displays.
r = place({ screenWidth: 600, barVertical: true, barWidth: 44 });
assert.strictEqual(r.width, 600 - 44 - 4, "floating width keeps one gutter beside the bar");
assert.strictEqual(r.left, 44 + 4, "starts just inside the bar");
r = place({ screenWidth: 1080, screenHeight: 1920, barVertical: true, barWidth: 56 });
assert.ok(r.left + r.width <= 1080, "portrait: inside the monitor");
r = place({ screenWidth: 1706.67, barVertical: true, barWidth: 44 });
assert.ok(Number.isInteger(r.left) && Number.isInteger(r.width) && Number.isInteger(r.top), "fractional scale yields integer pixels");
r = place({ screenWidth: 0, screenHeight: 0 });
assert.ok(r.width > 0 && r.maxHeight >= 200 && r.left >= 0 && r.top >= 0, "missing screen metrics degrade to sane defaults");
r = place({ screenWidth: NaN, screenHeight: undefined, barWidth: NaN, barVertical: true });
assert.ok([r.left, r.top, r.width, r.maxHeight].every(Number.isFinite), "non-finite inputs never leak");

// Top Strata geometry is exact: a narrow monitor gets the old min(620, width), no gutter.
r = place({ screenWidth: 600 });
assert.strictEqual(r.width, 600, "integrated pill keeps the historical min(620, monitor width)");
assert.strictEqual(r.left, 0, "and the historical centring");
// Tiny outputs: both dimensions clamp to what exists; no minimum is forced beyond the available space.
r = place({ screenWidth: 300, screenHeight: 200 });
assert.strictEqual(r.maxHeight, 200 - 44, "a 200px-tall output cannot promise 200px under its bar: it gives what remains");
assert.ok(r.width <= 300, "width within a 300px output");
r = place({ screenWidth: 300, screenHeight: 200, barVertical: true, barWidth: 44 });
assert.ok(r.left + r.width <= 300 && r.width > 0, "floating pill fits a 300px output beside its bar");
assert.strictEqual(r.maxHeight, 200 - r.top, "tiny floating output: the 200px floor applies but the box still ends inside the output");
r = place({ screenWidth: 300, screenHeight: 50, barVertical: true, barWidth: 44 });
assert.strictEqual(r.maxHeight, 50 - r.top, "...and dropped when even that does not fit, still ending inside the output");
r = place({ screenWidth: 40, barVertical: true, barWidth: 44 });
assert.ok(r.width >= 1 && r.left >= 0 && Number.isFinite(r.left), "a bar wider than the output still yields a finite, positive box");
assert.ok(r.left + r.width <= 40, "...and never extends past the output's right edge (" + JSON.stringify(r) + ")");

// Bounds hold on every output: left+width within the width, top+maxHeight within the height.
for (const o of [
    { screenWidth: 44, screenHeight: 44, barVertical: true, barWidth: 44 },
    { screenWidth: 100, screenHeight: 30, barVertical: true, barWidth: 44, barDetached: true, barMargin: 32 },
    { screenWidth: 100, screenHeight: 30 },
    { screenWidth: 640, screenHeight: 200, barVertical: true, barWidth: 72, barDetached: true, barMargin: 32, barInset: 0 },
    { screenWidth: 1, screenHeight: 1, barVertical: true, barWidth: 72 },
    { screenWidth: 1, screenHeight: 1 },
    { screenWidth: 3840, screenHeight: 2160, barVertical: true, barWidth: 44 }
]) {
    const q = place(o);
    assert.ok(q.left >= 0 && q.width >= 1 && q.left + q.width <= Math.max(1, o.screenWidth), "within width: " + JSON.stringify(o) + " -> " + JSON.stringify(q));
    assert.ok(q.top >= 0 && q.maxHeight >= 1 && q.top + q.maxHeight <= Math.max(1, o.screenHeight), "within height: " + JSON.stringify(o) + " -> " + JSON.stringify(q));
}

// Vertical centring is honoured wherever the output can hold it, and degrades
// to zero — never negative — on an output shorter than the resting pill.
r = place({ barVertical: true, barWidth: 44, screenHeight: 720 });
assert.strictEqual(r.top, Math.round((720 - 40) / 2), "centred on a 720px output");
r = place({ barVertical: true, barWidth: 44, screenHeight: 20 });
assert.strictEqual(r.top, 0, "an output shorter than the resting pill centres to 0, never negative");
r = place({ barVertical: true, barWidth: 44, screenHeight: 40 });
assert.strictEqual(r.top, 0, "exactly the resting height centres to 0");

// Integrated zero-inset stays flush; the floating branch no longer claims a top gutter.
r = place({ barVertical: false, barInset: 0 });
assert.strictEqual(r.top, 0, "integrated pill with a zero inset stays flush, as before");
r = place({ barVertical: true, barWidth: 44, barInset: 0 });
assert.strictEqual(r.top, Math.round((1080 - 40) / 2), "floating top comes from centring, not from the bar inset");

// Exhaustive sweep: every combination of output size, placement, bar width,
// detached margin and frame inset keeps the box inside the output.
{
    let combos = 0;
    for (const w of [1, 40, 44, 100, 300, 640, 1080, 1920, 3840])
        for (const h of [1, 30, 50, 200, 720, 1080, 2160])
            for (const v of [false, true])
                for (const bw of [0, 44, 72, 200])
                    for (const det of [false, true])
                        for (const ins of [0, 5]) {
                            const q = place({ screenWidth: w, screenHeight: h, barVertical: v, barWidth: bw, barMargin: 32, barDetached: det, barInset: ins });
                            const tag = JSON.stringify({ w, h, v, bw, det, ins }) + " -> " + JSON.stringify(q);
                            assert.ok(q.left >= 0 && q.width >= 1 && q.left + q.width <= w, "inside width " + tag);
                            assert.ok(q.top >= 0 && q.maxHeight >= 1 && q.top + q.maxHeight <= h, "inside height " + tag);
                            assert.ok([q.left, q.top, q.width, q.maxHeight].every(Number.isInteger), "integer pixels " + tag);
                            if (v) {
                                const reserved = bw + (det ? 32 : 0);
                                const usable = Math.max(0, w - reserved);
                                const gutter = usable > 16 ? 4 : 0;
                                const docked = Math.round(reserved + gutter);
                                if (docked + q.width <= w) assert.strictEqual(q.left, docked, "docks at the bar edge " + tag);
                                else assert.strictEqual(q.left, Math.max(0, w - q.width), "no room: clamped to the right edge " + tag);
                                assert.ok(q.top <= Math.max(0, Math.round((h - 40) / 2)) + 0, "centred or clamped down " + tag);
                            } else {
                                assert.strictEqual(q.left, Math.round((w - q.width) / 2), "integrated centring " + tag);
                            }
                            combos++;
                        }
    assert.strictEqual(combos, 2016);
}

// Top bar ignores barWidth even if a stale value is passed.
r = place({ barVertical: false, barWidth: 44 });
assert.strictEqual(r.left, Math.round((1920 - 620) / 2), "a horizontal bar reserves no width");

console.log("PASS: core placement (integrated Strata geometry exact; dormant floating branch docked beside the bar and vertically centred; margins, clamps)");
