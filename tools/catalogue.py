#!/usr/bin/env python3
"""The catalogue's own checks, and the index a panel reads.

    catalogue.py check [--base REF] [--app DIR] [--owner]
    catalogue.py index --commit SHA --out FILE

`check` reads every add-on under widgets/ — widgets in Dart or JSON, and
themes — and says what is wrong with any of them: a manifest that is incomplete, a file that should not be there, Dart
that reaches for something it has not declared. It runs nothing an add-on
contains. With --base it also holds a change to what a contributor may
change, and to a new version number for anything it changes. With --app (a
checkout of HomeCanvas) it holds each add-on to the app it says it needs.

`index` writes what panels download: each add-on's manifest, and the
SHA-256 of each of its files at the commit named. A panel installs nothing
that does not match.

Python's standard library only, so it runs anywhere and before anything is
installed.
"""

import argparse
import datetime
import hashlib
import ipaddress
import json
import os
import re
import struct
import subprocess
import sys
from urllib.parse import urlsplit

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WIDGETS = os.path.join(ROOT, "widgets")

ID = re.compile(r"^[a-z][a-z0-9_]{1,39}$")
TYPE = re.compile(r"^[a-z][A-Za-z0-9_]{1,39}$")
DART = re.compile(r"^[a-z][a-z0-9_]*\.dart$")
JSON_FILE = re.compile(r"^[a-z][a-z0-9_]*\.json$")
VERSION = re.compile(r"^\d+\.\d+\.\d+$")
# A theme's own name, as a panel's config.json keeps it: hyphens allowed.
THEME_ID = re.compile(r"^[a-z][a-z0-9-]{1,39}$")
COLOUR = re.compile(r"^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$")

# What an add-on can be: a widget written in Dart, one described in JSON,
# or a theme — colours and measures, no code at all.
KINDS = ("dart", "json", "theme")

# The theme the app ships, and so one no add-on may replace.
BUILT_IN_THEMES = {"glass"}
# How a theme's frames are drawn: the app draws these, a theme picks one.
STYLES = {"panels", "lcars"}
THEME_KEYS = {
    "id", "name", "background", "surface", "border", "textPrimary",
    "textSecondary", "accent", "cornerRadius", "gap", "fontFamily", "shadow",
    "glow", "glowEnd", "sheen", "style", "palette",
}
# The faces the app carries, for a theme to name; with --app, read from its
# pubspec.yaml instead.
FONTS = {
    "Inter", "SourceSans3", "Lora", "JetBrainsMono", "Oswald", "Antonio",
    "Quicksand", "Comfortaa", "Nunito", "Fredoka", "ComicNeue", "PatrickHand",
    "Orbitron", "ChakraPetch", "ShareTechMono", "SpaceMono", "VT323",
    "PressStart2P", "BebasNeue", "Bangers",
}

CATEGORIES = [
    "Time & day",
    "Weather & air",
    "Photos, music & TV",
    "Around the house",
    "Getting out",
    "News & reference",
    "Network",
    "UniFi",
    "Homey",
    "Home lab",
    "Other",
    "Themes",
]

MAX_DART = 256 * 1024
MAX_ADDON = 768 * 1024
MAX_JSON = 64 * 1024
MAX_SHOT = 400 * 1024

# What an add-on in Dart may reach for only if its manifest says so. Each is
# shown on the Add-ons page beside the widget, and a change that asks for
# one is for a maintainer to agree to, not only for these checks to pass.
PERMISSIONS = {
    "network": (
        "talks to the network itself, rather than through the app's services",
        re.compile(r"\b(Dio|HttpClient|WebSocket|WebSocketChannel|IOWebSocketChannel)\s*[.(]|\bhttp\.(get|post|put|delete|head|read|Client)\b"),
    ),
    "sockets": (
        "opens sockets of its own",
        re.compile(r"\b(Socket|ServerSocket|RawSocket|RawDatagramSocket|SecureSocket|HttpServer)\s*\."),
    ),
    "files": (
        "reads or writes files on the panel",
        re.compile(r"\b(File|Directory|Link|RandomAccessFile)\s*\(|\bFileSystemEntity\b"),
    ),
    "process": (
        "runs other programs on the panel",
        re.compile(r"\bProcess\s*\.\s*(run|runSync|start|killPid)\b"),
    ),
    "environment": (
        "reads the panel's environment",
        re.compile(r"\bPlatform\s*\.\s*(environment|executable|resolvedExecutable|script)\b"),
    ),
}

