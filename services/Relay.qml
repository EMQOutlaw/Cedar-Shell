pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import ".."
import "../components"

// CEDAR AI: two coding agents (Claude Code and Codex CLI) working one goal
// together, turn by turn, in one checkout. The shell is a presentation over
// scripts/cedar_ai.py: the script owns the agents, their sessions and the
// transcript on disk. A session is launched as its own process (a transient
// systemd user unit where there is one) serving its event stream at a Unix
// socket; this service attaches to that socket, replays the session so far
// and follows it live, and writes the person's messages and the stop request
// back over it. Closing the window, or restarting the shell, leaves the
// session running; the service re-attaches on its next start. `stop()` ends it.
//
// Turns are rows {agent, round, text, done, at}; activity lines are the tools
// each agent used, kept only for the running turn plus a short tail. Nothing
// polls: the process speaks when something happens.
Singleton {
    id: root
    readonly property var agents: ["claude", "codex"]
    property bool windowOpen: false
    readonly property bool open: windowOpen && !ShellState.locked

    // ----------------------------------------------------------- session
    property bool running: false
    property string socketPath: ""      // where the running session serves its stream
    property string goal: ""
    property string repo: ""
    property string mode: "edit"
    property string sessionDir: ""
    property string sessionName: ""
    property string currentAgent: ""
    property int currentRound: 0
    property var turns: []
    property var activity: []           // {agent, text} for the running turn
    property var humanMessages: []      // {text, at}
    property string finished: ""        // "" | done | rounds | stopped | error
    property string error: ""
    property string stderrTail: ""
    property string agentsUsed: "both"  // the session's agents: both | claude | codex
    property var models: ({ claude: { model: "", effort: "" }, codex: { model: "", effort: "" } })  // the session's models; "" = the tool's default
    property var relays: []             // {sender, receiver, round, at}: one agent's reply handed to the other
    // Tokens each agent has used in this session, as the tools report them (Claude also reports a cost).
    property var usage: ({ claude: null, codex: null })
    // The last plan reading each tool gave: Claude reports its 5-hour and 7-day windows on every run; Codex's CLI reports none.
    property var limits: ({ claude: null, codex: null })
    function tokens(n) { n = Number(n) || 0; return n >= 1e6 ? (n / 1e6).toFixed(1) + "M" : n >= 1e3 ? (n / 1e3).toFixed(n >= 1e4 ? 0 : 1) + "k" : String(n); }
    function usageLine(agent) {
        const u = usage[agent];
        if (!u) return "";
        return tokens(u.input + u.cached) + " in · " + tokens(u.output) + " out" + (u.cost ? " · $" + u.cost.toFixed(2) : "") + (u.turns ? " · " + u.turns + (u.turns === 1 ? " turn" : " turns") : "");
    }
    function limitLine(agent) {
        const l = limits[agent];
        if (!l) return "";
        return "5-hour " + Math.round(l.fiveHour * 100) + "% · week " + Math.round(l.sevenDay * 100) + "%";
    }
    function readUsage(value) {
        const out = { claude: null, codex: null };
        for (const agent of agents) {
            const u = value && value[agent];
            if (u && typeof u === "object") out[agent] = { input: Number(u.input) || 0, cached: Number(u.cached) || 0, output: Number(u.output) || 0, cost: Number(u.cost) || 0, turns: Number(u.turns) || 0 };
        }
        return out;
    }
    function readLimit(value) {
        if (!value || typeof value !== "object" || value.fiveHour === undefined) return null;
        return { fiveHour: Math.max(0, Math.min(1, Number(value.fiveHour) || 0)), sevenDay: Math.max(0, Math.min(1, Number(value.sevenDay) || 0)),
                 fiveHourResets: Number(value.fiveHourResets) || 0, sevenDayResets: Number(value.sevenDayResets) || 0, at: String(value.at || "") };
    }
    readonly property bool busy: running && currentAgent !== ""
    readonly property int roundCount: turns.length ? turns[turns.length - 1].round : 0
    readonly property bool soloSession: agentsUsed !== "both"
    readonly property string headline: !ready ? "Looking for the agents" : !available ? "Agents missing" : running ? (currentAgent ? agentName(currentAgent) + " is working" : "Between turns") : finished === "done" ? (soloSession ? agentName(agentsUsed) + " says it is done" : "Both agreed it is done") : finished === "rounds" ? "Paused at the round limit" : finished === "stopped" ? "Stopped" : finished === "error" ? "A turn failed" : turns.length ? "Resting" : "Ready"
    readonly property string subline: running ? (soloSession ? "Turn " : "Round ") + Math.max(1, currentRound) + (rounds > 0 ? " of " + rounds : " · until done") + " · " + mode : turns.length ? turns.length + (turns.length === 1 ? " turn" : " turns") + " · " + sessionName : (solo ? "Give " + agentName(preferredAgents) + " a goal" : "Give the two agents a goal")
    function turnTone(agent) { return agent === "claude" ? Theme.amber : Theme.teal; }
    function agentName(agent) { return agent === "claude" ? "Claude" : agent === "codex" ? "Codex" : "both agents"; }

    // ------------------------------------------------------- preferences
    readonly property string defaultRepo: Quickshell.shellDir
    readonly property string effectiveRepo: Config.saved.relayRepo || defaultRepo
    // 0 rounds means until the agents say the goal is done.
    readonly property int rounds: Math.max(0, Math.min(24, Number(Config.saved.relayRounds) || 0))
    readonly property string first: Config.saved.relayFirst === "codex" ? "codex" : "claude"
    readonly property string preferredMode: ["read", "edit", "full"].includes(Config.saved.relayMode) ? Config.saved.relayMode : "edit"
    readonly property string preferredAgents: ["both", "claude", "codex"].includes(Config.saved.relayAgents) ? Config.saved.relayAgents : "both"
    readonly property bool solo: preferredAgents !== "both"
    // Model and effort per agent; "" means whatever the tool itself is configured to use.
    readonly property string claudeModel: String(Config.saved.relayClaudeModel || "")
    readonly property string claudeEffort: claudeEfforts.includes(Config.saved.relayClaudeEffort) ? Config.saved.relayClaudeEffort : ""
    readonly property string codexModel: String(Config.saved.relayCodexModel || "")
    readonly property string codexEffort: codexEfforts.includes(Config.saved.relayCodexEffort) ? Config.saved.relayCodexEffort : ""
    function modelLabel(agent, chosen) {
        const m = (chosen || models)[agent] || { model: "", effort: "" };
        const parts = [m.model, m.effort].filter(Boolean);
        return parts.length ? parts.join(" · ") : "default";
    }

    // ---------------------------------------------------------- the tools
    property bool ready: false
    property var tools: ({ claude: "", codex: "" })
    property var claudeModels: []       // [{id, label}] aliases Claude Code accepts
    property var claudeEfforts: ["low", "medium", "high", "xhigh", "max"]
    property var codexModels: []        // [{id, label, efforts, defaultEffort}] from Codex's own model cache
    property var codexEfforts: ["minimal", "low", "medium", "high", "xhigh"]
    property var codexDefault: ({ model: "", effort: "" })
    readonly property bool available: preferredAgents === "claude" ? !!tools.claude : preferredAgents === "codex" ? !!tools.codex : !!tools.claude && !!tools.codex
    readonly property string missing: [!tools.claude && preferredAgents !== "codex" ? "Claude Code (claude)" : "", !tools.codex && preferredAgents !== "claude" ? "Codex CLI (codex)" : ""].filter(Boolean).join(" and ")
    function probe() { if (Config.testMode || ask.busy) return; ask.send({ action: "tools" }); }

    // ------------------------------------------------------------ sessions
    property var sessions: []
    property string sessionsRoot: ""
    // ServiceRequest queues this behind an in-flight tool probe when the window opens.
    function refreshSessions() { if (Config.testMode) return; ask.send({ action: "sessions" }); }
    function load(dir) { if (Config.testMode || ask.busy || running) return; ask.send({ action: "transcript", dir: dir }); }
    ServiceRequest {
        id: ask
        script: "scripts/cedar_ai.py"
        arguments: ["--serve"]
        timeoutMs: 15000
        onResult: value => {
            if (value.sessions) {
                root.sessions = value.sessions; root.sessionsRoot = value.root || "";
                root.sawRunning(value.running || null);
            }
            if (value.claude !== undefined) {
                root.tools = { claude: value.claude || "", codex: value.codex || "" };
                if (Array.isArray(value.claudeModels)) root.claudeModels = value.claudeModels;
                if (Array.isArray(value.claudeEfforts) && value.claudeEfforts.length) root.claudeEfforts = value.claudeEfforts;
                if (Array.isArray(value.codexModels)) root.codexModels = value.codexModels;
                if (Array.isArray(value.codexEfforts) && value.codexEfforts.length) root.codexEfforts = value.codexEfforts;
                if (value.codexDefault) root.codexDefault = { model: String(value.codexDefault.model || ""), effort: String(value.codexDefault.effort || "") };
                if (value.limits && typeof value.limits === "object") root.limits = { claude: root.readLimit(value.limits.claude), codex: root.readLimit(value.limits.codex) };
                root.ready = true;
            }
            if (value.session && value.turns) {
                root.finished = value.session.finished || "";
                root.goal = value.session.goal; root.repo = value.session.repo; root.mode = value.session.mode;
                root.agentsUsed = ["claude", "codex"].includes(value.session.agents) ? value.session.agents : "both";
                root.models = root.readModels(value.session.models);
                root.usage = root.readUsage(value.session.usage);
                root.sessionDir = value.session.dir; root.sessionName = value.session.name;
                root.turns = value.turns; root.activity = []; root.humanMessages = []; root.relays = []; root.error = "";
            }
        }
        onFailed: message => { root.error = message; root.ready = true; }
    }

    // ------------------------------------------------------------- running
    // One cedar_ai.py per session. The goal is an argument (never a shell
    // string); messages go to its stdin as JSON lines.
    function start(text) {
        const wanted = String(text || "").trim().slice(0, 4000);
        if (Config.testMode || ShellState.locked || running || !wanted || !available) return;
        root.goal = wanted; root.repo = effectiveRepo; root.mode = preferredMode; root.agentsUsed = preferredAgents;
        root.models = { claude: { model: claudeModel, effort: claudeEffort }, codex: { model: codexModel, effort: codexEffort } };
        root.usage = { claude: null, codex: null };
        root.turns = []; root.activity = []; root.humanMessages = []; root.relays = []; root.finished = ""; root.error = ""; root.stderrTail = "";
        root.sessionDir = ""; root.sessionName = ""; root.currentAgent = ""; root.currentRound = 0;
        const args = ["python3", Quickshell.shellPath("scripts/cedar_ai.py"), "--events", "--detach", "--repo", repo, "--mode", mode, "--agents", agentsUsed,
                      "--rounds", String(rounds), "--first", first];
        if (claudeModel) args.push("--claude-model", claudeModel);
        if (claudeEffort) args.push("--claude-effort", claudeEffort);
        if (codexModel) args.push("--codex-model", codexModel);
        if (codexEffort) args.push("--codex-effort", codexEffort);
        launch(args.concat([wanted]));
        if (!open) announce("started");
    }
    // Continue a recorded session; `text` is the message that picks it back up.
    // The session keeps the agents it was started with.
    function resume(dir, text) {
        const message = String(text || "").trim().slice(0, 4000);
        if (Config.testMode || ShellState.locked || running || !dir) return;
        root.finished = ""; root.error = ""; root.stderrTail = ""; root.activity = []; root.currentAgent = ""; root.currentRound = 0;
        const args = ["python3", Quickshell.shellPath("scripts/cedar_ai.py"), "--events", "--detach", "--resume-session", dir, "--rounds", String(rounds), "--first", first];
        if (message) args.push("-m", message);
        launch(args);
    }
    function say(text) {
        const message = String(text || "").trim().slice(0, 4000);
        if (!message || !running || !link.connected) return false;
        link.write(JSON.stringify({ message: message }) + "\n");
        link.flush();
        return true;  // the session echoes it as a `human` event at once
    }
    function stop() {
        if (!running) return;
        if (link.connected) { link.write(JSON.stringify({ stop: true }) + "\n"); link.flush(); }
        stopGuard.restart();
    }
    function clear() { if (running) return; turns = []; activity = []; humanMessages = []; relays = []; usage = { claude: null, codex: null }; goal = ""; sessionDir = ""; sessionName = ""; socketPath = ""; finished = ""; error = ""; agentsUsed = preferredAgents; }
    // A stop that the session does not honour within a few seconds is forced (SIGTERM through the script).
    Timer { id: stopGuard; interval: 6000; onTriggered: if (root.running && !Config.testMode) ask.send({ action: "kill" }) }

    // The launcher runs the script with --detach: it starts the session apart
    // from the shell, prints one line saying where its socket is, and exits.
    function launch(args) {
        root.running = true; root.socketPath = "";
        launcher.command = args;
        launcher.running = true;
    }
    Process {
        id: launcher
        stdout: SplitParser { onRead: data => root.launched(data) }
        stderr: SplitParser { onRead: data => root.stderrTail = (root.stderrTail + data + "\n").slice(-2000) }
        onExited: (code, status) => {
            if (code !== 0 || !root.socketPath) {
                root.running = false; root.currentAgent = "";
                root.finished = "error";
                root.error = "CEDAR AI could not start" + (root.stderrTail ? ": " + root.stderrTail.trim().split("\n").pop() : "");
                if (!root.open) root.announce("error");
            }
        }
    }
    function launched(line) {
        let event;
        try { event = JSON.parse(line); } catch (_) { return; }
        if (!event || event.type !== "launched" || !event.socket) return;
        attach(String(event.socket));
    }
    // Follow a session's stream. The socket replays everything recorded so far
    // first, so the state is rebuilt from nothing rather than merged.
    function attach(path) {
        if (!path) return;
        if (link.connected && root.socketPath === path) return;
        root.socketPath = path;
        root.turns = []; root.activity = []; root.humanMessages = []; root.relays = []; root.usage = { claude: null, codex: null };
        root.currentAgent = ""; root.currentRound = 0; root.finished = ""; root.error = "";
        root.running = true;
        attempts = 0;
        link.connected = false;
        link.path = path;
        link.connected = true;
        retry.restart();
    }
    property int attempts: 0
    // A freshly launched session needs a moment to bind its socket.
    Timer {
        id: retry
        interval: 250
        onTriggered: {
            if (link.connected || !root.running) return;
            if (++root.attempts > 40) { root.ended("CEDAR AI started but could not be reached"); return; }
            link.connected = false; link.connected = true; restart();
        }
    }
    Socket {
        id: link
        parser: SplitParser { onRead: data => root.accept(data) }
        onConnectedChanged: {
            if (connected) { retry.stop(); return; }
            // Gone while a session was running: it finished (the stream said
            // so) or it died; the running record tells which.
            if (root.running && root.socketPath && !retry.running) recheck.restart();
        }
    }
    Timer { id: recheck; interval: 400; onTriggered: if (ask.busy) restart(); else root.refreshSessions() }
    // The running record from the script: attach to a live session (after a
    // shell restart, or one started from a terminal), or close out ours.
    function sawRunning(record) {
        if (record && record.socket) {
            if (!link.connected || root.socketPath !== record.socket) attach(String(record.socket));
            return;
        }
        if (root.running && root.socketPath && !link.connected && !retry.running)
            ended(root.finished ? "" : "CEDAR AI ended without a word; see the session's transcript");
    }
    function ended(message) {
        stopGuard.stop(); retry.stop();
        root.running = false; root.currentAgent = "";
        if (message) { root.error = message; root.finished = "error"; }
        else if (!root.finished) root.finished = "stopped";
        if (!root.open) root.announce(root.finished);
    }
    Component.onCompleted: if (!Config.testMode) refreshSessions()
    function accept(line) {
        let event;
        try { event = JSON.parse(line); } catch (_) { return; }
        if (!event || typeof event !== "object") return;
        switch (event.type) {
        case "session":
            sessionDir = String(event.dir || ""); sessionName = String(event.name || "");
            goal = String(event.goal || goal); repo = String(event.repo || repo); mode = String(event.mode || mode);
            if (["both", "claude", "codex"].includes(event.agents)) agentsUsed = event.agents;
            if (event.models) models = readModels(event.models);
            if (event.usage) usage = readUsage(event.usage);
            finished = ""; error = "";  // a replayed stream may hold an earlier run's ending
            break;
        case "relay":
            if (agents.includes(event.sender) && agents.includes(event.receiver))
                relays = relays.concat([{ sender: event.sender, receiver: event.receiver, round: Number(event.round) || 0, at: new Date().toISOString() }]);
            break;
        case "turn.started":
            currentAgent = agents.includes(event.agent) ? event.agent : ""; currentRound = Number(event.round) || 0; activity = [];
            break;
        case "activity":
            if (agents.includes(event.agent)) activity = activity.concat([{ agent: event.agent, text: String(event.text || "").slice(0, 400) }]).slice(-60);
            break;
        case "turn.completed":
            if (agents.includes(event.agent))
                turns = turns.concat([{ agent: event.agent, round: Number(event.round) || currentRound, text: String(event.text || ""), done: !!event.done, at: new Date().toISOString() }]);
            currentAgent = "";
            break;
        case "usage":
            if (agents.includes(event.agent) && event.total) { const next = Object.assign({}, usage); next[event.agent] = readUsage({ [event.agent]: event.total })[event.agent]; usage = next; }
            break;
        case "limits":
            if (agents.includes(event.agent)) { const next = Object.assign({}, limits); next[event.agent] = readLimit(event); limits = next; }
            break;
        case "human":
            humanMessages = humanMessages.concat([{ text: String(event.text || ""), at: new Date().toISOString() }]);
            break;
        case "error":
            error = String(event.message || "");
            break;
        case "finished":
            finished = String(event.reason || "stopped");
            stopGuard.stop();
            currentAgent = "";
            if (running) { running = false; refreshSessions(); if (!open) announce(finished); }
            break;
        }
    }
    function readModels(value) {
        const out = { claude: { model: "", effort: "" }, codex: { model: "", effort: "" } };
        for (const agent of agents) {
            const m = value && value[agent];
            if (m && typeof m === "object") out[agent] = { model: String(m.model || "").slice(0, 80), effort: String(m.effort || "").slice(0, 16) };
        }
        return out;
    }
    function announce(reason) {
        if (!CoreService.enabled) return;
        const title = reason === "done" ? "CEDAR AI · " + (soloSession ? agentName(agentsUsed) + " is done" : "both agents are done") : reason === "rounds" ? "CEDAR AI · paused at the round limit" : reason === "error" ? "CEDAR AI · a turn failed" : reason === "started" ? "CEDAR AI · session started" : "CEDAR AI · stopped";
        CoreService.publish({ id: "relay", type: reason === "error" ? "warning" : "integration", priority: reason === "error" ? "high" : "normal", persistent: reason !== "started", sticky: false,
                              title: title, subtitle: goal.slice(0, 80), remember: false, actions: [{ id: "open", label: "Open CEDAR AI" }] });
    }

    // ----------------------------------------------------------- the app
    readonly property var pageIds: ["session", "sessions", "settings"]
    property string requestedPage: ""
    function openApp() { if (ShellState.locked) return; windowOpen = true; }
    function openPage(page) {
        if (ShellState.locked) return;
        const id = String(page || "").toLowerCase();
        if (!pageIds.includes(id)) return;
        windowOpen = true; requestedPage = ""; requestedPage = id;
    }
    function closeApp() { windowOpen = false; }
    function toggleApp() { if (windowOpen) closeApp(); else openApp(); }
    onOpenChanged: if (open) { probe(); refreshSessions(); }
    Connections { target: ShellState; function onLockedChanged() { if (ShellState.locked) root.windowOpen = false; } }
    function status() {
        return { ready: ready, available: available, running: running, attached: link.connected, socket: socketPath, finished: finished, windowOpen: windowOpen, goal: goal, mode: mode, agents: agentsUsed, models: models, usage: usage, limits: limits,
                 session: sessionName, round: currentRound, agent: currentAgent, turns: turns.length, relays: relays.length, error: error };
    }
}
