#!/usr/bin/env python3
"""Omarchy hook and guard entry point (theme-set, post-boot, cedar-theme-guard).

CEDAR is not an Omarchy theme: whichever theme is picked, CEDAR stays the
desktop. This only makes sure CEDAR is running and Omarchy's own shell is not;
the work is cedar_session.py, which Hyprland also runs at login on any system.
"""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import cedar_session  # noqa: E402


def sync(reconcile_only=False):
    return cedar_session.main(['reconcile' if reconcile_only else 'start'])


if __name__ == '__main__':
    raise SystemExit(sync(reconcile_only='--reconcile-only' in sys.argv))
