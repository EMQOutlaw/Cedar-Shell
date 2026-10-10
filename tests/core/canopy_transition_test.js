// Execute the production transition commands without a compositor. This checks
// cancellation and retained geometry; it does not measure QML interpolation.
// Run: node tests/core/canopy_transition_test.js
const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

const source = fs.readFileSync(path.join(__dirname, "../../modules/CanopyWindow.qml"), "utf8");
function command(name) {
    const start = source.indexOf("function " + name + "(");
    assert.notEqual(start, -1, "production command exists: " + name);
    const brace = source.indexOf("{", start);
    let depth = 1, end = brace + 1;
    while (depth && end < source.length) {
        if (source[end] === "{") depth++;
        if (source[end] === "}") depth--;
        end++;
    }
    assert.equal(depth, 0, "complete production command: " + name);
    return source.slice(start, end);
}
function fixture(mapped, height, reveal) {
    const calls = [], deferred = [];
    const animation = name => ({
        stop() { calls.push(name + ":stop"); },
        restart() { calls.push(name + ":restart"); }
    });
    const context = {
        mapped, switching: false,
        drop: { height, reveal, x: 36, width: 400, topic: "audio", standalone: false },
        Canopy: { topic: "audio", standalone: false, enter() { calls.push("enter"); } },
        root: { requested: true, retarget() { calls.push("retarget"); } },
        Qt: { callLater(fn) { deferred.push(fn); } },
        closeDelay: animation("closeDelay"), openReveal: animation("openReveal"),
        swap: animation("swap"), morph: animation("morph"),
        topicWidth() { return 560; }, topicX() { return 80; },
        setState(value) { calls.push("state:" + value); },
        snap(x, width, height) { Object.assign(context.drop, { x, width, height }); calls.push("snap"); }
    };
    vm.createContext(context);
    vm.runInContext(command("open"), context);
    return { context, calls, flush() { deferred.splice(0).forEach(fn => fn()); } };
}

const first = fixture(false, 0, 0);
first.context.open();
assert.equal(first.context.mapped, true);
assert.equal(first.context.drop.height, 0);
assert.equal(first.calls.filter(c => c === "snap").length, 1);
first.flush();
assert(first.calls.includes("retarget") && first.calls.includes("openReveal:restart"));

const interrupted = fixture(true, 247, .42);
interrupted.context.open();
assert.equal(interrupted.context.drop.height, 247, "reopen retains the in-flight height");
assert.equal(interrupted.context.drop.reveal, .42, "reopen retains the in-flight content opacity");
assert.equal(interrupted.context.drop.x, 36, "reopen does not teleport the visible surface");
assert(!interrupted.calls.includes("snap"));
interrupted.flush();
assert(interrupted.calls.includes("retarget"));

const cancelled = fixture(false, 0, 0);
cancelled.context.open();
cancelled.context.root.requested = false;
cancelled.flush();
assert(!cancelled.calls.includes("retarget"), "a close cancels deferred opening");
assert(!cancelled.calls.includes("openReveal:restart"));
assert(!cancelled.calls.includes("enter"));

console.log("PASS: Canopy initial open, interrupted reopen and deferred-close cancellation");
