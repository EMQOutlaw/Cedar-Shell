#!/usr/bin/env python3
"""Write a private source resource ledger, including explicit unmeasured costs.

Static sites are evidence of ownership, not proof that an object is live. Use
measure_resources.py and an isolated QML profiler to attach runtime evidence.
"""
import argparse
import json
import re
from pathlib import Path
import distribution as d

POLICIES = {
    'services/Network.qml': ('NetworkManager status and Connections/Core', 'One subscribed stream; detail snapshots on visible demand', 'Helper exits with shell; retry capped at 60 s', '4 MiB snapshot protocol; no packet/history accumulation'),
    'services/DefaultApps.qml': ('Go and Default Apps Settings', 'One AppInfoMonitor; read only when shown or applying an action', 'Helper exits with shell; retry capped at 60 s', '4 MiB catalog; hidden events only mark dirty'),
    'services/SystemStats.qml': ('Field Station, System, Forest, warnings', 'In-process FileView reads of /proc and hwmon: fast 2 s visible/20 s ambient; temperature 5 s visible/30 s warnings; uptime and `df` 30 s visible/300 s warnings; one timer armed for the next due topic', 'No demand stops scheduling; hwmon discovery runs once per shell lifetime', 'Bounded /proc and sysfs reads; one `df` line'),
    'components/ServiceRequest.qml': ('Explicit service callers', 'One request, never concurrent within this owner', '45 s default timeout; caller may set a bounded operation timeout', '4 MiB character acceptance; collector checked after every incoming chunk; one chunk of overshoot possible'),
    'services/BluetoothService.qml': ('Bluetooth Settings and Canopy', 'Native events; discovery only while its controls are visible', 'Close/lock stops scan and pairing prompt; native backend is optional', 'Native device model; one action process'),
    'services/SessionIntegration.qml': ('Authentication boundary', '1 s freshness check plus watched supervisor status', 'Kept alive for managed session; never visibility-gated', 'Latest local status only'),
    'services/CoreTimer.qml': ('Persistent user timer', 'User-started countdown', 'Persists across hidden views until canceled/completed', 'One activity'),
    'services/Brightness.qml': ('Quick Controls, Power settings, Core brightness, OSD', '10 s only while a brightness control is visible; key presses read on demand', 'Hidden controls stop the timer; one process in flight', 'One JSON value'),
    'services/Forest.qml': ('Core pill, Canopy panels, Field Station', 'Event-driven: recomputed when any input property changes; 1 s clock only while a state settles, an echo or whisper fades or a signal is announced', 'Core disabled with no Canopy shown stops the clock; lock clears private state', 'State string, bounded echoes and trails'),
    'services/Capabilities.qml': ('Shield, Gaming, Health', 'One scripts/capabilities.py run at startup; again only on refresh() (Shield opening, a privileged action finishing)', 'Nothing recurring', 'One JSON snapshot'),
    'services/Gaming.qml': ('Quick Controls tile, Power page, Core pill, Super+G', 'Event-driven transaction on activate()/deactivate(); the logind inhibitor and the GameMode D-Bus watcher run only while applicable', 'deactivate() or lock restores and stops the inhibitor; the watcher exits with the shell', 'Six registry steps; one JSON state file'),
    'services/Shield.qml': ('Settings › Shield', 'scripts/shield.py on page open, refresh, an action, and a debounced network-state change while the page is open', 'Closing the page stops every read; pkexec actions wait on the user', 'One snapshot; listeners capped at 200'),
    'services/Motion.qml': ('Every ambient loop', 'Idle monitor only; no polling', 'Pauses ambience after 120 s without input or under Reduced Motion', 'One boolean'),
}


def ledger(root):
    records=[]
    for path,relative in d.files(root):
        if path.suffix not in ('.qml','.py','.js') or str(relative).startswith('tests/'):continue
        lines=path.read_text().splitlines()
        for index,line in enumerate(lines):
            match=re.search(r'\b(Timer|Process|FileView|Connections|NumberAnimation|OpacityAnimator|SequentialAnimation|ParallelAnimation)\s*\{|\b(subprocess\.(?:run|Popen)|add_signal_receiver|io_add_watch|timeout_add)\s*\(',line)
            if not match:continue
            known=POLICIES.get(str(relative))
            records.append({'owner':str(relative),'line':index+1,'resource':match[1] or match[2],
                            'consumers':known[0] if known else 'Follow owner references; individual site review pending',
                            'triggerCadence':known[1] if known else 'See source binding; runtime cadence not yet measured',
                            'startCondition':line.strip(),
                            'stopAndRestart':known[2] if known else 'Not independently verified',
                            'outputBound':known[3] if known else 'Not independently verified',
                            'perMonitor':'shared singleton' if 'pragma Singleton' in '\n'.join(lines[:8]) else 'Follow screen host construction; not inferred from filename',
                            'measuredCost':'Not measured','sourceContext':'\n'.join(lines[index:index+8])})
    return {'format':1,'scope':'Release inventory; static resource sites, not a live allocation count',
            'runtimeStatus':'Not measured; do not use as a CPU, memory or frame-rate benchmark','records':records}


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('output',type=Path);args=parser.parse_args()
    d.private_directory(args.output.parent);d.write_json(args.output,ledger(d.ROOT));print('Private source resource ledger written.')
