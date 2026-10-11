import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[2] / 'scripts'))
from desktop_runtime import set_wallpaper
set_wallpaper(sys.argv[1])
