#!/usr/bin/env python3
"""Graphics & Power telemetry for Settings › Graphics & Power.

One JSON request on stdin, one {"ok":true,"data":…} (or {"ok":false,
"error":…}) object on stdout — the ServiceRequest protocol. Reads are
unprivileged: nvidia-smi queries and sysfs reads only. Writes exist, but
never unprivileged: the `apply` action escalates through pkexec to the
root-owned wrapper scripts/cedar-gpu-apply (installed at
/usr/local/sbin/cedar-gpu-apply), which re-validates every value as root.
This file never elevates by itself and never writes system state. The
system power profile is NOT read here — the Controls service owns it, and
two readers of one subsystem is a regression.
"""
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

HOME = Path.home()

NVIDIA_FIELDS = ('name', 'utilization.gpu', 'temperature.gpu', 'memory.used',
                 'memory.total', 'power.draw', 'power.limit', 'pstate',
                 'clocks.gr', 'clocks.max.gr', 'fan.speed', 'persistence_mode')
TUNE_FIELDS = ('uuid', 'power.min_limit', 'power.max_limit')


def num(text):
    try:
        return float(text)
    except (TypeError, ValueError):
        return None


def nvidia_gpus():
    """The discrete NVIDIA dossier, when the driver and nvidia-smi exist."""
    if not shutil.which('nvidia-smi'):
        return []
    query = '--query-gpu=' + ','.join(NVIDIA_FIELDS + TUNE_FIELDS)
    p = subprocess.run(['nvidia-smi', query, '--format=csv,noheader,nounits'],
                       capture_output=True, text=True, timeout=5, check=False)
    if p.returncode:
        return []
    gpus = []
    for line in p.stdout.splitlines():
        v = [s.strip() for s in line.split(',')]
        if len(v) != len(NVIDIA_FIELDS) + len(TUNE_FIELDS):
            continue  # a short row is honest absence, not a guess
        gpus.append({'source': 'nvidia', 'name': v[0],
                     'load': num(v[1]), 'temperature': num(v[2]),
                     'memoryUsed': num(v[3]), 'memoryTotal': num(v[4]),
                     'powerDraw': num(v[5]), 'powerLimit': num(v[6]),
                     'pstate': v[7], 'clock': num(v[8]), 'clockMax': num(v[9]),
                     'fan': num(v[10]), 'persistence': v[11].lower(),
                     'uuid': v[12],
                     'powerMinLimit': num(v[13]), 'powerMaxLimit': num(v[14])})
    return gpus


def drm_gpus():
    """The kernel fallback: amdgpu/i915 and friends expose busy + VRAM. Only
    real cards count — the connector directories (card1-DP-1 and friends)
    symlink to the same device and would render one GPU once per output."""
    gpus = []
    for card in sorted((d for d in Path('/sys/class/drm').iterdir()
                        if re.fullmatch(r'card\d+', d.name)), key=lambda d: d.name):
        device = card / 'device'

        def read(name, factor=1):
            try:
                return int((device / name).read_text()) / factor
            except (OSError, ValueError):
                return None
        if not (device / 'gpu_busy_percent').exists():
            continue
        gpus.append({'source': 'drm', 'name': card.name,
                     'load': read('gpu_busy_percent'), 'temperature': None,
                     'memoryUsed': read('mem_info_vram_used', 1048576),
                     'memoryTotal': read('mem_info_vram_total', 1048576),
                     'powerDraw': None, 'powerLimit': None, 'pstate': '',
                     'clock': None, 'clockMax': None, 'fan': None,
                     'persistence': ''})
    return gpus


