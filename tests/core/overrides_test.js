// node tests/core/overrides_test.js components/core/OverrideStack.js
const fs = require("node:fs"), vm = require("node:vm"), assert = require("node:assert/strict");
const lib = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2] || "components/core/OverrideStack.js", "utf8").replace(".pragma library", ""), lib);

let s = lib.create();
assert.strictEqual(lib.holder(s, "dnd"), "", "nothing held at first");

// One owner: hold and release restores the previous value.
s = lib.hold(s, "dnd", "profile", false, true);
assert.strictEqual(lib.holder(s, "dnd"), "profile");
let r = lib.release(s, "dnd", "profile");
assert.deepStrictEqual([r.restore, r.target, r.reason], [true, false, "top"], "top release restores previous");
assert.strictEqual(lib.holder(r.state, "dnd"), "", "key dropped when nobody holds it");

// Nested in order: profile then focus; focus releases first, then profile.
s = lib.create();
s = lib.hold(s, "dnd", "profile", false, true);
s = lib.hold(s, "dnd", "focus", true, true);
r = lib.release(s, "dnd", "focus");
assert.deepStrictEqual([r.restore, r.target], [true, true], "focus goes back to the profile's value");
r = lib.release(r.state, "dnd", "profile");
assert.deepStrictEqual([r.restore, r.target], [true, false], "profile goes back to the original");

// Nested out of order: profile ends while focus still holds the key.
s = lib.create();
s = lib.hold(s, "power", "profile", "balanced", "performance");
s = lib.hold(s, "power", "focus", "performance", "power-saver");
r = lib.release(s, "power", "profile");
assert.deepStrictEqual([r.restore, r.reason], [false, "nested"], "an owner underneath restores nothing now");
assert.strictEqual(lib.holder(r.state, "power"), "focus", "focus still owns it");
r = lib.release(r.state, "power", "focus");
assert.deepStrictEqual([r.restore, r.target], [true, "balanced"], "the last owner restores the original, not the profile's value");

// A manual change while held is respected on release.
s = lib.create();
s = lib.hold(s, "ambientIntensity", "profile", .45, 0);
s = lib.external(s, "ambientIntensity", .8);
assert.strictEqual(lib.entry(s, "ambientIntensity", "profile").overridden, true, "external change marks the top holder overridden");
r = lib.release(s, "ambientIntensity", "profile");
assert.deepStrictEqual([r.restore, r.reason], [false, "overridden"], "an overridden value is left alone");

// An external write of the value the owner itself applied is not an override.
s = lib.create();
s = lib.hold(s, "dnd", "profile", false, true);
s = lib.external(s, "dnd", true);
assert.strictEqual(lib.entry(s, "dnd", "profile").overridden, false, "re-applying the held value is not a manual change");

// Holding again keeps the original previous and refreshes the value.
s = lib.create();
s = lib.hold(s, "idleLockSeconds", "profile", 1800, 300);
s = lib.hold(s, "idleLockSeconds", "profile", 300, 600);
r = lib.release(s, "idleLockSeconds", "profile");
assert.deepStrictEqual([r.target], [1800], "re-hold keeps the first previous");

// Releasing something never held is a no-op.
r = lib.release(lib.create(), "dnd", "focus");
assert.deepStrictEqual([r.restore, r.reason], [false, "none"]);

// Bulk listing.
s = lib.create();
s = lib.hold(s, "dnd", "focus", false, true);
s = lib.hold(s, "forestWhispers", "focus", true, false);
s = lib.hold(s, "power", "profile", "balanced", "performance");
assert.equal(lib.keysHeldBy(s, "focus").sort().join(), "dnd,forestWhispers");

console.log("PASS: override stack holds, nests in any order, respects manual changes and releases");
