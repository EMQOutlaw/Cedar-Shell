#!/usr/bin/env python3
"""Acceptance checks on exact archive bytes, in a disposable extraction."""
from pathlib import Path
import hashlib,json,os,subprocess,sys,tempfile
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'scripts'))
from distribution import safe_extract
archive=Path(sys.argv[1]).resolve()
with tempfile.TemporaryDirectory(prefix='cedar artifact 雨 ') as temporary:
    base=Path(temporary);safe_extract(archive,base);root=base/'cedar-shell'
    manifest=json.loads((root/'ARTIFACT-CONTENTS.json').read_text())
    for rel,entry in manifest.items():
        file=root/rel
        if not file.is_file() or hashlib.sha256(file.read_bytes()).hexdigest()!=entry['sha256']:raise SystemExit('Artifact mismatch: '+rel)
    for row in json.loads((root/'data/plugins.json').read_text())['plugins']:
        for rel in row['releaseArtifacts']:
            if rel not in manifest:raise SystemExit('Plugin artifact omitted: '+rel)
    env={**os.environ,'HOME':str(base/'home'),**{'XDG_'+k+'_HOME':str(base/k.lower()) for k in ['CONFIG','DATA','STATE','CACHE']}}
    for argv in [['bash','./install.sh','--plan'],['bash','-n','install.sh'],[sys.executable,'-m','unittest','discover','-s','tests','-p','test_distribution.py'],[sys.executable,'-m','unittest','discover','-s','tests','-p','test_omarchy_session.py'],[sys.executable,'-m','unittest','discover','-s','tests','-p','test_omacale_providers.py']]:
        result=subprocess.run(argv,cwd=root,env=env,text=True,capture_output=True)
        if result.returncode:print(result.stdout+result.stderr);raise SystemExit(1)
    print('PASS: exact archive hashes, all plugin artifacts, spaces/non-ASCII paths, Bash startup and stdlib recovery/privacy tests')
    print('NOT TESTED: fresh-system package bootstrap, live Wayland/PAM, Zsh/Fish, logout/login/reboot and GPU matrix')
