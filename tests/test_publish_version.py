import unittest
from scripts.publish_version import next_version

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
