#!/usr/bin/env python3
"""CEDAR's portable installer entry point. No desktop distribution required."""
import sys
from setup import main

if __name__ == '__main__':
    try:
        main(sys.argv[1:])
    except (Exception, KeyboardInterrupt) as error:
        print('CEDAR: ' + (str(error) or 'Canceled; no further actions performed.'), file=sys.stderr)
        raise SystemExit(1)
