.pragma library
// Reconcile by semantic ID. Unchanged rows keep their QML delegates and focus.
function reconcile(model, rows, key) {
    const ids = new Set(rows.map(row => row[key]));
    for (let i = model.count - 1; i >= 0; --i)
        if (!ids.has(model.get(i)[key])) model.remove(i);
    for (let i = 0; i < rows.length; ++i) {
        const row = rows[i];
        let at = i;
        while (at < model.count && model.get(at)[key] !== row[key]) ++at;
        if (at === model.count) model.insert(i, row);
        else {
            if (at !== i) model.move(at, i, 1);
            for (const role of Object.keys(row))
                if (model.get(i)[role] !== row[role]) model.setProperty(i, role, row[role]);
        }
    }
}
