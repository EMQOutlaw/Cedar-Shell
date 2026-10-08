// node tests/core/diagnostics_test.js components/core/Diagnostics.js
const fs = require("node:fs"), vm = require("node:vm"), assert = require("node:assert/strict");
const lib = vm.createContext({});
vm.runInContext(fs.readFileSync(process.argv[2] || "components/core/Diagnostics.js", "utf8").replace(".pragma library", ""), lib);

// Nothing in, nothing out.
let issues = lib.diagnose({});
assert.equal(issues.length, 0, "no inputs produce no issues");
assert.equal(lib.status(issues), "healthy");
assert.equal(lib.headline("healthy"), "Healthy");

// A failed system service is critical and its action needs privileges; a user one does not.
issues = lib.diagnose({ services: [
    { name: "PipeWire", unit: "pipewire.service", user: true, status: "Failed", detail: "failed · failed · exit-code" },
    { name: "NetworkManager", unit: "NetworkManager.service", user: false, status: "Warning", detail: "inactive · dead · success" },
    { name: "Bluetooth", unit: "bluetooth.service", user: false, status: "Healthy", detail: "active · running · success" }] });
assert.equal(issues.length, 2);
assert.equal(issues[0].id, "service/pipewire.service");
assert.equal(issues[0].severity, "critical");
assert.equal(issues[0].privileged, false, "a user unit restarts without privileges");
assert.equal(issues[0].action.request.action, "restart");
assert.equal(issues[1].severity, "warning");
assert.equal(issues[1].privileged, true, "a system unit needs pkexec");
assert.equal(lib.status(issues), "risk");

// Failed units already covered by the service list are not listed twice.
issues = lib.diagnose({ services: [{ name: "PipeWire", unit: "pipewire.service", user: true, status: "Failed", detail: "" }],
                        failedUnits: [{ unit: "pipewire.service", user: true, description: "PipeWire", result: "failed" }, { unit: "backup.service", user: true, description: "Nightly backup", result: "failed" }] });
assert.equal(issues.filter(i => i.id.includes("pipewire")).length, 1, "deduplicated against the service list");
assert.ok(issues.some(i => i.id === "unit/user/backup.service" && i.severity === "warning"), "an unknown failed user unit is a warning");

// Log: a load failure is critical, a binding error a warning with its count.
issues = lib.diagnose({ logIssues: [{ line: "caused by @shell.qml[58:9]: Type X unavailable", count: 1, kind: "load" }, { line: "@a.qml[1:-1]: ReferenceError: y is not defined", count: 3, kind: "binding" }] });
assert.equal(issues[0].severity, "critical");
assert.ok(issues[1].title.includes("3×"), "count shown in the title");
assert.equal(issues[1].action, null, "no action is invented for a log line");

// Readings: thresholds from the inputs, not from constants.
issues = lib.diagnose({ disk: .95, diskLimit: .9, temperature: 80, temperatureLimit: 85, updates: 12, capabilities: { privilege: { helper: "pkexec", agent: false } }, shellMemoryMb: 1200 });
const ids = issues.map(i => i.id);
assert.ok(ids.includes("disk") && !ids.includes("thermal") && ids.includes("updates") && ids.includes("polkit-agent") && ids.includes("shell-memory"), ids.join());
assert.equal(issues.find(i => i.id === "disk").severity, "warning");
assert.equal(lib.diagnose({ disk: .98, diskLimit: .9 })[0].severity, "critical", "a nearly full disk is critical");
assert.equal(lib.diagnose({ updates: -1 }).length, 0, "updates not checked produce nothing");
assert.equal(lib.diagnose({ disk: -1, diskLimit: .9, temperature: -1, temperatureLimit: 85 }).length, 0, "unknown readings produce nothing");

// Order: critical first, then warnings, then notices; alphabetical within.
issues = lib.diagnose({ updates: 2, disk: .99, diskLimit: .9, config: [{ file: "theme.json", problem: "Not valid JSON" }] });
assert.deepEqual(issues.map(i => i.severity).join(), "critical,warning,notice");
assert.equal(lib.status(issues), "risk");

console.log("PASS: diagnostics engine turns readings into ordered issues with honest actions and privilege flags");
