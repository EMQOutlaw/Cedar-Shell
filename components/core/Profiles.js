.pragma library

// Desktop Profiles: what each profile asks for, as typed operations over the
// providers CEDAR already drives. Pure data and merge logic; the Profiles
// service applies, verifies and restores. Values are what the profile wants;
// `null` or an absent key means "leave it alone".
//
// Operations (key → provider):
//   power        power-profiles-daemon through Controls      "power-saver" | "balanced" | "performance"
//   dnd          Config doNotDisturb (CEDAR's own popups)     bool
//   idleLock     Config idleLockSeconds                       seconds, 0 = never
//   nightlight   hyprsunset / Omarchy through Controls        bool
//   ambient      Config ambientIntensity                      0 … 1
//   performance  Config performanceMode (VisualQuality)      "auto" | "on" | "off"
//   whispers     Config forestWhispers                        bool
//   audioScene   a saved Audio Scene by name                  string

var ops = {
    power:       { label: "Power profile",    hud: "Power profile",       kind: "choice", options: [{ value: "power-saver", label: "Power saver" }, { value: "balanced", label: "Balanced" }, { value: "performance", label: "Performance" }] },
    dnd:         { label: "Do not disturb",   hud: "Notifications",       kind: "bool" },
    idleLock:    { label: "Lock after",       hud: "Idle lock",           kind: "choice", options: [{ value: 0, label: "Never" }, { value: 300, label: "5 min" }, { value: 600, label: "10 min" }, { value: 1800, label: "30 min" }] },
    nightlight:  { label: "Night light",      hud: "Night light",         kind: "bool" },
    ambient:     { label: "Ambient effects",  hud: "Desktop appearance",  kind: "choice", options: [{ value: 0, label: "Off" }, { value: .25, label: "Low" }, { value: .45, label: "Normal" }, { value: .8, label: "High" }] },
    performance: { label: "Performance mode", hud: "Visual quality",      kind: "choice", options: [{ value: "auto", label: "Auto" }, { value: "on", label: "On" }, { value: "off", label: "Off" }] },
    whispers:    { label: "Whispers",         hud: "Background activity", kind: "bool" },
    audioScene:  { label: "Audio scene",      hud: "Audio scene",         kind: "scene" }
};
var order = ["power", "dnd", "idleLock", "nightlight", "ambient", "performance", "whispers", "audioScene"];
// Config keys behind the in-process operations.
var configKeys = { dnd: "doNotDisturb", idleLock: "idleLockSeconds", ambient: "ambientIntensity", performance: "performanceMode", whispers: "forestWhispers" };
// Accents are theme tokens, never literals; "moss" is derived by the service.
var accents = ["green", "teal", "moss", "blue", "violet", "amber", "brightGreen"];

var catalog = [
    { id: "balanced", label: "Balanced", line: "The everyday desktop: nothing held, nothing quieted.", accent: "green",
      ops: { power: "balanced", dnd: false, performance: "auto", whispers: true } },
    { id: "work", label: "Work", line: "Notifications wait, the flair rests, the desktop stays out of the way.", accent: "teal",
      ops: { dnd: true, performance: "on", whispers: false, power: "balanced" } },
    { id: "battery", label: "Battery", line: "Stretch the charge: power saver, a short idle lock, no ambience.", accent: "moss",
      ops: { power: "power-saver", idleLock: 300, performance: "on", ambient: 0, whispers: false } },
    { id: "night", label: "Night", line: "Warm light and a quiet desktop for the evening.", accent: "blue",
      ops: { nightlight: true, dnd: true, ambient: .25, whispers: false } },
    { id: "gaming", label: "Gaming", line: "The desktop quiets itself around the game and restores everything after.", accent: "brightGreen", gaming: true },
    { id: "custom", label: "Custom", line: "Your own set of changes.", accent: "green", ops: {}, editable: true }
];

function clone(value) { return JSON.parse(JSON.stringify(value)); }

// The catalog with the user's Custom definition merged in. `user` is the
// parsed profiles.json: { custom: { ops: {…}, accent: "teal" } }.
function definitions(user) {
    var rows = clone(catalog);
    var custom = user && user.custom && typeof user.custom === "object" ? user.custom : {};
    for (var i = 0; i < rows.length; ++i) {
        if (!rows[i].editable) continue;
        rows[i].ops = sanitizeOps(custom.ops || {});
        if (accents.indexOf(custom.accent) >= 0) rows[i].accent = custom.accent;
    }
    return rows;
}

// Keep only known operations with values of the right type.
function sanitizeOps(raw) {
    var out = {};
    for (var key in ops) {
        if (!(key in raw) || raw[key] === null || raw[key] === undefined) continue;
        var op = ops[key], value = raw[key];
        if (op.kind === "bool" && typeof value === "boolean") out[key] = value;
        else if (op.kind === "choice" && op.options.some(function (o) { return o.value === value; })) out[key] = value;
        else if (op.kind === "scene" && typeof value === "string" && value.length > 0 && value.length <= 60) out[key] = value;
    }
    return out;
}

function definition(rows, id) { for (var i = 0; i < rows.length; ++i) if (rows[i].id === id) return rows[i]; return null; }

// [{key, value}] in registry order for the operations a profile sets.
function managed(def) {
    var out = [];
    if (!def || !def.ops) return out;
    for (var i = 0; i < order.length; ++i) { var key = order[i]; if (key in def.ops && def.ops[key] !== null && def.ops[key] !== undefined) out.push({ key: key, value: def.ops[key] }); }
    return out;
}

// A short human line for one operation's value.
function describe(key, value) {
    var op = ops[key];
    if (!op) return String(value);
    if (op.kind === "bool") return value ? "on" : "off";
    if (op.kind === "choice") { for (var i = 0; i < op.options.length; ++i) if (op.options[i].value === value) return op.options[i].label.toLowerCase(); return String(value); }
    return String(value);
}
