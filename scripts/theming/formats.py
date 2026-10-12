"""Small lossless edits. Unsupported/ambiguous syntax is refused, never normalized."""
import configparser
import json
import re
import tomllib


def ini_validate(text):
    parser=configparser.RawConfigParser(strict=True,interpolation=None,delimiters=('=',),allow_no_value=False)
    parser.optionxform=str
    parser.read_string(text)

def ini_patch(text, updates):
    """Edit individual INI keys, preserving other keys, comments and spacing."""
    if text.strip(): ini_validate(text)
    lines=text.splitlines(keepends=True)
    for section,values in updates.items():
        header=re.compile(r'^\s*\['+re.escape(section)+r'\]\s*(?:[#;].*)?$')
        start=next((i for i,line in enumerate(lines) if header.match(line.strip())),None)
        if start is None:
            if lines and not lines[-1].endswith('\n'): lines[-1]+='\n'
            lines.extend(['\n['+section+']\n']);start=len(lines)-1
        end=next((i for i in range(start+1,len(lines)) if re.match(r'^\s*\[',lines[i])),len(lines))
        for key,value in values.items():
            found=[i for i in range(start+1,end) if re.match(r'^\s*'+re.escape(key)+r'\s*=',lines[i])]
            if len(found)>1: raise ValueError('Duplicate setting: '+key)
            new=key+'='+str(value)+'\n'
            if found: lines[found[0]]=new
            else: lines.insert(end,new);end+=1
    result=''.join(lines);ini_validate(result);return result

def block(text, body, marker='CEDAR APPLICATION THEME', comment='#'):
    start=comment+' BEGIN '+marker;end=comment+' END '+marker
    if text.count(start)!=text.count(end) or text.count(start)>1: raise ValueError('Broken CEDAR managed section.')
    new=start+'\n'+body.rstrip()+'\n'+end
    if start in text:
        a=text.index(start);b=text.index(end,a)+len(end)
        return text[:a]+new+text[b:]
    return text+('' if not text or text.endswith('\n') else '\n')+'\n'+new+'\n'

def toml_patch(text, updates):
    """Patch scalar keys in explicit TOML tables. Refuse dotted/inline collisions."""
    parsed=tomllib.loads(text)
    lines=text.splitlines(keepends=True)
    for table,values in updates.items():
        target=parsed
        for part in table.split('.') if table else []:
            target=target.get(part,{})
            if not isinstance(target,dict): raise ValueError('Non-table TOML setting: '+table)
        header='['+table+']'
        positions=[i for i,line in enumerate(lines) if line.strip().split('#',1)[0].strip()==header]
        if not table:start=-1
        elif positions:start=positions[0]
        else:
            # Existing inline/dotted representation needs a native config editor.
            if target: raise ValueError('Inline or dotted TOML table needs manual migration: '+table)
            if lines and not lines[-1].endswith('\n'):lines[-1]+='\n'
            lines.append('\n'+header+'\n');start=len(lines)-1
        end=next((i for i in range(start+1,len(lines)) if re.match(r'^\s*\[',lines[i])),len(lines))
        for key,value in values.items():
            found=[i for i in range(start+1,end) if re.match(r'^\s*'+re.escape(key)+r'\s*=',lines[i])]
            new=key+' = '+json.dumps(value,ensure_ascii=False)+'\n'
            if found:
                i=found[0]
                # Only replace a single-line scalar: complex structures are refused.
                try:tomllib.loads(lines[i])
                except tomllib.TOMLDecodeError:raise ValueError('Multiline TOML setting needs manual migration: '+key)
                lines[i]=new
            elif key in target:raise ValueError('Ambiguous TOML setting: '+key)
            else:lines.insert(end,new);end+=1
    result=''.join(lines);tomllib.loads(result);return result


def jsonc_tokens(text):
    # A real scanner retains comment/string boundaries, including URLs and escapes.
    tokens=[];i=0
    while i<len(text):
        if text[i].isspace():i+=1;continue
        if text.startswith('//',i):
            n=text.find('\n',i);i=len(text) if n<0 else n;continue
        if text.startswith('/*',i):
            n=text.find('*/',i+2)
            if n<0:raise ValueError('Unclosed JSON comment')
            i=n+2;continue
        a=i
        if text[i]=='"':
            i+=1
            while i<len(text):
                if text[i]=='\\':i+=2;continue
                if text[i]=='"':i+=1;break
                i+=1
            else:raise ValueError('Unclosed JSON string')
        elif text[i] in '{}[]:,':i+=1
        else:
            while i<len(text) and text[i] not in ',]} \t\r\n':i+=1
        tokens.append((text[a:i],a,i))
    return tokens


def jsonc_load(text):
    tokens=jsonc_tokens(text)
    clean=''.join(t[0] for i,t in enumerate(tokens) if not (t[0]==',' and i+1<len(tokens) and tokens[i+1][0] in ('}',']')))
    return json.loads(clean or '{}')

def jsonc_patch(text, updates):
    """Losslessly replace top-level JSONC values using a token scanner."""
    tokens=jsonc_tokens(text)
    obj=jsonc_load(text)
    if not isinstance(obj,dict):raise ValueError('Expected a JSON object')
    if not tokens:return json.dumps(updates,indent=2)+'\n'
    edits=[];existing=set();depth=0
    for n,(value,a,b) in enumerate(tokens):
        if value in ('{','['):depth+=1
        elif value in ('}',']'):depth-=1
        elif depth==1 and value.startswith('"') and n+1<len(tokens) and tokens[n+1][0]==':':
            key=json.loads(value)
            if key in existing:raise ValueError('Duplicate JSON key: '+key)
            existing.add(key)
            if key not in updates or obj.get(key)==updates[key]:continue
            j=n+2;begin=tokens[j][1];nest=0
            while j<len(tokens):
                v=tokens[j][0]
                if nest==0 and v in (',','}'):break
                if v in ('{','['):nest+=1
                elif v in ('}',']'):nest-=1
                j+=1
            edits.append((begin,tokens[j-1][2],json.dumps(updates[key],ensure_ascii=False)))
    additions={k:v for k,v in updates.items() if k not in existing}
    if additions:
        end=tokens[-1][1];previous=tokens[-2][0] if len(tokens)>1 else '{'
        prefix='' if previous in ('{',',') else ','
        edits.append((end,end,prefix+'\n'+',\n'.join('  '+json.dumps(k)+': '+json.dumps(v,ensure_ascii=False) for k,v in additions.items())+'\n'))
    for a,b,value in sorted(edits,reverse=True):text=text[:a]+value+text[b:]
    return text
