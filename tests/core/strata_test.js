// node tests/core/strata_test.js components/core/StrataGeometry.js components/core/Kinetic.js
const fs = require("node:fs"), vm = require("node:vm"), assert = require("node:assert/strict");
function load(path) { const ctx = vm.createContext({}); vm.runInContext(fs.readFileSync(path, "utf8").replace(".pragma library", ""), ctx); return ctx; }
const G = load(process.argv[2] || "components/core/StrataGeometry.js");
const K = load(process.argv[3] || "components/core/Kinetic.js");

// ---- geometry: anchors left, centre, right; clamping; scaling-independent logical units
const bar = 2560, avail = 1400;
let t = G.target({ barWidth: bar, anchor: null, wantedWidth: 420, wantedHeight: 660, availableHeight: avail, sideInset: 0 });
assert.equal(t.x, Math.round(bar / 2 - 210), "no anchor centres on the screen");
assert.equal(t.origin, -1, "no origin without an anchor");
t = G.target({ barWidth: bar, anchor: { x: 60, width: 40 }, wantedWidth: 520, wantedHeight: 700, availableHeight: avail, sideInset: 0 });
assert.equal(t.x, 12, "a control at the far left pins the panel to the left edge");
assert.equal(t.origin, 80 - 12, "the tie line points at the control's centre inside the panel");
t = G.target({ barWidth: bar, anchor: { x: bar - 50, width: 30 }, wantedWidth: 520, wantedHeight: 700, availableHeight: avail, sideInset: 0 });
assert.equal(t.x, bar - 520 - 12, "a control at the far right pins the panel to the right edge");
t = G.target({ barWidth: bar, anchor: { x: 1200, width: 40 }, wantedWidth: 400, wantedHeight: 700, availableHeight: avail, sideInset: 12 });
assert.equal(t.x, Math.round(1220 - 12 - 200), "a detached bar's side inset shifts the centre");
t = G.target({ barWidth: 800, anchor: null, wantedWidth: 1040, wantedHeight: 900, availableHeight: 500, sideInset: 0 });
assert.equal(t.width, 800 - 24, "a wide panel is clamped to the bar with the edge free");
assert.equal(t.height, 500, "height is clamped to what fits under the bar");
assert.equal(G.target({ barWidth: 800, anchor: null, wantedWidth: 400, wantedHeight: 40, availableHeight: 500, sideInset: 0 }).height, 160, "a tiny panel keeps the minimum");

// ---- retargeting: same origin morphs in place, a different control folds back
const quick = G.target({ barWidth: bar, anchor: { x: 1260, width: 150 }, wantedWidth: 420, wantedHeight: 660, availableHeight: avail, sideInset: 0 });
const calendar = G.target({ barWidth: bar, anchor: { x: 1260, width: 150 }, wantedWidth: 520, wantedHeight: 700, availableHeight: avail, sideInset: 0 });
const bell = G.target({ barWidth: bar, anchor: { x: 2480, width: 32 }, wantedWidth: 400, wantedHeight: 700, availableHeight: avail, sideInset: 0 });
assert.equal(G.sharesOrigin(quick, calendar), true, "two tabs from the pill share an origin");
assert.equal(G.sharesOrigin(quick, bell), false, "the bell is a different origin");
assert.equal(G.progress({ height: 0 }, { height: 600 }, 150), .25);
assert.equal(G.progress({ height: 600 }, { height: 600 }, 600), 1, "no travel is complete");

// ---- kinetic: relay safety, the plan, style choice, compression, rate limit
assert.equal(K.relayable("BALANCED", "GAMING"), true);
assert.equal(K.relayable("CONNECTING", "CONNECTED"), true);
assert.equal(K.relayable("Café", "Cafe"), true, "Latin-1 letters are single graphemes");
assert.equal(K.relayable("é", "e"), false, "a combining mark is not relayed");
assert.equal(K.relayable("🙂 on", "🙂 off"), false, "emoji falls back");
assert.equal(K.relayable("שלום", "שלומי"), false, "right-to-left falls back");
assert.equal(K.relayable("A rather long window title here", "A rather long window title there"), false, "long text falls back");
assert.equal(K.relayable("same", "same"), false, "no change, no relay");
let plan = K.relay("CONNECTING", "CONNECTED");
assert.deepEqual([plan.prefix, plan.leaving, plan.arriving, plan.suffix], ["CONNECT", "ING", "ED", ""]);
plan = K.relay("FOCUS", "PAUSED");
assert.deepEqual([plan.prefix, plan.leaving, plan.arriving, plan.suffix], ["", "FOCUS", "PAUSED", ""], "no shared suffix when the last letters differ");
plan = K.relay("PAUSED", "RESUMED");
assert.deepEqual([plan.prefix, plan.leaving, plan.arriving, plan.suffix], ["", "PAUS", "RESUM", "ED"]);
plan = K.relay("PROTECTED", "ATTENTION");
assert.deepEqual([plan.prefix, plan.leaving, plan.arriving, plan.suffix], ["", "PROTECTED", "ATTENTION", ""]);
assert.equal(K.choose("relay", "BALANCED", "GAMING", 16, false), "relay");
assert.equal(K.choose("relay", "🙂", "🙁", 16, false), "resolve", "an unsafe relay resolves instead");
assert.equal(K.choose("relay", "A", "B", 16, true), "none", "Reduced Motion is static");
assert.equal(K.choose("fade", "A", "A", 16, false), "none", "no change is static");
assert.equal(K.choose("anything", "A", "B", 16, false), "fade", "unknown styles fade");
const widths = { "Performance Profile": 160, "Performance": 90, "P": 10 };
assert.equal(K.fit(["Performance Profile", "Performance", "P"], 200, v => widths[v]), "Performance Profile");
assert.equal(K.fit(["Performance Profile", "Performance", "P"], 100, v => widths[v]), "Performance");
assert.equal(K.fit(["Performance Profile", "Performance", "P"], 5, v => widths[v]), "P", "the shortest variant is the floor");
assert.equal(K.allowed(1000, 1500, 800), false, "a second change within the window is static");
assert.equal(K.allowed(1000, 2000, 800), true);

console.log("PASS: strata geometry (anchors, clamping, retarget origin) and kinetic type policy (relay safety, plans, styles, compression, rate limit)");
