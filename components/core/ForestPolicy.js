.pragma library

function state(s) {
    if (s.warning) return "EMBER";
    if (s.watching) return "WATCH";
    if (s.resting) return "REST";
    if (s.performance) return "HUNT";
    if (s.activities >= 2) return "FLOW";
    if (s.idle && s.cpu >= 0 && s.cpu < .15 && s.activities === 0) return "QUIET";
    return "AWAKE";
}
function trail(rows, entry, now) {
    if (!entry.label || rows[0]?.key === entry.key) return rows;
    return [Object.assign({}, entry, {at: now})].concat(rows).slice(0, 24);
}
function echo(rows, activity, now) {
    if (!activity || !["volume", "brightness", "screenshot", "workspace", "bluetooth"].includes(activity.type)) return rows;
    return [{id:activity.id, icon:activity.icon, type:activity.type, until:now+6000}]
        .concat(rows.filter(r=>r.id!==activity.id && r.until>now)).slice(0, 3);
}