def cpu():
    """What the host reports about the CPU. Current clocks come from cpufreq
    (cpuinfo's MHz lags under amd-pstate); the governor and the energy
    preference are read as state — when the privileged helper is
    installed, THIS helper writes them on the page's behalf and the state
    reported here is what that write produced."""
    model, threads, freqs = '', 0, []
    try:
        for line in Path('/proc/cpuinfo').read_text().splitlines():
            if line.startswith('model name'):
                model = line.split(':', 1)[1].strip()
            elif line.startswith('processor'):
                threads += 1
    except OSError:
        pass
    for policy in sorted(Path('/sys/devices/system/cpu').glob('cpu[0-9]*/cpufreq/scaling_cur_freq')):
        try:
            freqs.append(int(policy.read_text()) / 1000.0)  # kHz -> MHz
        except (OSError, ValueError):
            continue

    def state(name):
        # Read from cpu0 only: the assumption is a single cpufreq policy for the
        # whole package (true on this AMD host). Intel hybrid parts (P/E cores)
        # can carry per-policy values cpu0 misreports as machine-wide.
        try:
            return Path('/sys/devices/system/cpu/cpu0/cpufreq', name).read_text().strip()
        except OSError:
            return ''
    CPUFREQ0 = Path('/sys/devices/system/cpu/cpu0/cpufreq')
    available = {'scaling_available_governors': '', 'energy_performance_available_preferences': ''}
    for key in available:
        try:
            available[key] = Path('/sys/devices/system/cpu/cpu0/cpufreq', key).read_text().strip()
        except OSError:
            available[key] = ''
    try:
        load1, load5, load15 = (float(x) for x in Path('/proc/loadavg').read_text().split()[:3])
    except (OSError, ValueError):
        load1 = load5 = load15 = None
    freq_min = freq_max = None  # the HARDWARE range (cpuinfo_*), never the user-set scaling ceiling
    try:
        freq_min = int((CPUFREQ0 / 'cpuinfo_min_freq').read_text())
        freq_max = int((CPUFREQ0 / 'cpuinfo_max_freq').read_text())
    except (OSError, ValueError):
        pass
    return {'model': model, 'threads': threads,
            'freqAvg': round(sum(freqs) / len(freqs) / 1000.0, 2) if freqs else None,  # GHz
            'governor': state('scaling_governor'), 'epp': state('energy_performance_preference'),
            'governors': available['scaling_available_governors'].split(),
            'preferences': available['energy_performance_available_preferences'].split(),
            'load1': load1, 'load5': load5, 'load15': load15,
            'freqMinKHz': freq_min, 'freqMaxKHz': freq_max}


def snapshot():
    gpus = nvidia_gpus() or drm_gpus()  # the NVIDIA dossier wins when it exists
    return {'gpus': gpus, 'cpu': cpu(),
            'source': 'nvidia-smi' if gpus and gpus[0]['source'] == 'nvidia'
                      else ('kernel' if gpus else ''),
            'applyHelper': APPLY_HELPER.exists(),
            'program': program_get()}


# The privileged half. This file is the ONLY thing pkexec runs, it must be
# root-owned and unwritable by group/other (a user-writable script run as
# root is an arbitrary-root hole), and it must be THIS build's copy — a stale
# one would apply rules this code no longer stands behind. See
# scripts/cedar-gpu-apply.
APPLY_HELPER = Path('/usr/local/sbin/cedar-gpu-apply')
PROGRAM_FILE = Path(os.environ.get('XDG_CONFIG_HOME', HOME / '.config')) / 'cedar' / 'gpu-power.json'
APPLY_TIMEOUT_S = 90  # polkit prompts a human: the read-and-type window. Kept
                      # strictly INSIDE the UI's channel deadline (135 s) so
                      # the helper's own "authorization timed out" always
                      # lands before the UI gives up — an orphaned pkexec with
                      # a live dialog would apply root writes nobody reads.


