"""Best-effort local diagnostic redaction; always require human review before sharing."""
import re,socket
from pathlib import Path

def redact(text):
    text=str(text).replace(str(Path.home()),'~').replace(socket.gethostname(),'[host]')
    text=re.sub(r'(?i)((?:password|passwd|token|secret|authorization|api[_-]?key)\s*[:=]\s*)\S+',r'\1[redacted]',text)
    text=re.sub(r'\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+)\b','[redacted]',text)
    text=re.sub(r'\b(?:[0-9]{1,3}\.){3}[0-9]{1,3}\b','[address]',text)
    text=re.sub(r'(?i)\b(?:[0-9a-f]{2}:){5}[0-9a-f]{2}\b','[device]',text)
    text=re.sub(r'[\w.+-]+@[\w.-]+\.[A-Za-z]{2,}','[email]',text)
    return text