# Never, whatever the manifest says.
FORBIDDEN = [
    (re.compile(r"""^\s*import\s+['"]dart:(ffi|mirrors|js|js_interop|html|cli)['"]""", re.M), "imports dart:{0}"),
    (re.compile(r"\b(DynamicLibrary|NativeFunction|spawnUri)\b"), "uses {0}"),
    (re.compile(r"\bProcess\s*\.\s*(?:run|runSync|start)\s*\(\s*['\"](sh|bash|sudo|su|curl|wget|nc|python3?|perl)['\"]"), "starts {0}"),
    (re.compile(r"[A-Za-z0-9+/=]{1500,}"), "carries a long encoded blob"),
]

IMPORT = re.compile(r"""^\s*(?:import|export|part)\s+['"]([^'"]+)['"]""", re.M)
ALLOWED_DART = {
    "dart:async", "dart:collection", "dart:convert", "dart:core", "dart:io",
    "dart:math", "dart:typed_data", "dart:ui",
}
URL = re.compile(r"""['"](https?://[^'"\s$]+)""")


class Report:
    def __init__(self):
        self.errors = []
        self.notes = []

    def error(self, where, what):
        self.errors.append(f"{where}: {what}")

    def note(self, where, what):
        self.notes.append(f"{where}: {what}")


def strip_comments(dart, strings=True):
    """Dart without its comments, so that prose is not read as code.

    Strings are kept, and read as Dart reads them — raw ones, triple-quoted
    ones, and code inside ${…} — so that nothing can be dressed up as a
    comment by a quote the reader miscounted. Without [strings], what a
    string says is left out too — only the code inside its ${…} stays — for
    asking what the code calls: a label reading "Link (ICS)" opens no link.
    """
    out = []
    n = len(dart)
    i = 0

    def string():
        nonlocal i
        raw = i > 0 and dart[i - 1] == "r" and not (i > 1 and (dart[i - 2].isalnum() or dart[i - 2] in "_$"))
        quote = dart[i : i + 3] if dart[i : i + 3] in ("'''", '"""') else dart[i]
        out.append(quote)
        i += len(quote)
        while i < n:
            c = dart[i]
            if not raw and c == "\\" and i + 1 < n:
                if strings:
                    out.append(dart[i : i + 2])
                i += 2
            elif dart.startswith(quote, i):
                out.append(quote)
                i += len(quote)
                return
            elif not raw and dart.startswith("${", i):
                out.append("${")
                i += 2
                code(True)
            elif c == "\n" and len(quote) == 1:
                return  # unterminated: not Dart, and the analyser will say so
            else:
                if strings:
                    out.append(c)
                i += 1

    def code(inside):
        nonlocal i
        depth = 0
        while i < n:
            c = dart[i]
            if dart.startswith("//", i):
                j = dart.find("\n", i)
                i = n if j < 0 else j
            elif dart.startswith("/*", i):
                nested = 1
                i += 2
                while i < n and nested:
                    if dart.startswith("/*", i):
                        nested += 1
                        i += 2
                    elif dart.startswith("*/", i):
                        nested -= 1
                        i += 2
                    else:
                        i += 1
                out.append(" ")
            elif c in "'\"":
                string()
            elif c == "{":
                depth += 1
                out.append(c)
                i += 1
            elif c == "}":
                out.append(c)
                i += 1
                if inside and depth == 0:
                    return
                depth -= 1
            else:
                out.append(c)
                i += 1

    code(False)
    return "".join(out)


