.pragma library

// CEDAR Station's diagnostics engine. Pure: takes what the collectors read
// and returns issues, each saying what happened, why it matters, what CEDAR
// could verify, the action on offer and whether it needs elevated privileges.
// Nothing here guesses; an input that is missing produces no issue.
//
// input = {
//   services:     [{name, unit, user, status, detail}]          (SettingsInfo)
//   failedUnits:  [{unit, user, description, result}]          (station.py)
//   logIssues:    [{line, count, kind}]                         (station.py, redacted)
//   config:       [{file, problem}]                             (station.py)
//   disk:         0 … 1 or -1                                   (SystemStats)
//   diskLimit:    0 … 1                                         (Config coreDiskLimit / 100)
//   temperature:  °C or -1                                      (SystemStats)
//   temperatureLimit: °C                                        (Config coreTemperatureLimit)
//   updates:      count or -1 when not checked                  (CoreService.packages)
//   capabilities: {privilege:{helper, agent}, power:{provider}} (Capabilities)
//   shellMemoryMb: number or -1                                 (Station's /proc read)
//   visualQuality: "normal" | "efficient" | "gaming"
// }
// severity: "critical" | "warning" | "notice"

function issue(id, severity, title, what, why, verify, action, privileged) {
    return { id: id, severity: severity, title: title, what: what, why: why, verify: verify, action: action || null, privileged: !!privileged };
}

function fromServices(input) {
    const out = [];
    for (const s of input.services || []) {
        if (s.status === "Failed")
            out.push(issue("service/" + s.unit, "critical", s.name + " has failed",
                "systemd reports " + s.unit + " failed: " + s.detail + ".",
                "CEDAR depends on it; what it provides (audio, networking, Bluetooth, portals) is unavailable until it runs again.",
                "The unit's load, active and sub state from `systemctl show`; the last 60 journal lines are available under Logs.",
                { label: "Restart " + s.name, request: { action: "restart", unit: s.unit, user: !!s.user } }, !s.user));
        else if (s.status === "Warning")
            out.push(issue("service/" + s.unit, "warning", s.name + " is not active",
                s.unit + " is loaded but " + s.detail + ".",
                "It may be starting, stopped on purpose, or stuck; CEDAR cannot tell which from the state alone.",
                "The unit's state from `systemctl show`.",
                { label: "Restart " + s.name, request: { action: "restart", unit: s.unit, user: !!s.user } }, !s.user));
    }
    return out;
}

function fromFailedUnits(input) {
    const known = new Set((input.services || []).map(s => s.unit));
    return (input.failedUnits || []).filter(u => !known.has(u.unit)).map(u =>
        issue("unit/" + (u.user ? "user/" : "system/") + u.unit, u.user ? "warning" : "critical", u.unit + " failed",
            (u.description || u.unit) + " ended with result " + (u.result || "failed") + ".",
            u.user ? "A user service that failed stays failed until it is reset or restarted; whatever it did for your session is not happening." : "A system service that failed may affect every user; CEDAR can only read its state.",
            "Listed by `systemctl " + (u.user ? "--user " : "") + "--failed`.",
            { label: "Restart " + u.unit, request: { action: "restart", unit: u.unit, user: !!u.user } }, !u.user));
}

function fromLog(input) {
    const out = [];
    for (const l of input.logIssues || []) {
        if (l.kind === "load")
            out.push(issue("log/load", "critical", "The shell refused a configuration",
                l.line, "A load failure means the previous shell state is still running and the edited one never took; the live desktop and the files on disk disagree.",
                "The ERROR lines in ~/.local/state/cedar/shell.log since the last launch.", null, false));
        else if (l.kind === "binding")
            out.push(issue("log/binding/" + l.line.slice(0, 40), "warning", "A QML binding errored" + (l.count > 1 ? " (" + l.count + "×)" : ""),
                l.line, "A property that errors is left at its previous value, so a control may show the wrong state without saying so.",
                "The warning as the shell logged it; the component and line are in the text.", null, false));
    }
    return out;
}

function fromConfig(input) {
    return (input.config || []).map(c => issue("config/" + c.file, "warning", c.file + " has a problem",
        c.problem, "CEDAR falls back to defaults for what it cannot read; your preference in that file is not applied.",
        "The file was parsed on this read; the message is the parser's.", null, false));
}

function fromReadings(input) {
    const out = [];
    if (typeof input.disk === "number" && input.disk >= 0 && typeof input.diskLimit === "number" && input.disk >= input.diskLimit)
        out.push(issue("disk", input.disk >= .97 ? "critical" : "warning", "Disk is " + Math.round(input.disk * 100) + "% full",
            "The configured filesystem has " + Math.round((1 - input.disk) * 100) + "% free.",
            "A full disk stops updates, downloads and saves; some services fail quietly first.",
            "Usage from `df` on the path chosen in Settings › CEDAR Core.", null, false));
    if (typeof input.temperature === "number" && input.temperature >= 0 && typeof input.temperatureLimit === "number" && input.temperature >= input.temperatureLimit)
        out.push(issue("thermal", "warning", "Temperature is " + Math.round(input.temperature) + " °C",
            "The system temperature sensor reads at or above the limit of " + input.temperatureLimit + " °C.",
            "Sustained heat throttles the processor and shortens hardware life.",
            "The hwmon sensor CEDAR already samples; it is not labelled CPU-only.", null, false));
    if (typeof input.updates === "number" && input.updates > 0)
        out.push(issue("updates", "notice", input.updates + " repository " + (input.updates === 1 ? "update" : "updates") + " available",
            "`checkupdates` lists " + input.updates + " package" + (input.updates === 1 ? "" : "s") + " with newer versions.",
            "Updates carry fixes; CEDAR never installs them for you.",
            "Repository packages only; AUR and security classification are not included.", null, false));
    const p = input.capabilities && input.capabilities.privilege;
    if (p && p.helper === "pkexec" && !p.agent)
        out.push(issue("polkit-agent", "warning", "No authentication agent is registered",
            "pkexec is installed but no polkit agent answers on this session.",
            "Privileged actions (the firewall, restarting a system service) cannot ask for permission and will fail.",
            "Capabilities probe; CEDAR registers its own agent only when it is the session's shell.", null, false));
    if (p && p.helper !== "pkexec")
        out.push(issue("pkexec", "notice", "pkexec is not installed",
            "No privilege helper was found.", "Privileged actions are offered but cannot run.", "Capabilities probe.", null, false));
    if (typeof input.shellMemoryMb === "number" && input.shellMemoryMb > 900)
        out.push(issue("shell-memory", "notice", "The shell is using " + Math.round(input.shellMemoryMb) + " MB",
            "Resident memory of the shell process, read from /proc.", "Above about 900 MB something is likely holding onto memory; a restart from Settings › Health clears it.",
            "VmRSS; helpers and the GPU driver's share are not included.", null, false));
    return out;
}

const order = { critical: 0, warning: 1, notice: 2 };

function diagnose(input) {
    const all = [].concat(fromServices(input), fromFailedUnits(input), fromLog(input), fromConfig(input), fromReadings(input));
    return all.sort((a, b) => order[a.severity] - order[b.severity] || a.title.localeCompare(b.title));
}

function status(issues) {
    if (issues.some(i => i.severity === "critical")) return "risk";
    if (issues.some(i => i.severity === "warning")) return "attention";
    return "healthy";
}

function headline(status) { return ({ healthy: "Healthy", attention: "Attention", risk: "Needs fixing" })[status] || "Reading…"; }
