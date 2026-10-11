import json, subprocess
rows=json.loads(subprocess.check_output(['hyprctl','-j','binds'],text=True))
items=[]
seen=set()
for row in rows:
    if not row.get('description'): continue
    mods=[name for bit,name in [(64,'Super'),(4,'Ctrl'),(8,'Alt'),(1,'Shift')] if row['modmask'] & bit]
    key=row.get('key') or ('Keycode '+str(row.get('keycode',0)))
    combo=' + '.join(mods+[key])
    desc=row['description']
    if row.get('release'): combo+=' (release)'
    if (combo,desc) in seen: continue
    seen.add((combo,desc));items.append({'keys':combo,'description':desc,'modifiers':row['modmask'],'key':key})

def sort_key(row):
    mask = row['modifiers']
    return (0 if mask & 64 else 1, mask.bit_count(),
            mask & ~64, row['key'].casefold(), row['description'].casefold())

print(json.dumps(sorted(items, key=sort_key)))