def private_host(host):
    host = host.lower().strip("[]")
    if host in ("localhost",) or host.endswith((".local", ".lan", ".internal", ".home")):
        return True
    try:
        ip = ipaddress.ip_address(host)
    except ValueError:
        return False
    return not ip.is_global


def png_size(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n" or data[12:16] != b"IHDR":
        return None
    return struct.unpack(">II", data[16:24])


def read_manifest(id, rep):
    path = os.path.join(WIDGETS, id, "addon.json")
    try:
        with open(path, encoding="utf-8") as f:
            m = json.load(f)
    except OSError:
        rep.error(id, "has no addon.json")
        return None
    except ValueError as e:
        rep.error(id, f"addon.json is not valid JSON: {e}")
        return None
    if not isinstance(m, dict):
        rep.error(id, "addon.json must be an object")
        return None
    return m


def check_manifest(id, m, rep):
    def text(key, least, most):
        v = m.get(key)
        if not isinstance(v, str) or not (least <= len(v.strip()) <= most):
            rep.error(id, f'"{key}" is needed, as text of {least} to {most} characters')
            return ""
        return v

    if not ID.match(id):
        rep.error(id, "the folder's name must be lower-case letters, digits and underscores, starting with a letter")
    text("name", 2, 40)
    text("description", 20, 400)
    text("author", 2, 60)
    url = m.get("authorUrl")
    if url is not None and not (isinstance(url, str) and url.startswith("https://")):
        rep.error(id, '"authorUrl" must be an https:// address')
    theme = m.get("kind") == "theme"
    if m.get("category") not in CATEGORIES:
        rep.error(id, '"category" must be one of: ' + ", ".join(CATEGORIES))
    elif theme != (m.get("category") == "Themes"):
        rep.error(id, 'a theme\'s "category" is "Themes", and only a theme\'s is')
    glyph = m.get("glyph")
    if not isinstance(glyph, str) or not (1 <= len(glyph) <= 8):
        rep.error(id, '"glyph" is needed: one emoji')
    for key in ("version", "minApp"):
        if not (isinstance(m.get(key), str) and VERSION.match(m[key])):
            rep.error(id, f'"{key}" must be three numbers: 1.0.0')
    if m.get("kind") not in KINDS:
        rep.error(id, '"kind" must be "dart", "json" or "theme"')
    types = m.get("types")
    if theme:
        if types != []:
            rep.error(id, 'a theme brings no widget types: "types" is []')
        types = []
        themes = m.get("themes")
        if not (isinstance(themes, list) and len(themes) == 1
                and isinstance(themes[0], str) and THEME_ID.match(themes[0])):
            rep.error(id, '"themes" must name the one theme it brings, as its theme.json does')
    else:
        if "themes" in m:
            rep.error(id, 'only a theme has "themes"')
        if not (isinstance(types, list) and types and all(isinstance(t, str) for t in types)):
            rep.error(id, '"types" must list the widget types it brings')
            types = []
    perms = m.get("permissions", [])
    if not (isinstance(perms, list) and all(p in PERMISSIONS for p in perms)):
        rep.error(id, '"permissions" may only name: ' + ", ".join(PERMISSIONS))
    if m.get("screenshot") != "screenshot.png":
        rep.error(id, '"screenshot" must be "screenshot.png"')
    known = {
        "name", "description", "author", "authorUrl", "category", "glyph",
        "version", "kind", "entry", "types", "permissions", "minApp",
        "screenshot", "starter", "themes",
    }
    for key in m:
        if key not in known:
            rep.error(id, f'"{key}" is not something an addon.json has')
    return types


def check_files(id, m, rep):
    """What is in the folder. Returns the names of its own files."""
    folder = os.path.join(WIDGETS, id)
    own, total = [], 0
    for name in sorted(os.listdir(folder)):
        path = os.path.join(folder, name)
        if os.path.islink(path):
            rep.error(id, f"{name} is a link; add-ons hold only plain files")
            continue
        if os.path.isdir(path):
            if name != "test":
                rep.error(id, f"{name}/ should not be there: only test/ may be a folder")
                continue
            for dirpath, _, files in os.walk(path):
                for f in files:
                    full = os.path.join(dirpath, f)
                    if os.path.islink(full) or os.path.getsize(full) > MAX_DART:
                        rep.error(id, f"test/{f} is a link or too big")
            continue
        size = os.path.getsize(path)
        if name in ("addon.json", "README.md"):
            continue
        if name == "screenshot.png":
            with open(path, "rb") as f:
                dims = png_size(f.read(32))
            if dims is None:
                rep.error(id, "screenshot.png is not a PNG")
            elif not (320 <= dims[0] <= 1920 and 200 <= dims[1] <= 1200):
                rep.error(id, f"screenshot.png is {dims[0]}×{dims[1]}; between 320×200 and 1920×1200, please")
            if size > MAX_SHOT:
                rep.error(id, "screenshot.png is over 400 KB")
            continue
        if m.get("kind") == "dart" and DART.match(name):
            if size > MAX_DART:
                rep.error(id, f"{name} is over 256 KB")
        elif m.get("kind") in ("json", "theme") and JSON_FILE.match(name):
            if size > MAX_JSON:
                rep.error(id, f"{name} is over 64 KB")
        else:
            rep.error(id, f"{name} should not be there")
            continue
        own.append(name)
        total += size
    if total > MAX_ADDON:
        rep.error(id, "is over 768 KB altogether")
    if not os.path.isfile(os.path.join(folder, "screenshot.png")):
        rep.error(id, "has no screenshot.png: draw one with tools/shots.sh")
    return own


def check_dart(id, m, own, rep):
    folder = os.path.join(WIDGETS, id)
    entry = m.get("entry")
    if not (isinstance(entry, str) and entry in own):
        rep.error(id, '"entry" must name one of its Dart files')
        return
    declared = set(m.get("permissions") or [])
    used = set()
    everything = ""
    for name in own:
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            try:
                source = f.read()
            except UnicodeDecodeError:
                rep.error(id, f"{name} is not UTF-8 text")
                continue
        where = f"{id}/{name}"
        code = strip_comments(source)
        everything += code
        if any(len(line) > 2000 for line in source.splitlines()):
            rep.error(where, "has a line over 2,000 characters; code is to be read")
        for uri in IMPORT.findall(code):
            if uri.startswith("dart:"):
                if uri not in ALLOWED_DART and not re.match(r"dart:(ffi|mirrors|js|js_interop|html|cli)$", uri):
                    rep.error(where, f"imports {uri}, which add-ons do not use")
            elif uri.startswith("package:"):
                continue  # held to the app's own packages when it is analysed
            elif "/" in uri or uri not in own:
                rep.error(where, f"imports '{uri}': only its own files, the app's (package:home_canvas/…) and the app's packages")
        for pattern, what in FORBIDDEN:
            hit = pattern.search(code)
            if hit:
                rep.error(where, what.format(*(hit.groups() or (hit.group(0),))) + ", which no add-on may")
        calls = strip_comments(source, strings=False)
        for perm, (meaning, pattern) in PERMISSIONS.items():
            if pattern.search(calls):
                used.add(perm)
                if perm not in declared:
                    rep.error(where, f'{meaning}: say so with "{perm}" in "permissions", or do without')
        for url in URL.findall(code):
            parts = urlsplit(url)
            if parts.scheme == "http" and parts.hostname and not private_host(parts.hostname):
                rep.error(where, f"fetches {url} without TLS; use https://")
    for perm in sorted(declared - used):
        rep.error(id, f'asks for "{perm}" and does not use it')
    if not re.search(r"^\s*(final|const|var|List<DashboardWidgetType>)\b[^;=]*\bwidgetTypes\s*=", everything, re.M):
        rep.error(id, f"{entry} must declare what it brings: final widgetTypes = <DashboardWidgetType>[…];")
    for t in m.get("types") or []:
        if not TYPE.match(t) or t.startswith("custom_") :
            rep.error(id, f'"{t}" is not a type an add-on can bring')
        elif not re.search(r"type:\s*['\"]" + re.escape(t) + r"['\"]", everything):
            rep.error(id, f'lists the type "{t}", which its Dart does not declare')
    for perm in sorted(declared):
        rep.note(id, f"permission “{perm}”: {PERMISSIONS[perm][0]}")


def check_json(id, m, own, rep):
    if len(own) != 1:
        rep.error(id, "an add-on described in JSON is one .json file beside its addon.json")
        return
    with open(os.path.join(WIDGETS, id, own[0]), encoding="utf-8") as f:
        try:
            w = json.load(f)
        except ValueError as e:
            rep.error(id, f"{own[0]} is not valid JSON: {e}")
            return
    if not isinstance(w, dict) or not ID.match(str(w.get("type", ""))):
        rep.error(id, f'{own[0]}: "type" must be lower-case letters, digits and underscores')
        return
    if m.get("types") != ["custom_" + w["type"]]:
        rep.error(id, f'"types" must be ["custom_{w["type"]}"], as its file says')
    if m.get("permissions"):
        rep.error(id, "a widget described in JSON has no permissions to ask for")
    source = w.get("source")
    if source is None:
        return
    url = source.get("url") if isinstance(source, dict) else None
    if not isinstance(url, str):
        rep.error(id, '"source" needs a "url"')
        return
    # Where it fetches from is fixed and public: only what comes after the
    # host may be filled in from the widget's settings.
    head = re.match(r"^https://([A-Za-z0-9.-]+)(?::\d+)?(/|\?|$)", url)
    if not head:
        rep.error(id, "its source must be an https:// address with the host written out")
    elif private_host(head[1]) or "." not in head[1]:
        rep.error(id, f"its source is {head[1]}, which is not a public address")
    for name, value in (source.get("headers") or {}).items():
        if re.search(r"authorization|cookie|key|token|secret", name, re.I) and "{{option." not in str(value):
            rep.error(id, f'the header "{name}" carries a secret; take it from a setting: {{{{option.key}}}}')


def check_theme(id, m, own, rep, fonts=FONTS):
    """A theme: one theme.json of colours and measures, which the app reads
    as it reads a theme dropped in its themes folder."""
    if own != ["theme.json"] or m.get("entry") != "theme.json":
        rep.error(id, 'a theme is one file, theme.json, named as its "entry"')
        return
    if m.get("permissions"):
        rep.error(id, "a theme has no permissions to ask for")
    with open(os.path.join(WIDGETS, id, "theme.json"), encoding="utf-8") as f:
        try:
            t = json.load(f)
        except ValueError as e:
            rep.error(id, f"theme.json is not valid JSON: {e}")
            return
    if not isinstance(t, dict):
        rep.error(id, "theme.json must be an object")
        return
    for key in t:
        if key not in THEME_KEYS:
            rep.error(id, f'theme.json: "{key}" is not something a theme has')
    tid = t.get("id")
    if not (isinstance(tid, str) and THEME_ID.match(tid)):
        rep.error(id, 'theme.json: "id" must be lower-case letters, digits and hyphens')
    elif tid in BUILT_IN_THEMES:
        rep.error(id, f'theme.json: "{tid}" is the app\'s own theme, and cannot be replaced')
    elif m.get("themes") != [tid]:
        rep.error(id, f'"themes" must be ["{tid}"], as its theme.json says')
    name = t.get("name")
    if not (isinstance(name, str) and 2 <= len(name.strip()) <= 40):
        rep.error(id, 'theme.json: "name" is needed, of 2 to 40 characters')

    def colour(key, needed=True):
        v = t.get(key)
        if v is None and not needed:
            return
        if not (isinstance(v, str) and COLOUR.match(v)):
            rep.error(id, f'theme.json: "{key}" must be a colour, #rrggbb or #aarrggbb')

    for key in ("surface", "border", "textPrimary", "textSecondary", "accent"):
        colour(key)
    colour("glow", needed=False)
    colour("glowEnd", needed=False)
    bg = t.get("background")
    bg = bg if isinstance(bg, list) else [bg]
    if not (1 <= len(bg) <= 2 and all(isinstance(c, str) and COLOUR.match(c) for c in bg)):
        rep.error(id, 'theme.json: "background" is one colour, or two for a gradient')

    def number(key, least, most):
        v = t.get(key)
        if v is None:
            return
        if isinstance(v, bool) or not isinstance(v, (int, float)) or not least <= v <= most:
            rep.error(id, f'theme.json: "{key}" must be a number from {least} to {most}')

    number("cornerRadius", 0, 60)
    number("gap", 0, 48)
    number("sheen", 0, 0.5)
    if "shadow" in t and not isinstance(t["shadow"], bool):
        rep.error(id, 'theme.json: "shadow" is true or false')
    style = t.get("style", "panels")
    if style not in STYLES:
        rep.error(id, 'theme.json: "style" must be one of: ' + ", ".join(sorted(STYLES)))
    palette = t.get("palette", [])
    if not (isinstance(palette, list) and len(palette) <= 12
            and all(isinstance(c, str) and COLOUR.match(c) for c in palette)):
        rep.error(id, 'theme.json: "palette" is a list of up to twelve colours')
    elif style == "lcars" and not palette:
        rep.error(id, 'theme.json: a console ("style": "lcars") needs a "palette" for its blocks')
    font = t.get("fontFamily")
    if font is not None and font not in fonts:
        rep.error(id, f'theme.json: "fontFamily" {font!r} is not a face the app has: '
                  + ", ".join(sorted(fonts)))


def app_fonts(app):
    """The faces the app at [app] carries, as its pubspec.yaml lists them."""
    with open(os.path.join(app, "pubspec.yaml"), encoding="utf-8") as f:
        return set(re.findall(r"^\s*-\s*family:\s*(\S+)\s*$", f.read(), re.M)) or FONTS


def addons():
    return sorted(
        d for d in os.listdir(WIDGETS) if os.path.isdir(os.path.join(WIDGETS, d))
    )


def git(*args):
    return subprocess.run(
        ["git", "-C", ROOT, *args], capture_output=True, text=True, check=False
    )


def check_change(base, owner, manifests, rep):
    """What this change touches, against [base]."""
    diff = git("diff", "--name-only", f"{base}...HEAD")
    if diff.returncode != 0:
        rep.error("change", f"could not be compared with {base}: {diff.stderr.strip()}")
        return
    touched = set()
    for path in diff.stdout.split("\n"):
        if not path:
            continue
        parts = path.split("/")
        if parts[0] == "widgets" and len(parts) > 2:
            touched.add(parts[1])
        elif parts[0] == "tests" and len(parts) == 2 and parts[1].endswith(".dart"):
            continue
        elif not owner:
            rep.error(path, "is the catalogue's own; a contribution changes only widgets/<name>/ and tests/")
    for id in sorted(touched):
        m = manifests.get(id)
        if m is None:
            continue  # taken out
        before = git("show", f"{base}:widgets/{id}/addon.json")
        if before.returncode != 0:
            rep.note(id, "is new")
            if m.get("starter") and not owner:
                rep.error(id, '"starter" is for the maintainers to set')
            continue
        try:
            old = json.loads(before.stdout)
        except ValueError:
            continue
        if not newer(m.get("version"), old.get("version")):
            rep.error(id, f'has changed: its "version" must go up from {old.get("version")}')
        if set(m.get("permissions") or []) - set(old.get("permissions") or []):
            rep.note(id, "asks for more than it did: for a maintainer to agree to")
        if old.get("author") != m.get("author") and not owner:
            rep.note(id, f'changes author from “{old.get("author")}”: for a maintainer to agree to')
        if m.get("starter") != old.get("starter") and not owner:
            rep.error(id, '"starter" is for the maintainers to set')


def parts(version):
    return tuple(int(x) for x in str(version).split("+")[0].split("."))


def newer(a, b):
    try:
        return parts(a) > parts(b)
    except ValueError:
        return False


def app_version(app):
    with open(os.path.join(app, "pubspec.yaml"), encoding="utf-8") as f:
        m = re.search(r"^version:\s*(\d+\.\d+\.\d+)", f.read(), re.M)
    return m[1] if m else None


def check(args):
    rep = Report()
    manifests, types, themes = {}, {}, {}
    fonts = app_fonts(args.app) if args.app else FONTS
    for id in addons():
        m = read_manifest(id, rep)
        if m is None:
            continue
        manifests[id] = m
        declared = check_manifest(id, m, rep)
        own = check_files(id, m, rep)
        if m.get("kind") == "dart":
            check_dart(id, m, own, rep)
        elif m.get("kind") == "json":
            check_json(id, m, own, rep)
        elif m.get("kind") == "theme":
            check_theme(id, m, own, rep, fonts)
            for t in m.get("themes") or []:
                if isinstance(t, str) and t in themes:
                    rep.error(id, f'brings the theme "{t}", which {themes[t]} already does')
                themes[t] = id
        for t in declared:
            if t in types:
                rep.error(id, f'brings "{t}", which {types[t]} already does')
            types[t] = id
    if args.app:
        have = app_version(args.app)
        for id, m in manifests.items():
            try:
                if have and parts(m.get("minApp")) > parts(have):
                    rep.error(id, f"needs HomeCanvas {m.get('minApp')}; the app checked against is {have}")
            except ValueError:
                pass
    if args.base:
        check_change(args.base, args.owner, manifests, rep)

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    lines = [f"Checked {len(manifests)} add-ons."]
    if rep.notes:
        lines += ["", "For a maintainer to look at:"] + [f"- {n}" for n in rep.notes]
    if rep.errors:
        lines += ["", "To put right:"] + [f"- {e}" for e in rep.errors]
    else:
        lines += ["", "Nothing to put right."]
    print("\n".join(lines))
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
    return 1 if rep.errors else 0


def index(args):
    if not re.fullmatch(r"[0-9a-f]{40}", args.commit):
        print("--commit must be a full commit id", file=sys.stderr)
        return 1
    rep = Report()
    out = []
    for id in addons():
        m = read_manifest(id, rep)
        if m is None:
            continue
        own = check_files(id, m, rep)
        files = []
        for name in own:
            with open(os.path.join(WIDGETS, id, name), "rb") as f:
                data = f.read()
            files.append(
                {"path": name, "sha256": hashlib.sha256(data).hexdigest(), "size": len(data)}
            )
        out.append({"id": id, **m, "files": files})
    if rep.errors:
        print("\n".join(rep.errors), file=sys.stderr)
        return 1
    remote = git("config", "--get", "remote.origin.url").stdout.strip()
    repo = re.sub(r"^.*github\.com[:/]|\.git$", "", remote)
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(
            {
                "schema": 1,
                "repo": repo,
                "commit": args.commit,
                "generated": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
                "addons": out,
            },
            f,
            indent=1,
            ensure_ascii=False,
        )
        f.write("\n")
    print(f"{len(out)} add-ons at {args.commit[:10]} -> {args.out}")
    return 0


def main():
    p = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    sub = p.add_subparsers(dest="action", required=True)
    c = sub.add_parser("check")
    c.add_argument("--base", help="the commit a change is made against")
    c.add_argument("--app", help="a checkout of HomeCanvas to hold add-ons to")
    c.add_argument("--owner", action="store_true", help="the change is a maintainer's own")
    i = sub.add_parser("index")
    i.add_argument("--commit", required=True)
    i.add_argument("--out", required=True)
    args = p.parse_args()
    return check(args) if args.action == "check" else index(args)


if __name__ == "__main__":
    sys.exit(main())
