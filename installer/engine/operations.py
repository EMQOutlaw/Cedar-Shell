"""Explicit operations with explicit state, and a runner that remembers.

Every operation has an id, a title, a description and a state the UI can
show; the runner writes the whole list to a state file after each change, so
an interrupted installation is recognized on the next start and can resume,
start over or restore. Operations in the same `group` are independent of
each other and run together; everything else is sequential.
"""
from concurrent.futures import ThreadPoolExecutor
import json
import os
from pathlib import Path
import threading
import time
import traceback

PENDING, RUNNING, COMPLETE, WARNING, FAILED, SKIPPED = 'pending', 'running', 'complete', 'warning', 'failed', 'skipped'
FINAL = {COMPLETE, WARNING, SKIPPED}


class Skip(Exception):
    """Raised by an operation that has nothing to do here; the reason is shown."""


class Warn(Exception):
    """Raised by an operation that finished but wants the person to know something."""


class Failed(RuntimeError):
    def __init__(self, operation, message, rolled_back=False):
        super().__init__(message)
        self.operation = operation
        self.rolled_back = rolled_back


class Operation:
    def __init__(self, id, title, description, run, verify=None, rollback=None, optional=False, group=''):
        self.id, self.title, self.description = id, title, description
        self._run, self._verify, self._rollback = run, verify, rollback
        self.optional, self.group = optional, group
        self.state, self.progress, self.detail, self.error = PENDING, 0.0, '', ''
        self.started_at, self.finished_at, self.rolled_back = 0.0, 0.0, False

    def to_dict(self):
        return {'id': self.id, 'title': self.title, 'description': self.description, 'state': self.state, 'progress': self.progress,
                'detail': self.detail, 'error': self.error, 'optional': self.optional, 'group': self.group,
                'startedAt': self.started_at, 'finishedAt': self.finished_at, 'rolledBack': self.rolled_back}

    def load(self, row):
        for key in ('state', 'progress', 'detail', 'error'):
            if key in row:
                setattr(self, key, row[key])
        self.started_at = row.get('startedAt', 0.0); self.finished_at = row.get('finishedAt', 0.0); self.rolled_back = row.get('rolledBack', False)

    def run(self, ctx):
        return self._run(ctx, self)

    def verify(self, ctx):
        return True if self._verify is None else self._verify(ctx, self)

    def rollback(self, ctx):
        if self._rollback is None:
            return False
        self._rollback(ctx, self)
        return True


