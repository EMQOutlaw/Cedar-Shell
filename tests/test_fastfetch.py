"""Regression coverage for scripts/fastfetch_settings.py — the settings page's
helper. Each test pins one securitybot/reviewbot finding: config preservation,
baseline conflicts, symlink refusal, private/permissioned writes, test-mode
refusal, read-only get, and the JSONC reader's string safety."""

import json
import os
import stat
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import fastfetch_settings as ff  # noqa: E402


class Base(unittest.TestCase):
    def setUp(self):
        self.dir = Path(tempfile.mkdtemp(prefix="cedar-fastfetch-test-"))
        self.config = self.dir / "config.jsonc"
        self._old_config = ff.CONFIG
        self._old_env = {k: os.environ.get(k) for k in ("CEDAR_TEST", "FOXFIRE_TEST")}
        for key in self._old_env:
            os.environ.pop(key, None)
        self.addCleanup(self._restore)
        ff.CONFIG = self.config

    def _restore(self):
        ff.CONFIG = self._old_config
        for key, value in self._old_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def write(self, body, mode=0o600):
        self.config.write_text(body)
        os.chmod(self.config, mode)
        return body

    def model(self):
        model, error = ff.load_model()
        self.assertEqual(error, "")
        return model


class Preserve(Base):
    def test_unknown_module_options_and_formats_survive_a_save(self):
        """P1: saving may not destroy fields CEDAR does not manage."""
        original = {
            "logo": {"type": "none", "padding": {"top": 2, "right": 4}},
            "display": {"separator": " :: ", "color": {"keys": "1;2;3", "title": "red"}},
            "modules": [
                {"type": "os", "key": "My OS", "format": "{name}"},
                {"type": "custom", "key": "Custom", "format": "KEEP_ME"},
                {"type": "display"},
            ],
        }
        self.write(json.dumps(original))
        model = self.model()
        saved = ff.candidate(model)
        self.assertEqual(saved["display"]["separator"], " :: ")
        self.assertEqual(saved["display"]["color"]["title"], "red")
        self.assertEqual(saved["display"]["color"]["keys"], "1;2;3")  # the accent round-trips byte-for-byte
        self.assertEqual(saved["logo"]["type"], "none")
        self.assertEqual(saved["logo"]["padding"], {"top": 2, "right": 4})  # untouched
        by_type = {m.get("type") if isinstance(m, dict) else m: m for m in saved["modules"]}
        self.assertEqual(by_type["os"]["format"], "{name}")
        self.assertEqual(by_type["os"]["key"], "My OS")
        self.assertEqual(by_type["custom"]["format"], "KEEP_ME")
        self.assertIn("display", by_type)

    def test_relabel_sets_only_the_label_key(self):
        self.write(json.dumps({"modules": [{"type": "os", "key": "OS", "format": "{name}"}]}))
        model = self.model()
        model["rows"][0]["label"] = "System"
        saved = ff.candidate(model)
        self.assertEqual(saved["modules"][0], {"type": "os", "key": "SYSTEM", "format": "{name}"})

    def test_key_change_builds_a_fresh_module(self):
        self.write(json.dumps({"modules": [{"type": "os", "key": "OS", "format": "{name}"}]}))
        model = self.model()
        model["rows"][0]["key"] = "kernel"
        saved = ff.candidate(model)
        self.assertEqual(saved["modules"][0], {"type": "kernel", "key": "KERNEL"})

    def test_clearing_the_accent_removes_only_color_keys(self):
        self.write(json.dumps({"display": {"separator": "|", "color": {"keys": "1;2;3", "title": "red"}}}))
        model = self.model()
        model["accent"] = ""
        saved = ff.candidate(model)
        self.assertEqual(saved["display"], {"separator": "|", "color": {"title": "red"}})

    def test_unknown_logo_type_is_preserved_not_normalized(self):
        self.write(json.dumps({"logo": {"type": "sixel", "source": "~/art.png"}, "modules": []}))
        model = self.model()
        self.assertEqual(model["logo"]["kind"], "other")
        self.assertEqual(model["logo"]["type"], "sixel")
        saved = ff.candidate(model)
        self.assertEqual(saved["logo"], {"type": "sixel", "source": "~/art.png"})

    def test_ui_kinds_map_to_real_fastfetch_enums(self):
        self.write(json.dumps({"modules": []}))
        model = self.model()
        model["logo"] = {"kind": "ascii", "type": "", "source": str(self.dir / "l.txt"), "width": 30, "height": 16, "padding": 2,
                         "raw": {"source": "", "width": 28, "height": 14, "padding": 3}}
        self.assertEqual(ff.candidate(model)["logo"]["type"], "file-raw")
        # CEDAR offers no Image kind: image-rendering logo types are preserved
        model["logo"] = {"kind": "other", "type": "sixel", "source": "", "width": 28, "height": 14, "padding": 3, "raw": {}}
        self.assertEqual(ff.candidate(model)["logo"]["type"], "sixel")

    def test_string_logo_is_preserved(self):
        """Round 2: logo = "arch" (a bare string) is a valid config; a save may
        not turn it into {type: builtin}."""
        self.write(json.dumps({"logo": "arch", "modules": ["os"]}))
        model = self.model()
        self.assertEqual(model["logo"]["kind"], "other")
        self.assertEqual(ff.candidate(model)["logo"], "arch")

    def test_named_accent_colour_is_preserved_on_save(self):
        """Round 2: display.color.keys "red" is valid fastfetch that CEDAR
        cannot represent; clearing the (empty) accent field may not delete it."""
        self.write(json.dumps({"display": {"color": {"keys": "red", "title": "blue"}}, "modules": ["os"]}))
        model = self.model()
        self.assertEqual(model["accent"], "")
        saved = ff.candidate(model)
        self.assertEqual(saved["display"]["color"]["keys"], "red")
        self.assertEqual(saved["display"]["color"]["title"], "blue")

    def test_colors_object_is_replayed_not_replaced(self):
        """Round 2: a hand-configured colors row keeps its symbol and padding."""
        self.write(json.dumps({"modules": ["os", {"type": "colors", "symbol": "block", "paddingLeft": 5}]}))
        model = self.model()
        saved = ff.candidate(model)
        self.assertIn({"type": "colors", "symbol": "block", "paddingLeft": 5}, saved["modules"])

    def test_distinct_custom_rows_are_never_deduplicated(self):
        """Round 2: two custom modules with different formats are the user's
        data; deduplication by type deleted one of them."""
        self.write(json.dumps({"modules": ["os", {"type": "custom", "key": "ONE", "format": "KEEP_ONE"}, {"type": "custom", "key": "TWO", "format": "KEEP_TWO"}]}))
        model = self.model()
        saved = ff.candidate(model)
        self.assertEqual(len([m for m in saved["modules"] if isinstance(m, dict) and m.get("type") == "custom"]), 2)

    def test_untouched_padding_object_survives_and_changed_padding_keeps_siblings(self):
        """Review: fastfetch requires logo.padding as an object for file logos.
        An untouched padding dict replays verbatim; editing the left column
        updates only that key and keeps the user's top/right/bottom."""
        self.write(json.dumps({"logo": {"type": "file-raw", "source": "a.txt", "padding": {"top": 2, "left": 4, "right": 7}}, "modules": ["os"]}))
        model = self.model()
        saved = ff.candidate(model)  # only an unrelated label change below
        self.assertEqual(saved["logo"]["padding"], {"top": 2, "left": 4, "right": 7})
        model["logo"]["padding"] = 9
        self.assertEqual(ff.candidate(model)["logo"]["padding"], {"top": 2, "left": 9, "right": 7})

    def test_config_without_modules_key_gains_none(self):
        """Round 2: a config with no modules list must not gain an empty one
        when the readout is empty."""
        self.write(json.dumps({"logo": {"type": "none"}}))
        model = self.model()
        self.assertEqual(model["rows"], [])
        self.assertNotIn("modules", ff.candidate(model))

    def test_relabelled_string_module_becomes_the_object_form(self):
        """Round 3: relabeling a plain-string module must carry the label —
        the string replay silently dropped it."""
        self.write(json.dumps({"modules": ["os"]}))
        model = self.model()
        model["rows"][0]["label"] = "System"
        saved = ff.candidate(model)
        self.assertEqual(saved["modules"], [{"type": "os", "key": "SYSTEM"}])
        model["rows"][0]["label"] = model["rows"][0]["olabel"]
        self.assertEqual(ff.candidate(model)["modules"], ["os"])  # unchanged stays the string

    def test_crlf_config_saves_without_a_false_conflict(self):
        """Round 4: the baseline hashes raw bytes — a CRLF config must not
        fail every save with a phantom external change."""
        self.write('{\r\n  "modules": ["os"]\r\n}\r\n')
        model = self.model()
        with mock.patch.object(ff, "preview", return_value=None):
            ff.save(model)  # must not raise
        self.assertIn('"os"', self.config.read_text())

    def test_symlink_swapped_in_during_prepare_is_not_destroyed(self):
        """Round 4: the commit-boundary revalidation checks the file type as
        well as the content."""
        target = self.dir / "elsewhere.jsonc"
        target.write_text(json.dumps({"modules": ["os"]}))
        self.write(json.dumps({"modules": ["os"]}))
        model = self.model()
        self.config.unlink(); self.config.symlink_to(target)
        with mock.patch.object(ff, "preview", return_value=None):
            with self.assertRaises(RuntimeError) as caught:
                ff.save(model)
        self.assertIn("symlink", str(caught.exception))
        self.assertTrue(self.config.is_symlink())

    def test_string_color_semantics(self):
        """Round 8: fastfetch's string display.color colours keys AND title.
        An untouched string survives verbatim; an explicit accent edit keeps
        the original title colour alongside the new keys."""
        self.write(json.dumps({"display": {"color": "red"}, "modules": ["os"]}))
        model = self.model()
        self.assertTrue(model["colorWasString"])
        self.assertEqual(ff.candidate(model)["display"]["color"], "red")  # unrelated edit: untouched
        model["accent"] = "#aabbcc"
        saved = ff.candidate(model)
        self.assertEqual(saved["display"]["color"], {"keys": "170;187;204", "title": "red"})
        # a numeric string that is left alone also stays a string
        self.write(json.dumps({"display": {"color": "1;2;3"}, "modules": ["os"]}))
        model = self.model()
        self.assertEqual(ff.candidate(model)["display"]["color"], "1;2;3")
        # re-saving the colour the config already carries is not an edit
        model["accent"] = "#010203"
        self.assertEqual(ff.candidate(model)["display"]["color"], "1;2;3")
        # clearing removes the keys override but keeps the string form's title colour
        model["accent"] = ""
        self.assertEqual(ff.candidate(model)["display"]["color"], {"title": "1;2;3"})

    def test_string_in_jsonc_with_comma_bracket_survives(self):
        """P2: the trailing-comma pass must be string-aware."""
        parsed = json.loads(ff.strip_comments('{"a":"A,]B,}C","modules":["os",]}'))
        self.assertEqual(parsed["a"], "A,]B,}C")
        self.assertEqual(parsed["modules"], ["os"])


