#!/usr/bin/env python3
"""Launch the matching release's independent native Task Manager."""
from pathlib import Path
import os,sys
ROOT=Path(__file__).resolve().parents[1]
def main():
    binary=ROOT/'libexec/cedar-task-manager'
    if not binary.is_file():
        # Source checkouts build explicitly; installed releases ship prepared binaries.
        binary=ROOT/'.local/task-manager/cedar-task-manager'
    if not binary.is_file():
        raise SystemExit('CEDAR Task Manager is not built. Run python3 scripts/build_task_manager.py in the source checkout, or reinstall CEDAR through its installer.')
    os.execv(str(binary),[str(binary),'--source',str(ROOT),*sys.argv[1:]])
if __name__=='__main__':main()