class Runner:
    def __init__(self, operations, state_path, log, emit=None, version='', options=None, run_id=''):
        self.operations = list(operations)
        self.state_path = Path(state_path)
        self.log = log
        self.emit = emit or (lambda event, data: None)
        self.version = version
        self.options = options or {}
        self.run_id = run_id
        self.started_at = 0.0
        self.finished = False
        self.backup = ''
        self.extra = {}
        self._lock = threading.RLock()

    # -- state -----------------------------------------------------------
    def by_id(self, op_id):
        return next((op for op in self.operations if op.id == op_id), None)

    def to_dict(self):
        return {'format': 1, 'runId': self.run_id, 'version': self.version, 'options': self.options, 'startedAt': self.started_at,
                'updatedAt': time.time(), 'finished': self.finished, 'backup': self.backup, 'log': str(self.log.path) if self.log else '',
                'operations': [op.to_dict() for op in self.operations], **self.extra}

    def save(self):
        with self._lock:
            self.state_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
            temporary = self.state_path.with_name(self.state_path.name + '.' + str(os.getpid()) + '.tmp')
            temporary.write_text(json.dumps(self.to_dict(), indent=2))
            os.chmod(temporary, 0o600)
            os.replace(temporary, self.state_path)

    def restore_from(self, state):
        if not state:
            return
        self.run_id = state.get('runId', self.run_id) or self.run_id
        self.started_at = state.get('startedAt', 0.0)
        self.backup = state.get('backup', '')
        for row in state.get('operations', []):
            op = self.by_id(row.get('id'))
            if op:
                op.load(row)
                if op.state == RUNNING:
                    op.state, op.detail = PENDING, 'Interrupted last time; runs again'

    def update(self, op, state=None, progress=None, detail=None, error=None):
        with self._lock:
            if state is not None: op.state = state
            if progress is not None: op.progress = max(0.0, min(1.0, float(progress)))
            if detail is not None: op.detail = detail
            if error is not None: op.error = error
            self.save()
            self.emit('operation', op.to_dict())

    def summary(self):
        done = sum(1 for op in self.operations if op.state in FINAL)
        return {'completed': done, 'total': len(self.operations), 'failed': [op.id for op in self.operations if op.state == FAILED],
                'warnings': [op.id for op in self.operations if op.state == WARNING], 'skipped': [op.id for op in self.operations if op.state == SKIPPED]}

    # -- execution -------------------------------------------------------
    def run(self, ctx, resume=False):
        if not self.started_at:
            self.started_at = time.time()
        self.finished = False
        self.save()
        groups = []
        for op in self.operations:
            if op.group and groups and groups[-1][0] == op.group:
                groups[-1][1].append(op)
            else:
                groups.append((op.group, [op]))
        for group, ops in groups:
            todo = [op for op in ops if not (resume and op.state in FINAL)]
            for op in ops:
                if op not in todo:
                    self.emit('operation', op.to_dict())
            if not todo:
                continue
            if len(todo) == 1:
                self._execute(ctx, todo[0])
            else:
                with ThreadPoolExecutor(max_workers=len(todo)) as pool:
                    futures = [pool.submit(self._execute, ctx, op) for op in todo]
                    errors = []
                    for future in futures:
                        try:
                            future.result()
                        except Failed as error:
                            errors.append(error)
                    if errors:
                        raise errors[0]
        self.finished = True
        self.save()
        return self.summary()

    def _execute(self, ctx, op):
        op.started_at = time.time(); op.rolled_back = False
        self.update(op, state=RUNNING, progress=0.0, detail='', error='')
        if self.log: self.log.info('start ' + op.title, op.id)
        try:
            op.run(ctx)
            if not op.verify(ctx):
                raise RuntimeError(op.title + ' did not verify')
            op.finished_at = time.time()
            self.update(op, state=COMPLETE, progress=1.0)
            if self.log: self.log.info('complete ' + op.title, op.id)
        except Skip as skip:
            op.finished_at = time.time()
            self.update(op, state=SKIPPED, progress=1.0, detail=str(skip))
            if self.log: self.log.info('skipped ' + op.title + ': ' + str(skip), op.id)
        except Warn as warn:
            op.finished_at = time.time()
            self.update(op, state=WARNING, progress=1.0, detail=str(warn))
            if self.log: self.log.warn(op.title + ': ' + str(warn), op.id)
        except BaseException as error:
            message = str(error) or error.__class__.__name__
            op.finished_at = time.time()
            if self.log:
                self.log.error(op.title + ' failed: ' + message, op.id)
                self.log.write('debug', traceback.format_exc(), op.id)
            rolled = False
            try:
                rolled = op.rollback(ctx)
                if rolled and self.log: self.log.info('rolled back ' + op.title, op.id)
            except BaseException as undo:
                if self.log: self.log.error('rollback of ' + op.title + ' failed: ' + str(undo), op.id)
            op.rolled_back = rolled
            self.update(op, state=FAILED, error=message)
            raise Failed(op, message, rolled) from error


def load_state(path):
    path = Path(path)
    if not path.is_file():
        return None
    try:
        state = json.loads(path.read_text())
    except (OSError, ValueError):
        return None
    return state if isinstance(state, dict) and state.get('format') == 1 else None


def describe_state(state):
    """What a previous run left behind, or None when there is nothing to resume."""
    if not state or state.get('finished'):
        return None
    ops = state.get('operations', [])
    done = sum(1 for op in ops if op.get('state') in FINAL)
    failed = [op for op in ops if op.get('state') == FAILED]
    running = [op for op in ops if op.get('state') == RUNNING]
    if not done and not failed and not running:
        return None
    return {'runId': state.get('runId', ''), 'version': state.get('version', ''), 'startedAt': state.get('startedAt', 0.0), 'completed': done,
            'total': len(ops), 'failed': [op['id'] for op in failed], 'interruptedAt': running[0]['id'] if running else (failed[0]['id'] if failed else ''),
            'backup': state.get('backup', ''), 'log': state.get('log', ''), 'operations': ops}
