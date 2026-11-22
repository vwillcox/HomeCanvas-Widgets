#!/usr/bin/env python3
"""The checks, checked: python3 -m unittest tools/test_catalogue.py"""

import json
import os
import shutil
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import catalogue  # noqa: E402

PNG = (
    b"\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR"
    + (640).to_bytes(4, "big")
    + (400).to_bytes(4, "big")
    + b"\x08\x06\x00\x00\x00"
)

GOOD = """
import 'package:flutter/material.dart';
import 'package:home_canvas/dashboard/widget_registry.dart';

final tideWidgetType = DashboardWidgetType(
  type: 'tide',
  name: 'Tide',
  description: 'High water.',
  glyph: '🌊',
  build: (context, w) => const SizedBox(),
);

final widgetTypes = <DashboardWidgetType>[tideWidgetType];
"""


class Checks(unittest.TestCase):
    def setUp(self):
        self.dir = tempfile.mkdtemp()
        self.was = catalogue.WIDGETS
        catalogue.WIDGETS = self.dir

    def tearDown(self):
        catalogue.WIDGETS = self.was
        shutil.rmtree(self.dir)

    def addon(self, dart=GOOD, **manifest):
        folder = os.path.join(self.dir, "tide")
        os.makedirs(folder, exist_ok=True)
        m = {
            "name": "Tide",
            "description": "High and low water for a port you choose.",
            "author": "Somebody",
            "category": "Getting out",
            "glyph": "🌊",
            "version": "1.0.0",
            "kind": "dart",
            "entry": "tide.dart",
            "types": ["tide"],
            "permissions": [],
            "minApp": "2.0.0",
            "screenshot": "screenshot.png",
            **manifest,
        }
        with open(os.path.join(folder, "addon.json"), "w") as f:
            json.dump(m, f)
        if m["kind"] == "dart":
            with open(os.path.join(folder, "tide.dart"), "w") as f:
                f.write(dart)
        with open(os.path.join(folder, "screenshot.png"), "wb") as f:
            f.write(PNG)
        return folder

    def errors(self):
        rep = catalogue.Report()
        m = catalogue.read_manifest("tide", rep)
        catalogue.check_manifest("tide", m, rep)
        own = catalogue.check_files("tide", m, rep)
        check = {
            "dart": catalogue.check_dart,
            "json": catalogue.check_json,
            "theme": catalogue.check_theme,
        }[m["kind"]]
        check("tide", m, own, rep)
        return rep.errors

    def test_a_plain_widget_passes(self):
        self.addon()
        self.assertEqual(self.errors(), [])

    def test_running_a_program_must_be_declared(self):
        self.addon(GOOD + "\nvoid f() { Process.run('ls', []); }\n")
        self.assertTrue(any('"process"' in e for e in self.errors()))
        self.addon(GOOD + "\nvoid f() { Process.run('ls', []); }\n", permissions=["process"])
        self.assertEqual(self.errors(), [])

    def test_a_permission_not_used_is_not_kept(self):
        self.addon(permissions=["files"])
        self.assertTrue(any("does not use it" in e for e in self.errors()))

    def test_a_shell_is_never_started(self):
        self.addon(GOOD + "\nvoid f() { Process.run('bash', ['-c', 'x']); }\n", permissions=["process"])
        self.assertTrue(any("starts bash" in e for e in self.errors()))

    def test_ffi_is_never_imported(self):
        self.addon("import 'dart:ffi';\n" + GOOD)
        self.assertTrue(any("dart:ffi" in e for e in self.errors()))

    def test_code_cannot_hide_behind_a_quote(self):
        # Read naively, the first string never ends and the second line's
        # "//" starts a comment that swallows the call after it.
        hidden = GOOD + "\nvar a = '${\"'\"}';\nvar b = \"//\"; void f() { Process.run('ls', []); }\n"
        self.addon(hidden)
        self.assertTrue(any('"process"' in e for e in self.errors()))

    def test_words_in_comments_are_not_code(self):
        self.addon(GOOD + "\n// Process.run('ls') would be wrong here.\n/* File('x') /* nor this */ */\n")
        self.assertEqual(self.errors(), [])

    def test_plain_http_to_the_world_is_refused(self):
        self.addon(GOOD + "\nconst u = 'http://example.org/feed';\n")
        self.assertTrue(any("without TLS" in e for e in self.errors()))
        self.addon(GOOD + "\nconst u = 'http://homeassistant.local:8123';\n")
        self.assertEqual(self.errors(), [])

    def test_another_addons_files_are_not_imported(self):
        self.addon("import '../clock/clock_widget.dart';\n" + GOOD)
        self.assertTrue(any("only its own files" in e for e in self.errors()))

    def test_the_type_listed_must_be_declared(self):
        self.addon(types=["tide", "surf"])
        self.assertTrue(any('"surf"' in e for e in self.errors()))

    def test_words_in_a_label_are_not_calls(self):
        self.addon(GOOD + "\nconst label = 'Link (ICS) or File (local)';\n")
        self.assertEqual(self.errors(), [])
        self.addon(GOOD + "\nfinal x = 'a${File('/etc/passwd').readAsStringSync()}';\n")
        self.assertTrue(any('"files"' in e for e in self.errors()))

    def test_the_names_kept_for_uploads_are_not_taken(self):
        self.addon(GOOD.replace("'tide'", "'custom_tide'"), types=["custom_tide"])
        self.assertTrue(any("not a type an add-on can bring" in e for e in self.errors()))

    def test_stray_files_are_refused(self):
        folder = self.addon()
        with open(os.path.join(folder, "run.sh"), "w") as f:
            f.write("#!/bin/sh\n")
        self.assertTrue(any("run.sh should not be there" in e for e in self.errors()))

    def described(self, url, **more):
        folder = self.addon(kind="json", types=["custom_tide"])
        path = os.path.join(folder, "addon.json")
        with open(path) as f:
            m = json.load(f)
        m.pop("entry")
        with open(path, "w") as f:
            json.dump(m, f)
        with open(os.path.join(folder, "tide.json"), "w") as f:
            json.dump({"type": "tide", "source": {"url": url, **more}}, f)

    def test_json_fetches_only_from_a_public_https_host(self):
        self.described("https://api.example.org/tide?at={{option.port}}")
        self.assertEqual(self.errors(), [])
        for bad in (
            "http://api.example.org/tide",
            "https://192.168.1.4/tide",
            "https://{{option.host}}/tide",
            "https://localhost/tide",
            "https://router.local/tide",
        ):
            self.described(bad)
            self.assertTrue(self.errors(), bad)

    def test_json_keeps_no_secret_in_a_header(self):
        self.described("https://api.example.org/t", headers={"Authorization": "Bearer abc"})
        self.assertTrue(any("carries a secret" in e for e in self.errors()))
        self.described("https://api.example.org/t", headers={"Authorization": "Bearer {{option.key}}"})
        self.assertEqual(self.errors(), [])

    def theme(self, **theme):
        t = {
            "id": "tide-pool",
            "name": "Tide pool",
            "background": ["#04121a"],
            "surface": "#14ffffff",
            "border": "#22ffffff",
            "textPrimary": "#ffffffff",
            "textSecondary": "#99ffffff",
            "accent": "#ff7dd3fc",
            "cornerRadius": 20,
            "gap": 12,
            "fontFamily": "Inter",
            **theme,
        }
        folder = self.addon(
            kind="theme", category="Themes", entry="theme.json", types=[],
            themes=[t["id"]],
        )
        with open(os.path.join(folder, "theme.json"), "w") as f:
            json.dump(t, f)

    def test_a_theme_passes(self):
        self.theme()
        self.assertEqual(self.errors(), [])

    def test_a_theme_is_colours_and_measures(self):
        for bad, said in (
            ({"accent": "orange"}, '"accent" must be a colour'),
            ({"gap": 400}, '"gap" must be a number'),
            ({"fontFamily": "Papyrus"}, "not a face the app has"),
            ({"style": "comic"}, '"style" must be one of'),
            ({"style": "lcars"}, 'needs a "palette"'),
            ({"script": "alert(1)"}, '"script" is not something a theme has'),
            ({"id": "glass"}, "the app's own theme"),
        ):
            self.theme(**bad)
            self.assertTrue(any(said in e for e in self.errors()), (bad, self.errors()))

    def test_a_theme_brings_no_widgets(self):
        self.theme()
        path = os.path.join(self.dir, "tide", "addon.json")
        with open(path) as f:
            m = json.load(f)
        m["types"] = ["tide"]
        with open(path, "w") as f:
            json.dump(m, f)
        self.assertTrue(any("brings no widget types" in e for e in self.errors()))

    def test_only_a_theme_is_filed_under_themes(self):
        self.addon(category="Themes")
        self.assertTrue(any('"Themes"' in e for e in self.errors()))


if __name__ == "__main__":
    unittest.main()
