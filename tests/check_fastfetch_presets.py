#!/usr/bin/env python3
"""Settings › Fastfetch presets: the interaction check. Mounts the real page
offscreen (CEDAR_TEST=1 — reads allowed, writes refused), clicks an actual
preset button in the rendered Presets section, and verifies the draft, the
Save bar and the live specimen all follow. No user config is ever written."""
from pathlib import Path
import os, re, shutil, subprocess, sys, tempfile

ROOT = Path(__file__).resolve().parents[1]
HARNESS = '''
import QtQuick
import QtTest
import Quickshell
import "modules"
import "services"
import "components"

ShellRoot {
    FloatingWindow {
        id: window
        visible: true
        implicitWidth: 1200
        implicitHeight: 900
        FastfetchSettings { id: page; anchors.fill: parent; active: true }
    }
    TestCase {
        id: tests
        name: "FastfetchPresets"
        when: window.visible
        function named(item, name) {
            if (item.objectName === name) return item;
            for (const child of item.children || []) {
                const found = named(child, name);
                if (found) return found;
            }
            return null;
        }
        function presetButtons(page) {
            const cell = named(page, "fastfetchPresets");
            if (!cell) return [];
            const out = [];
            const walk = item => {
                if (item instanceof StationButton) out.push(item);
                for (const child of item.children || []) walk(child);
            };
            walk(cell);
            return out;
        }
        function test_preset_click_loads_draft_and_specimen() {
            tryCompare(Fastfetch, "ready", true, 30000);
            verify(Fastfetch.installed, "fastfetch is installed in the harness");
            verify(Fastfetch.presets.length > 0, "presets are listed");
            const before = Fastfetch.previewText;
            const buttons = presetButtons(page);
            verify(buttons.length === Fastfetch.presets.length, "every preset has a button");
            const target = buttons.find(b => b.text === "neofetch");
            verify(target !== undefined, "the neofetch preset button exists");
            verify(target.enabled, "preset buttons are enabled");
            target.clicked();
            // The draft becomes the preset: dirty, Save enabled, specimen follows.
            tryCompare(Fastfetch, "dirty", true, 30000);
            tryVerify(() => Fastfetch.previewText !== "" && Fastfetch.previewText !== before, 30000,
                      "the specimen shows the preset's own readout");
            verify((Fastfetch.draft.rows || []).some(r => r.key === "title"), "the preset draft carries the preset's rows");
            verify(!Fastfetch.error && !Fastfetch.previewError, "no errors after the preset load");
            // Revert drops the preset: back to the committed model, not dirty.
            Fastfetch.revert();
            tryCompare(Fastfetch, "dirty", false, 30000);
            console.log("PASS: fastfetch preset click loads the draft, the specimen follows, revert restores");
        }
        function test_preset_save_is_refused_under_test() {
            tryCompare(Fastfetch, "ready", true, 30000);
            const buttons = presetButtons(page);
            const target = buttons.find(b => b.text === "neofetch");
            target.clicked();
            tryCompare(Fastfetch, "dirty", true, 30000);
            Fastfetch.save();
            tryVerify(() => Fastfetch.message.indexOf("refused") !== -1, 30000,
                      "the page reports the refused save");
            verify(!Fastfetch.saving, "nothing was written");
            console.log("PASS: save under test mode is refused by the page");
        }
    }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='cedar-ff-preset-') as tmp:
        p = Path(tmp)
        source = p / 'shell'
        shutil.copytree(ROOT, source, ignore=shutil.ignore_patterns('__pycache__', '.git'))
        runtime = p / 'runtime'; runtime.mkdir(mode=0o700)
        # A hermetic config fixture: the page reads a real model, and the save
        # refusal is proven against a file nothing else touches.
        fixture = p / 'config' / 'fastfetch'; fixture.mkdir(parents=True)
        (fixture / 'config.jsonc').write_text('{"logo": {"type": "builtin"}, "modules": ["os", "kernel"]}\n')
        (source / 'preview.qml').write_text(HARNESS)
        env = {**os.environ, 'CEDAR_TEST': '1', 'QT_QPA_PLATFORM': 'offscreen', 'QT_QPA_PLATFORMTHEME': 'basic',
               'QT_QUICK_CONTROLS_STYLE': 'Basic', 'QT_QUICK_BACKEND': 'software', 'QSG_RENDER_LOOP': 'basic',
               'XDG_RUNTIME_DIR': str(runtime), 'XDG_CONFIG_HOME': str(p / 'config'), 'XDG_STATE_HOME': str(p / 'state')}
        try:
            result = subprocess.run(['qs', '-p', str(source / 'preview.qml')], env=env, capture_output=True, text=True, timeout=180)
        except subprocess.TimeoutExpired as error:
            print(error.stdout or '', error.stderr or '')
            raise SystemExit('Fastfetch preset checks timed out')
        output = result.stdout + result.stderr
        ok = ('PASS: fastfetch preset click loads the draft' in output
              and 'PASS: save under test mode is refused' in output)
        bad = re.search(r'Quickshell has crashed|Failed to load configuration|ReferenceError|TypeError|Binding loop|is not defined|Unable to assign|FAIL!|Actual *:|FAIL:', output)
        if result.returncode or not ok or bad:
            print(output)
            raise SystemExit(1)
        print('PASS: fastfetch presets — real button click loads the draft, the specimen follows, revert restores, save refused under test')

if __name__ == '__main__':
    main()
