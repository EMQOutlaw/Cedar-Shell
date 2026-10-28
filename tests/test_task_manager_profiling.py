"""A missing collector must not appear to be a successful lightweight workload."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('task_manager_session', ROOT / 'tools/profiling/task_manager_session.py')
fixture = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixture)


def row(pid, parent, name, start=1):
    return {'pid': pid, 'parent': parent, 'name': name, 'start': start}


def sample(*rows):
    return {'processesDetail': list(rows)}


class FixtureAccounting(unittest.TestCase):
    def test_requires_real_collector_in_every_sample(self):
        app = row(100, 1, 'cedar-task-mana')
        collector = row(101, 100, 'cedar-taskd')
        for samples in ([], [sample(app)], [sample(app, collector), sample(app)]):
            with self.subTest(samples=samples):
                self.assertFalse(fixture.fixture_scope(samples, (100, 1))[1])

    def test_remembers_reparented_collector_and_helpers_without_shell_processes(self):
        app = row(100, 1, 'cedar-task-mana')
        collector = row(101, 100, 'cedar-taskd')
        helper = row(102, 101, 'fixture-helper')
        shell = row(200, 1, 'qs')
        rows = [sample(app, collector, helper, shell),
                sample(app, row(101, 1, 'cedar-taskd'), row(102, 1, 'fixture-helper'), shell)]
        identities, valid = fixture.fixture_scope(rows, (100, 1))
        self.assertTrue(valid)
        self.assertEqual(identities, {(100, 1), (101, 1), (102, 1)})

    def test_reused_pid_cannot_satisfy_collector_workload(self):
        app = row(100, 1, 'cedar-task-mana')
        rows = [sample(app, row(101, 100, 'cedar-taskd')),
                sample(app, row(101, 1, 'cedar-taskd', start=2))]
        identities, valid = fixture.fixture_scope(rows, (100, 1))
        self.assertFalse(valid)
        self.assertNotIn((101, 2), identities)


if __name__ == '__main__':
    unittest.main()
