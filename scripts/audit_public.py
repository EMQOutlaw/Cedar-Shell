#!/usr/bin/env python3
"""Report privacy categories and filenames, never matched private values."""
from pathlib import Path
import os,re,socket,sys
ROOT=Path(__file__).resolve().parents[1]
# The current account and host are personal identities to keep out of a
# release; generic account names (CI runners, containers, fixtures) are not.
# A fixture that has to show a home directory uses a placeholder, so a
# /home/<account>/ path is only personal when the account is not one of these.
GENERIC_ACCOUNTS={'runner','root','user','ubuntu','github','build','builder','test','admin','ci','vagrant','docker','debian','arch','fedora',
                  'u','username','you','me','someone','example','station'}
identities=[value for value in (str(Path.home()),os.environ.get('USER',''),socket.gethostname()) if value.lower() not in GENERIC_ACCOUNTS]
home_path=re.compile(rb'/home/([A-Za-z0-9_.-]+)/')
patterns=[('private IPv4 endpoint',re.compile(rb'\b(?:192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+|172\.(?:1[6-9]|2\d|3[01])\.\d+\.\d+)\b')),
          ('credential signature',re.compile(rb'(?:gh[pousr]_[A-Za-z0-9]{30,}|sk-[A-Za-z0-9]{24,}|BEGIN (?:RSA |OPENSSH )?PRIVATE KEY)'))]


def personal_home(data):
    """A /home/<account>/ path names a person unless the account is a placeholder."""
    return any(match.group(1).decode('ascii','ignore').lower() not in GENERIC_ACCOUNTS for match in home_path.finditer(data))


def label(path,root):
    try:return str(Path(path).relative_to(root))
    except ValueError:return str(path)


def scan(paths,root=ROOT):
    """Categories and file names for the given publication inputs, never values."""
    findings=[]
    for path in paths:
        path=Path(path)
        if not path.is_file() or any(part in ('.git','__pycache__') for part in path.parts):continue
        if path.suffix in ('.log','.qslog','.pyc'):
            findings.append(('private/runtime artifact',label(path,root)));continue
        data=path.read_bytes()
        if personal_home(data):findings.append(('personal home path',label(path,root)))
        for category,pattern in patterns:
            if pattern.search(data):findings.append((category,label(path,root)))
        if any(re.search(rb'(?<![A-Za-z0-9_])'+re.escape(value.encode())+rb'(?![A-Za-z0-9_])',data) for value in identities if len(value)>3):
            findings.append(('local machine identity',label(path,root)))
    return sorted(set(findings))


def main():
    sys.path.insert(0,str(Path(__file__).resolve().parent))
    from distribution import files
    # Scan the exact publication inputs. Local handoffs and recoverable backups
    # outside this inventory are never release inputs; CI also checks tracked files.
    findings=scan([path for path,_ in files(ROOT)])
    for category,path in findings:print(category+': '+path)
    print('Privacy scan: '+('review required' if findings else 'no matches in the release source, documentation or assets'))
    print('Git history: '+('present; requires separate review' if (ROOT/'.git').exists() else 'not present in the provided project snapshot'))
    return bool(findings)


if __name__=='__main__':sys.exit(main())
