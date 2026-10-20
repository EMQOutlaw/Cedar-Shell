"""Validated semantic tokens, independent of Quickshell and adapter syntax."""
import colorsys
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
DEFAULT = json.loads((ROOT / 'themes/palettes/cedar.json').read_text())
ANSI = ['background', 'ember', 'green', 'amber', 'blue', 'violet', 'teal', 'text',
        'muted', 'brightEmber', 'brightGreen', 'brightAmber', 'brightBlue', 'brightViolet', 'brightTeal', 'white']
NAMES = ['black', 'red', 'green', 'yellow', 'blue', 'magenta', 'cyan', 'white']
MAP = {'background.primary':'background', 'background.secondary':'surface', 'background.elevated':'elevated',
       'surface.default':'surface', 'surface.hover':'elevated', 'surface.active':'border', 'surface.overlay':'background',
       'text.primary':'text', 'text.secondary':'muted', 'text.disabled':'muted',
       'accent.primary':'green', 'accent.secondary':'teal', 'accent.hover':'brightGreen',
       'border.default':'border', 'border.focus':'green', 'border.subtle':'surface',
       'status.success':'green', 'status.warning':'amber', 'status.error':'ember', 'status.info':'blue'}

def color(value):
    if not isinstance(value, str) or not re.fullmatch(r'#[0-9a-fA-F]{6}', value):
        raise ValueError('Colors must be #RRGGBB values.')
    return value.lower()

def rgb(value): return tuple(int(color(value)[i:i+2],16) for i in (1,3,5))
def luminance(value):
    return sum((n/255/12.92 if n/255 <= .04045 else ((n/255+.055)/1.055)**2.4)*w for n,w in zip(rgb(value),(.2126,.7152,.0722)))
def contrast(a,b):
    x,y=sorted((luminance(a),luminance(b))); return (y+.05)/(x+.05)
def readable(fg, backgrounds, minimum=4.5):
    if min(contrast(fg,bg) for bg in backgrounds) >= minimum: return fg
    best=max(('#ffffff','#080f0d'),key=lambda c:min(contrast(c,bg) for bg in backgrounds))
    if min(contrast(best,bg) for bg in backgrounds) < minimum:
        raise ValueError('The selected surfaces cannot share a readable text color.')
    return best

def compile_theme(palette=None, options=None):
    palette=palette or {}; options=options or {}
    mode=options.get('variant',palette.get('mode','dark'))
    if mode not in ('light','dark'): raise ValueError('Choose light or dark.')
    colors=dict(DEFAULT['colors'])
    if mode=='light':
        colors.update(background='#f1f3eb',surface='#e6ebdf',elevated='#dce4d5',border='#a4b7a0',text='#16231c',muted='#415447',green='#226234',teal='#176b62',amber='#735319',ember='#a23832',blue='#285b86',violet='#684a87')
    for key,value in palette.get('colors',{}).items():
        if key not in colors: raise ValueError('Unknown palette color: '+key)
        if mode==palette.get('mode',mode) or key not in {'background','surface','elevated','border','text','muted'}:colors[key]=color(value)
    accent=options.get('accent','')
    if accent: colors['green']=color(accent)
    tokens={name:color(colors[key]) for name,key in MAP.items()}
    for key,value in palette.get('tokens',{}).items():
        if key not in MAP and key!='text.onAccent' and not key.startswith('terminal.'): raise ValueError('Unknown semantic token: '+key)
        if mode==palette.get('mode',mode):tokens[key]=color(value)
    if accent:tokens['accent.primary']=color(accent)
    surfaces=[tokens[k] for k in ('background.primary','surface.default','background.elevated')]
    for key in ('text.primary','text.secondary'):
        tokens[key]=readable(tokens[key],surfaces)
    tokens['text.onAccent']=readable(tokens['text.primary'],[tokens['accent.primary']])
    canonical={'background':'background.primary','surface':'surface.default','elevated':'background.elevated','border':'border.default','text':'text.primary','muted':'text.secondary','green':'accent.primary','teal':'accent.secondary','brightGreen':'accent.hover','ember':'status.error','amber':'status.warning','blue':'status.info'}
    for key,token in canonical.items():colors[key]=tokens[token]
    terminal=options.get('terminalPalette') or {}
    if not isinstance(terminal,dict): raise ValueError('Terminal palette must be an object.')
    for i,key in enumerate(ANSI):
        name=('terminal.' if i<8 else 'terminal.bright.')+NAMES[i%8]
        tokens[name]=color(terminal.get(name,palette.get('tokens',{}).get(name,colors[key])))
    if set(terminal)-{k for k in tokens if k.startswith('terminal.') }: raise ValueError('Unknown terminal color token.')
    family=options.get('fontFamily','JetBrainsMono Nerd Font')
    ui=options.get('uiFont','sans-serif')
    for name in (family,ui):
        if not isinstance(name,str) or not re.fullmatch(r'[\w .+-]{1,100}',name): raise ValueError('Invalid font family.')
    size=options.get('fontSize',11); opacity=options.get('opacity',1.0); radius=options.get('radius',12)
    for value,low,high in [(size,6,40),(opacity,.65,1),(radius,0,32)]:
        if isinstance(value,bool) or not isinstance(value,(int,float)) or not low<=value<=high: raise ValueError('Appearance value outside supported range.')
    icon=options.get('iconTheme','')
    if not isinstance(icon,str) or (icon and not re.fullmatch(r'[\w.+-]{1,80}',icon)): raise ValueError('Invalid icon theme name.')
    name=palette.get('name','CEDAR')
    if not isinstance(name,str) or not 1<=len(name)<=100:raise ValueError('Invalid palette name.')
    result={'name':name,'mode':mode,'tokens':tokens,'colors':colors,
            'font':{'family':family,'ui':ui,'size':size,'enabled':bool(options.get('fonts',False))},
            'opacity':opacity,'radius':radius,'iconTheme':icon}
    result['digest']=hashlib.sha256(json.dumps(result,sort_keys=True).encode()).hexdigest()
    return result

def presets():
    result = [{'id':'cedar','name':'CEDAR','mode':'dark'},{'id':'mist','name':'Morning Mist','mode':'light'},
              {'id':'dusk','name':'Forest Dusk','mode':'dark'}]
    for path in sorted((ROOT / 'themes/palettes').glob('*.json')):
        if path.stem == 'cedar':
            continue
        value = json.loads(path.read_text())
        result.append({'id': path.stem, 'name': value['name'], 'mode': value['mode']})
    return result

def preset(name):
    if name=='cedar': return {'name':'CEDAR','mode':'dark'}
    if name=='mist': return {'name':'Morning Mist','mode':'light'}
    if name=='dusk': return {'name':'Forest Dusk','mode':'dark','colors':{'green':'#b9bd8e','teal':'#8db4b4','background':'#14191b','surface':'#1d2528','elevated':'#283335'}}
    if name in {item['id'] for item in presets()}:
        return json.loads((ROOT / 'themes/palettes' / (name + '.json')).read_text())
    raise ValueError('Unknown preset.')
