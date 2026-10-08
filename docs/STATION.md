# Station

CEDAR Station is the health of this desktop as a first-party application:
its own window (`cedar station`, Go › Station, Super+Shift+H, `qs -c cedar
ipc call station open`), a rail with Health, Services, Issues, Log and
Report, and a diagnostics engine that turns real readings into issues that
say what happened, why it matters, what CEDAR verified, what it can do and
whether that needs elevated privileges. `cedar station issues` or
`station page log` opens a page directly. Settings › Health remains the
quick summary inside Settings; Station is where the work is done.

## What it reads, and from where

Nothing is rebuilt. Station reuses the collectors that exist and adds one
read-only helper:

| Reading | Source | When |
| --- | --- | --- |
| Service health (PipeWire, WirePlumber, NetworkManager, Bluetooth, the portals) and versions | `SettingsInfo` → `scripts/settings_info.py` | on open and Check again |
| Failed units, user and system | `scripts/station.py` → `systemctl --failed` | on open and Check again |
| Shell log issues since the last launch (load failures, binding errors), deduplicated with counts, redacted | `scripts/station.py` over `~/.local/state/cedar/shell.log` | on open and Check again |
| Configuration files that do not parse; a profile link without a shell | `scripts/station.py` | on open and Check again |
| GPU utilisation and temperature | `scripts/station.py`: sysfs `gpu_busy_percent` or `nvidia-smi`, where one exists; otherwise "no supported path" | on open and Check again |
| The shell's resident memory | `scripts/station.py` from `/proc` | on open and Check again |
| Processor, memory, disk, temperature, uptime, network rate | `SystemStats`, at its instrument cadence (2 s) only while the window is open | live |
| Repository updates | `CoreService` → `checkupdates`, on Check updates only; "not checked" until then | on request |
| Privilege helper, power provider, GPU path | `Capabilities` | cached |

## The engine

`components/core/Diagnostics.js` is pure and tested: it takes the readings
and returns issues ordered critical → warning → notice, each with `what`,
`why`, `verify`, an optional `action` and a `privileged` flag.

| Issue | Severity | Action | Privileged |
| --- | --- | --- | --- |
| A CEDAR dependency failed / not active | critical / warning | Restart | system units: yes (pkexec) |
| Another unit failed | user: warning · system: critical | Restart, Reset | system: yes |
| The shell refused a configuration | critical | none; reported | — |
| A QML binding errored (with count) | warning | none; reported | — |
| A configuration file does not parse | warning | none; reported | — |
| Disk at or over its limit | warning, critical at 97 % | none; reported | — |
| Temperature at or over its limit | warning | none; reported | — |
| Repository updates available | notice | none; CEDAR never installs | — |
| No polkit agent / no pkexec | warning / notice | none; reported | — |
| Shell memory above ~900 MB | notice | none; reported | — |

A restart asks for confirmation; a system unit goes through `pkexec
systemctl`, and the polkit agent prompts. Nothing is restarted or changed
without that. An action whose prerequisite is missing (no agent) is shown
disabled with the reason.

## The window

A station like Shield: the rail carries the status pill, when the readings
were taken and the host name; Health shows the status frame with a service
ring, the live readings with processor and memory traces (drawn only while
the window is open), the services and the shell's own cost; Services lists
every dependency with Logs and Restart and every failed unit with Logs,
Reset and Restart; Issues shows one card per issue with Details for the
why and the verification; Log shows the shell-log issues and a unit's
redacted journal; Report builds a plain-text diagnostic report (status,
versions, services, readings, capabilities, failed units, log issues,
configuration problems), redacted by `scripts/redaction.py`, shown for
review and copied on request. Nothing is uploaded.

Keyboard: Ctrl+1…5 pages, Ctrl+R checks again, Escape or Ctrl+W closes.

## Cost

Idle: nothing. Opening runs settings_info.py and station.py once and raises
SystemStats to its instrument cadence until the window closes. The GPU
reading is one sysfs read or one `nvidia-smi` call per snapshot, never on a
timer.

## Tests

`node tests/core/diagnostics_test.js components/core/Diagnostics.js` (the
engine: ordering, privilege flags, deduplication, thresholds from inputs,
unknown readings produce nothing) and `tests/check_station.py` (fixture
collectors through the service, status and counts, page requests, the
pages at 1180 and 640 px, a clean reading restores Healthy).