class Safety(Base):
    def setUp(self):
        super().setUp()
        self.installed = mock.patch.object(ff, "installed", return_value=True).start()
        self.addCleanup(mock.patch.stopall)

    def test_save_refuses_when_the_file_changed_underneath(self):
        """P1: a stale baseline is a conflict, never a silent overwrite."""
        first = self.write(json.dumps({"modules": ["os"]}))
        model = self.model()
        self.write(json.dumps({"modules": ["os", "kernel"], "display": {"separator": "ext"}}))
        with mock.patch.object(ff, "preview", return_value=None):
            with self.assertRaises(RuntimeError) as caught:
                ff.save(model)
        self.assertIn("changed since it was read", str(caught.exception))
        # the external edit is still on disk, untouched
        self.assertIn("ext", self.config.read_text())
        self.assertNotEqual(self.config.read_text(), first)

    def test_save_refuses_a_symlinked_config(self):
        target = self.dir / "real.jsonc"
        target.write_text(json.dumps({"modules": ["os"]}))
        self.config.symlink_to(target)
        model, error = ff.load_model()
        self.assertEqual(error, "")
        with mock.patch.object(ff, "preview", return_value=None):
            with self.assertRaises(RuntimeError) as caught:
                ff.save(model)
        self.assertIn("symlink", str(caught.exception))
        self.assertTrue(self.config.is_symlink())

    def test_save_preserves_restrictive_permissions(self):
        """P2: a 0600 config (and its backup) must not widen to 0644."""
        self.write(json.dumps({"modules": ["os"]}), mode=0o600)
        model = self.model()
        with mock.patch.object(ff, "preview", return_value=None):
            ff.save(model)
        self.assertEqual(stat.S_IMODE(self.config.stat().st_mode), 0o600)
        backup = self.config.with_name(self.config.name + ".bak")
        self.assertTrue(backup.exists())
        self.assertEqual(stat.S_IMODE(backup.stat().st_mode), 0o600)

    def test_save_is_refused_under_a_test_environment(self):
        """P2: the helper boundary refuses writes, not only the QML layer."""
        for flag in ("CEDAR_TEST", "FOXFIRE_TEST"):
            os.environ[flag] = "1"
            try:
                self.write(json.dumps({"modules": ["os"]}))
                model = self.model()
                with self.assertRaises(RuntimeError) as caught:
                    ff.save(model)
                self.assertIn("test", str(caught.exception).lower())
            finally:
                os.environ.pop(flag)

    def test_get_never_generates_a_config(self):
        """get() is read-only: a missing config is reported, not created."""
        with mock.patch.object(ff, "run", side_effect=AssertionError("get must not run fastfetch")):
            data = ff.get()
        self.assertIsNone(data["model"])
        self.assertTrue(data["error"])
        self.assertFalse(self.config.exists())

    def test_backup_holds_the_pre_save_content(self):
        self.write(json.dumps({"modules": ["os"]}))
        model = self.model()
        model["rows"].append({"kind": "module", "key": "kernel", "label": "KERNEL", "olabel": "KERNEL", "fixed": False, "orig": None})
        with mock.patch.object(ff, "preview", return_value=None):
            ff.save(model)
        backup = json.loads(self.config.with_name(self.config.name + ".bak").read_text())
        self.assertEqual(backup, {"modules": ["os"]})
        self.assertEqual([m for m in json.loads(self.config.read_text())["modules"]], ["os", {"type": "kernel", "key": "KERNEL"}])


if __name__ == "__main__":
    unittest.main()