def _guard(info, source_digest, helper_digest):
    """The ownership/writability/freshness gate, pure so it is testable as a
    non-root user (a real root-owned file cannot exist in a test tree)."""
    import hashlib
    import stat
    if info.st_uid != 0:
        raise RuntimeError('The apply helper is not root-owned. Refusing to escalate through it — reinstall it (the Graphics & Power page shows the command).')
    if info.st_mode & (stat.S_IWGRP | stat.S_IWOTH):
        raise RuntimeError('The apply helper is writable by group or other. Refusing to escalate through it — reinstall it.')
    if helper_digest != source_digest:
        raise RuntimeError('The installed apply helper differs from this build of CEDAR. Reinstall it (the Graphics & Power page shows the command) so the two agree on what may be written.')


def check_helper():
    """The wrapper must exist, be root-owned, and be unwritable by anyone but
    root — pkexec does not check any of that, and a group-writable helper
    would run attacker-edited code as root unchallenged. It must also be THIS
    build's copy: a stale one would apply rules this code no longer stands
    behind."""
    import hashlib
    if not APPLY_HELPER.exists():
        raise RuntimeError('The privileged apply helper is not installed (/usr/local/sbin/cedar-gpu-apply). The Graphics & Power page shows the exact install command.')
    source = Path(__file__).resolve().parent / 'cedar-gpu-apply'
    digest = lambda p: hashlib.sha256(Path(p).read_bytes()).hexdigest()
    try:
        _guard(APPLY_HELPER.stat(), digest(source), digest(APPLY_HELPER))
    except OSError as error:
        raise RuntimeError('The apply helper could not be read (%s). Reinstall it — the Graphics & Power page shows the command.' % error)


def apply_request(request):
    """One write, through pkexec. The request is validated here as the user
    AND again inside the root-owned wrapper; nothing else is ever executed."""
    check_helper()
    if not isinstance(request, dict):
        raise ValueError('The apply request is not an object.')
    payload = {}
    if 'gpu' in request:
        gpu = request['gpu'] or {}
        if not isinstance(gpu, dict):
            raise ValueError('The gpu request is not an object.')
        allowed = {'uuid', 'powerLimit', 'persistence'}
        if set(gpu) - allowed:
            raise ValueError('Unknown GPU keys: ' + ', '.join(sorted(set(gpu) - allowed)))
        payload['gpu'] = gpu
    if 'cpu' in request:
        cpu = request['cpu'] or {}
        if not isinstance(cpu, dict):
            raise ValueError('The cpu request is not an object.')
        allowed = {'governor', 'epp', 'maxFreqKHz'}
        if set(cpu) - allowed:
            raise ValueError('Unknown CPU keys: ' + ', '.join(sorted(set(cpu) - allowed)))
        payload['cpu'] = cpu
    if not payload:
        raise ValueError('Nothing to apply.')
    try:
        p = subprocess.run(['pkexec', str(APPLY_HELPER)], input=json.dumps(payload),
                           capture_output=True, text=True, timeout=APPLY_TIMEOUT_S, check=False)
    except subprocess.TimeoutExpired:
        raise RuntimeError('The polkit authorization timed out. Apply again — the prompt waits about 90 seconds for the password.')
    try:
        reply = json.loads(p.stdout.splitlines()[-1]) if p.stdout.strip() else None
    except (ValueError, IndexError):
        reply = None
    if reply and reply.get('ok'):
        # Remember what the machine should be running: the driver drops
        # runtime limits when it re-initializes (persistence off, reboot), and
        # the page offers a one-click re-apply when it detects the reset.
        try:
            _remember_last_applied(payload, PROGRAM_FILE)
        except OSError:
            pass  # the write succeeded; bookkeeping must not shadow it
        return reply['data']
    raise RuntimeError((reply or {}).get('error') or p.stderr.strip() or 'pkexec could not run the apply helper.')


