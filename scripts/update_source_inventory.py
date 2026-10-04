#!/usr/bin/env python3
"""Maintainer command: record tracked source; ordinary installation needs no Git."""
import argparse, json, subprocess
from pathlib import Path

root=Path(__file__).resolve().parents[1]
names=subprocess.check_output(['git','ls-files','-z'],cwd=root).decode().split('\0')
names=sorted(set(filter(None,names))|{'data/source-files.json'})
p=argparse.ArgumentParser();p.add_argument('--check',action='store_true');args=p.parse_args()
content=json.dumps(names,indent=2,ensure_ascii=False)+'\n';destination=root/'data/source-files.json'
if args.check:
    if not destination.is_file() or destination.read_text()!=content:raise SystemExit('Source inventory differs from tracked files. Stage intended files and run scripts/update_source_inventory.py.')
    print('Source inventory matches tracked files.')
else:
    destination.write_text(content)
    print('Recorded',len(names),'source files. Review the inventory before committing.')
