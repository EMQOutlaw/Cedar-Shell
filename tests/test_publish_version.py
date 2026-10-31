import datetime
import unittest
from scripts.publish_version import next_version, update_spec

SPEC = '''# %changelog is kept in step by scripts/publish_version.py
Name:           cedar-shell
Version:        1.17
Release:        3%{?dist}
Summary:        CEDAR

%changelog
* Sat Oct 31 2026 Someone <s@example.org> - 1.17-3
- Older entry
'''

class Versions(unittest.TestCase):
    def test_two_part_increment_and_retry(self):
        self.assertEqual(next_version('1.3', ['Add picker']), '1.4')
        self.assertEqual(next_version('1.3', ['chore(release): publish CEDAR 1.4', 'Add picker']), '1.4')
        self.assertEqual(next_version('1.3', ['Next change', 'chore(release): publish CEDAR 1.4', 'Add picker']), '1.5')
    def test_multiple_changes_and_no_changes(self):
        self.assertEqual(next_version('1.3', []), '1.3')
        self.assertEqual(next_version('1.3', ['a', 'b', 'c']), '1.6')
    def test_invalid_version(self):
        with self.assertRaises(ValueError): next_version('0.1.3', [])
    def test_spec_version_release_and_changelog_advance_together(self):
        text = update_spec(SPEC, '1.18', datetime.date(2026, 11, 2))
        self.assertIn('\nVersion:        1.18\n', text); self.assertIn('\nRelease:        1%{?dist}\n', text)
        self.assertTrue(text.startswith('# %changelog is kept'), 'the comment mentioning %changelog is not the section')
        head = text[text.index('\n%changelog\n'):]
        self.assertTrue(head.startswith('\n%changelog\n* Mon Nov 02 2026 CEDAR release automation <41898282+github-actions[bot]@users.noreply.github.com> - 1.18-1\n- Automated release 1.18\n\n* Sat Oct 31 2026'), head)
        self.assertEqual(update_spec(text, '1.18'), text, 'a retry of the same version changes nothing')
