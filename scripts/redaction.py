"""Best-effort local diagnostic redaction; always require human review before sharing."""
import getpass,ipaddress,re,socket
from pathlib import Path

KEY=r'(?:password|passwd|passphrase|token|secret|api[_-]?key|psk|ssid)'
VALUE=r'"[^"\r\n]*"|\'[^\'\r\n]*\'|[^\s"\',;&}]+'
AUTH=re.compile(r'(?i)(\bauthorization["\']?\s*[:=]\s*["\']?)(?:(?:bearer|basic|token|digest|negotiate|ntlm)\s+)?[^\s"\',;]+')
BEARER=re.compile(r'(?i)(\bbearer\s+)[A-Za-z0-9._~+/=-]+')
KEYED=re.compile(r'(?i)(\w*'+KEY+r'\w*["\']?\s*[:=]\s*)('+VALUE+')')
FLAG=re.compile(r'(?i)(--[\w-]*'+KEY+r'[\w-]*\s+)(?!-)('+VALUE+')')
USERINFO=re.compile(r'(?i)\b([a-z][a-z0-9+.-]*://)[^\s/@]+@')
IPV6=re.compile(r'(?i)(?<![\w:.])(?:[0-9a-f]{0,4}:){2,7}(?:(?:[0-9]{1,3}\.){3}[0-9]{1,3}|[0-9a-f]{1,4})?(?:%[\w.-]+)?(?![\w.])')

def _value(match):
    value=match.group(2)
    quote=value[0] if value[:1] in '"\'' else ''
    return match.group(1)+quote+'[redacted]'+quote

def _ipv6(match):
    text=match.group(0)
    for end in (len(text),len(text.rstrip(':'))):
        candidate=text[:end]
        try:ipaddress.IPv6Address(candidate.split('%')[0])
        except ValueError:continue
        if re.search(r'[0-9a-f]',candidate,re.I):return '[address]'+text[end:]
    return text

def redact(text):
    text=str(text).replace(str(Path.home()),'~').replace(socket.gethostname(),'[host]')
    try:user=getpass.getuser()
    except Exception:user=''
    if len(user)>=3:text=re.sub(r'(?<![\w.-])'+re.escape(user)+r'(?![\w-])','[user]',text)
    text=USERINFO.sub(r'\1[redacted]@',text)
    text=AUTH.sub(r'\1[redacted]',text)
    text=BEARER.sub(r'\1[redacted]',text)
    text=KEYED.sub(_value,text)
    text=FLAG.sub(_value,text)
    text=re.sub(r'\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+)\b','[redacted]',text)
    text=re.sub(r'(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b','[device]',text)
    text=IPV6.sub(_ipv6,text)
    text=re.sub(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b','[address]',text)
    text=re.sub(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}','[email]',text)
    return text
