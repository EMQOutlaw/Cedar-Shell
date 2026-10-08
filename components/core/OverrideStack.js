.pragma library

// Who owns a managed desktop value right now, and what it goes back to.
//
// A Desktop Profile, Focus and Gaming Mode may each change the same setting
// (do-not-disturb, the power profile, ambient intensity). Each owner holds
// the key with the value it found and the value it applied. Releases nest
// correctly in any order: releasing the top owner restores its `previous`;
// releasing an owner underneath hands its `previous` to the owner above, so
// the original value still comes back when the last owner lets go.
//
// A manual change while a key is held is recorded against the top holder as
// an override: that holder's release then restores nothing, because the user
// chose the current value on purpose. Pure functions over a plain object;
// the Overrides service keeps the state.

function create() { return { keys: {} }; }

function stack(state, key) { return (state.keys[key] || []).slice(); }

function holder(state, key) { const s = state.keys[key] || []; return s.length ? s[s.length - 1].owner : ""; }

function held(state, key, owner) { return (state.keys[key] || []).some(e => e.owner === owner); }

function entry(state, key, owner) { return (state.keys[key] || []).find(e => e.owner === owner) || null; }

function withKey(state, key, rows) {
    const keys = Object.assign({}, state.keys);
    if (rows.length) keys[key] = rows; else delete keys[key];
    return { keys: keys };
}

// `owner` takes `key`, which was `previous` and is now `value`. Holding a key
// again updates the applied value and keeps the original `previous`.
function hold(state, key, owner, previous, value) {
    if (!key || !owner) throw new Error("hold needs a key and an owner");
    const rows = stack(state, key), at = rows.findIndex(e => e.owner === owner);
    if (at >= 0) { rows[at] = Object.assign({}, rows[at], { value: value, overridden: false }); return withKey(state, key, rows); }
    rows.push({ owner: owner, previous: previous, value: value, overridden: false });
    return withKey(state, key, rows);
}

// The value `key` currently shows changed outside every owner. The top holder
// is marked overridden; its release leaves the user's choice alone.
function external(state, key, current) {
    const rows = stack(state, key);
    if (!rows.length) return state;
    const top = rows[rows.length - 1];
    if (top.value === current) return state;
    rows[rows.length - 1] = Object.assign({}, top, { overridden: true, value: current });
    return withKey(state, key, rows);
}

// `owner` lets go of `key`. Returns {state, restore, target, reason}:
//   restore  true when the caller should write `target` back now
//   reason   "top" | "nested" | "overridden" | "none"
function release(state, key, owner) {
    const rows = stack(state, key), at = rows.findIndex(e => e.owner === owner);
    if (at < 0) return { state: state, restore: false, target: undefined, reason: "none" };
    const mine = rows[at];
    rows.splice(at, 1);
    if (at === rows.length) {
        // Top of the stack: the value goes back to what this owner found,
        // unless the user changed it meanwhile.
        return { state: withKey(state, key, rows), restore: !mine.overridden, target: mine.previous, reason: mine.overridden ? "overridden" : "top" };
    }
    // Someone above still holds it: they inherit what this owner found.
    rows[at] = Object.assign({}, rows[at], { previous: mine.previous });
    return { state: withKey(state, key, rows), restore: false, target: undefined, reason: "nested" };
}

// Every key `owner` holds, for a bulk release.
function keysHeldBy(state, owner) { return Object.keys(state.keys).filter(k => held(state, k, owner)); }
