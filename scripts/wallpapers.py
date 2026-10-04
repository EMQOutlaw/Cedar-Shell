#!/usr/bin/env python3
"""List local CEDAR wallpapers without an external theme manager."""
import json
from desktop_runtime import wallpapers
if __name__ == '__main__':
    print(json.dumps(wallpapers()))
