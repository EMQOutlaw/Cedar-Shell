"""One-frame, bounded wallpaper palette extraction with a persistent content cache."""
import colorsys
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
from .tokens import color


def extract(store,path,mode='dark',locked_accent=''):
    path=Path(path).expanduser()
    if not path.is_file() or path.suffix.lower() not in {'.jpg','.jpeg','.png','.webp','.bmp','.gif'}:
        raise ValueError('Choose a supported local wallpaper image.')
    if path.stat().st_size>128*1024*1024:raise ValueError('Wallpaper is too large for palette extraction.')
    key=hashlib.sha256(path.read_bytes()).hexdigest()
    cache=store.state/'palettes'/(key+'.json')
    stored=store.json(cache,None)
    if stored:accent=stored['accent']
    else:
        if not shutil.which('magick'):raise ValueError('ImageMagick is required for wallpaper palettes. No packages were installed.')
        # First frame only, strict resource limits, tiny raw RGB output. No shell evaluation.
        result=subprocess.run(['magick','-limit','memory','128MiB','-limit','map','256MiB','-limit','disk','0',str(path.absolute())+'[0]','-auto-orient','-thumbnail','32x32!','-alpha','off','-depth','8','rgb:-'],capture_output=True,timeout=12)
        if result.returncode or len(result.stdout)!=3072:raise ValueError('Wallpaper color extraction failed.')
        buckets={}
        for i in range(0,len(result.stdout),3):
            h,s,v=colorsys.rgb_to_hsv(*(x/255 for x in result.stdout[i:i+3]))
            if s<.12 or v<.10 or v>.96:continue
            bucket=round(h*24)%24;buckets[bucket]=buckets.get(bucket,0)+s
        hue=max(buckets,key=buckets.get)/24 if buckets else .36
        # Quantized hue and fixed tonal levels avoid reacting to minor image differences.
        accent='#'+''.join(f'{round(c*255):02x}' for c in colorsys.hsv_to_rgb(hue,.40,.85))
        store.save(cache,{'accent':accent})
    h,s,v=colorsys.rgb_to_hsv(*(n/255 for n in bytes.fromhex(accent[1:])))
    if mode=='light':accent='#'+''.join(f'{round(c*255):02x}' for c in colorsys.hsv_to_rgb(h,min(.65,s+.2),.38))
    if locked_accent:accent=color(locked_accent)
    return {'name':'Wallpaper palette','mode':mode,'colors':{'green':accent,'teal':'#'+''.join(f'{round(c*255):02x}' for c in colorsys.hsv_to_rgb((h+.08)%1,.32,.72 if mode=='dark' else .35))}}