def _remember_last_applied(payload, program_file):
    """lastApplied = the values CEDAR last successfully wrote, merged per
    uuid so a second GPU never clobbers the first. Read back on every
    snapshot so a driver reset is visible as a difference, not silence."""
    try:
        existing = json.loads(program_file.read_text()) if program_file.exists() else {}
    except Exception:  # noqa: BLE001 — bookkeeping, never the apply's success
        existing = {}
    merged = dict(existing) if isinstance(existing, dict) else {}
    previous_all = merged.get('lastApplied') if isinstance(merged.get('lastApplied'), dict) else {}
    gpu = payload.get('gpu') or {}
    if gpu.get('uuid'):
        previous = previous_all.get(gpu['uuid']) if isinstance(previous_all.get(gpu['uuid']), dict) else {}
        entry = {**previous, 'uuid': gpu['uuid']}
        if 'powerLimit' in gpu:
            entry['powerLimit'] = gpu['powerLimit']
        if 'persistence' in gpu:
            entry['persistence'] = gpu['persistence']
        merged['lastApplied'] = {**previous_all, gpu['uuid']: entry}
    if isinstance(payload.get('cpu'), dict) and payload['cpu']:
        merged['lastAppliedCpu'] = {**merged.get('lastAppliedCpu', {}), **payload['cpu']}
    program_file.parent.mkdir(parents=True, exist_ok=True)
    tmp = program_file.with_name(program_file.name + '.tmp')
    tmp.write_text(json.dumps(merged, indent=2) + '\n')
    os.chmod(tmp, 0o600)
    os.replace(tmp, program_file)


def program_get():
    """The saved per-profile CPU programmer values. Read-only, tolerant: an
    unreadable file is reported, never silently replaced on read."""
    try:
        data = json.loads(PROGRAM_FILE.read_text())
    except FileNotFoundError:
        return {'profiles': {}, 'path': str(PROGRAM_FILE)}
    except Exception as error:  # noqa: BLE001
        return {'profiles': {}, 'path': str(PROGRAM_FILE), 'error': str(error)}
    if not isinstance(data, dict):
        return {'profiles': {}, 'path': str(PROGRAM_FILE), 'error': 'The programmer file is not an object.'}
    return {'profiles': data.get('profiles') or {}, 'path': str(PROGRAM_FILE),
            **({'error': data.get('error')} if data.get('error') else {})}


def program_save(req):
    """Persist per-profile CPU values. Unknown keys in the file survive; the
    file is written atomically with private permissions."""
    profiles = req.get('profiles')
    if not isinstance(profiles, dict) or not profiles:
        raise ValueError('The programmer needs a profiles object.')
    clean = {}
    for profile, values in profiles.items():
        if not isinstance(profile, str) or profile not in ('power-saver', 'balanced', 'performance'):
            raise ValueError('Unknown profile: ' + str(profile))
        if not isinstance(values, dict):
            raise ValueError('Profile values must be an object.')
        clean[profile] = {k: v for k, v in values.items()
                          if k in ('governor', 'epp', 'maxFreqKHz') and v is not None}
    try:
        existing = json.loads(PROGRAM_FILE.read_text()) if PROGRAM_FILE.exists() else {}
    except Exception:  # noqa: BLE001 — a corrupt file is replaced, the data is CEDAR's own
        existing = {}
    if not isinstance(existing, dict):
        existing = {}
    merged = dict(existing)
    merged['profiles'] = {**(existing.get('profiles') or {}), **clean}
    PROGRAM_FILE.parent.mkdir(parents=True, exist_ok=True)
    tmp = PROGRAM_FILE.with_name(PROGRAM_FILE.name + '.tmp')
    tmp.write_text(json.dumps(merged, indent=2) + '\n')
    os.chmod(tmp, 0o600)
    os.replace(tmp, PROGRAM_FILE)
    return program_get()


def action(req):
    name = req.get('action', 'snapshot')
    if name == 'snapshot':
        return snapshot()
    if name == 'apply':
        return apply_request(req)
    if name == 'program-save':
        return program_save(req)
    raise ValueError('Unknown graphics action')


if __name__ == '__main__':
    try:
        print(json.dumps({'ok': True, 'data': action(json.loads(sys.stdin.readline() or '{}'))}))
    except Exception as error:  # noqa: BLE001
        print(json.dumps({'ok': False, 'error': str(error)}))
