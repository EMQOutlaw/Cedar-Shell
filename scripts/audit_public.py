#!/usr/bin/env python3
"""Report privacy categories and filenames, never matched private values."""
from pathlib import Path
import os,re,socket,sys
ROOT=Path(__file__).resolve().parents[1]
identities=[str(Path.home()),os.environ.get('USER',''),socket.gethostname()]
patterns=[('personal home path',re.compile(rb'/home/[A-Za-z0-9_.-]+/')),
          ('private IPv4 endpoint',re.compile(rb'\b(?:192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)\b')),
          ('credential signature',re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{24,}|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY)'))]
findings=[]
from distribution import files
# Scan the exact publication inputs. Local handoffs and recoverable backups
# outside this inventory are never release inputs; CI also checks tracked files.
for path, _ in files(ROOT):
    if not path.is_file() or any(part in ('.git','__pycache__') for part in path.parts):continue
    if path.suffix in ('.log','.qslog','.pyc'):findings.append(('private/runtime artifact',str(path.relative_to(ROOT))));continue
    data=path.read_bytes()
    for category,pattern in patterns:
        if pattern.search(data):findings.append((category,str(path.relative_to(ROOT))))
    if any(re.search(rb'(?<![A-Za-z0-9_])'+re.escape(value.encode())+rb'(?![A-Za-z0-9_])',data) for value in identities if len(value)>3):findings.append(('local machine identity',str(path.relative_to(ROOT))))
for category,path in sorted(set(findings)):print(category+': '+path)
print('Privacy scan: '+('review required' if findings else 'no matches in the release source, documentation or assets'))
print('Git history: '+('present; requires separate review' if (ROOT/'.git').exists() else 'not present in the provided project snapshot'))
sys.exit(bool(findings))
