"""Structured installer logs: one JSON-lines file per run, never a secret.

~/.local/state/cedar/installer/logs/<run id>.jsonl. Each record carries a
timestamp, a level, the operation it belongs to and a redacted message.
Environment variables are never written; command lines are logged by name
and arguments only after redaction.
"""
import json
import os
from pathlib import Path
import re
import socket
import time
import uuid

SECRET = re.compile(r'(?i)((?:password|passwd|token|secret|authorization|api[_-]?key|bearer)\s*[:=]\s*)\S+')
KEYS = re.compile(r'\b(?:gh[pousr]_[A-Za-z0-9_]+|github_pat_[A-Za-z0-9_]+|sk-[A-Za-z0-9_-]+)\b')


def redact(text, home=None):
    text = str(text)
    if home:
        text = text.replace(str(home), '~')
    try:
        text = text.replace(socket.gethostname(), '[host]')
    except OSError:
        pass
    text = SECRET.sub(r'\1[redacted]', text)
    text = KEYS.sub('[redacted]', text)
    return text


class RunLog:
    def __init__(self, directory, home=None, run_id=None):
        self.directory = Path(directory)
        self.run_id = run_id or time.strftime('%Y%m%dT%H%M%S') + '-' + uuid.uuid4().hex[:6]
        self.path = self.directory / (self.run_id + '.jsonl')
        self.home = home
        self.listeners = []
        self.lines = []
        self._stream = None

    def open(self):
        self.directory.mkdir(parents=True, exist_ok=True, mode=0o700)
        self._stream = self.path.open('a', encoding='utf-8')
        os.chmod(self.path, 0o600)
        return self

    def close(self):
        if self._stream:
            self._stream.close(); self._stream = None

    def write(self, level, message, operation='', **fields):
        record = {'at': time.time(), 'level': level, 'operation': operation, 'message': redact(message, self.home)}
        for key, value in fields.items():
            record[key] = redact(json.dumps(value) if not isinstance(value, str) else value, self.home)
        self.lines.append(record)
        if self._stream:
            self._stream.write(json.dumps(record, ensure_ascii=False) + '\n'); self._stream.flush()
        for listener in self.listeners:
            listener(record)
        return record

    def info(self, message, operation='', **fields): return self.write('info', message, operation, **fields)
    def warn(self, message, operation='', **fields): return self.write('warning', message, operation, **fields)
    def error(self, message, operation='', **fields): return self.write('error', message, operation, **fields)
    def output(self, line, operation=''): return self.write('output', line, operation)


def latest(directory):
    files = sorted(Path(directory).glob('*.jsonl'))
    return files[-1] if files else None
