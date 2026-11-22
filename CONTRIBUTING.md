# Sending in a widget

Anyone can add a widget to the catalogue. It is a folder under `widgets/`
and a pull request; the checks tell you what, if anything, to put right.

## Two kinds

**Described in JSON** — what it is called, its settings, the address its
data comes from and how to show it: a figure, some cards, or a list. Nothing
in it is run; the panel reads it and draws what it says. It is on a panel
the moment it is downloaded, and it is the easiest kind to get accepted,
because what it can do is all there to read. Start from
[`templates/json/`](templates/json).

**Written in Dart** — a real Flutter widget, as full as any the app ever
had: its own drawing, taps, timers. The panel builds it into itself. Start
from [`templates/dart/`](templates/dart). The widgets already here are the
best examples; how a widget is put together is described in the app, in
[`lib/dashboard/widgets/README.md`](https://github.com/vwillcox/HomeCanvas/blob/main/lib/dashboard/widgets/README.md).

## The folder

```
widgets/tide_times/
  addon.json
  screenshot.png
  tide_times.dart        (or tide_times.json)
  test/tide_times_test.dart     optional
```

The folder's name is the add-on's name for good: lower-case letters, digits
and underscores.

### addon.json

```json
{
  "name": "Tide times",
  "description": "High and low water for a port you choose, from the Admiralty's tables.",
  "author": "Your name",
  "authorUrl": "https://github.com/your-name",
  "category": "Getting out",
  "glyph": "🌊",
  "version": "1.0.0",
  "kind": "dart",
  "entry": "tide_times.dart",
  "types": ["tide_times"],
  "permissions": [],
  "minApp": "1.1.0",
  "screenshot": "screenshot.png"
}
```

| | |
|---|---|
| `name`, `description` | What the Add-ons page shows. Say what it does and where its data comes from. |
| `author`, `authorUrl` | You. The address is optional, and must be `https://`. |
| `category` | Where the editor lists it: `Time & day`, `Weather & air`, `Photos, music & TV`, `Around the house`, `Getting out`, `News & reference`, `Network`, `UniFi`, `Homey`, `Home lab` or `Other`. |
| `glyph` | One emoji, shown where there is no picture. |
| `version` | Three numbers. It must go up whenever the add-on changes: that is how a panel knows there is an update. |
| `kind` | `dart` or `json`. |
| `entry` | Dart only: the file that declares `widgetTypes`. |
| `types` | The widget types it brings — what a dashboard saves a tile as. For Dart, each `type:` its descriptors declare. For JSON, `custom_` and then the `type` in its file. Nobody else's, and never renamed. |
| `permissions` | Dart only: what it reaches for beyond drawing. See below. |
| `minApp` | The oldest HomeCanvas it works with. |

### What a Dart add-on may do

It may import `dart:async`, `dart:collection`, `dart:convert`, `dart:math`,
`dart:typed_data`, `dart:ui`, Flutter, anything of the app's
(`package:home_canvas/…`), the packages in the app's `pubspec.yaml`, and
its own files. Most widgets need nothing else: the app's services already
fetch feeds, talk to Home Assistant, and so on.

If it needs more it says so, and the Add-ons page tells whoever is about to
download it:

| `permissions` | Because it… |
|---|---|
| `network` | talks to the network itself (`Dio`, `HttpClient`, a web socket) rather than through the app's services |
| `sockets` | opens sockets of its own |
| `files` | reads or writes files on the panel |
| `process` | runs other programs on the panel |
| `environment` | reads the panel's environment |

Asking is not the same as being given: each is for a maintainer to agree
to, and the plainer the reason in your pull request, the quicker that is.

Never, whatever it declares: `dart:ffi`, `dart:mirrors`, starting a shell,
fetching from the internet without TLS, or code nobody can read.

Its entry file ends with what it brings:

```dart
final widgetTypes = <DashboardWidgetType>[tideTimesWidgetType];
```

### What a JSON add-on may do

Fetch JSON from one public `https://` host, written out in full — only what
comes after the host may be filled in from the widget's settings — and show
it. A key or token goes in a setting of kind `secret` and is sent as
`{{option.key}}`; it is never written into the file.

### The picture

```
tools/shots.sh tide_times
```

draws `screenshot.png` from your widget's own `preview` — the stand-in
content it declares for the editor. That is deliberate: a photograph of
your panel has your calendar and your address in it. You may send a picture
of your own instead (a PNG, between 320×200 and 1920×1200, under 400 KB) so
long as nothing in it is anybody's own.

## Trying it before you send it

```
python3 tools/catalogue.py check     # reads every add-on; needs only Python
tools/try.sh                         # that, then builds them into the app and runs the tests
```

`tools/try.sh` and `tools/shots.sh` need [Flutter](https://docs.flutter.dev/get-started)
and a checkout of HomeCanvas: one beside this folder is used if it is there
(or name one with `HOMECANVAS_APP=…`), and otherwise one is fetched into
`.app/`.

To see it on a real panel before it is in the catalogue: a Dart widget can
be uploaded as it is under **Custom widgets** in the editor (declare
`final widgetType = …` as well, for that page), and a JSON one likewise.

## Tests

A test beside the widget, in `widgets/<name>/test/`, is run with the app's
own. It imports the widget from where the panel builds it:

```dart
import 'package:home_canvas/dashboard/widgets/custom/addons/tide_times/tide_times.dart';
```

## The pull request

Change only your own folder under `widgets/` (and `tests/`, for a test that
spans several). The checks run by themselves and say, at the top of the run,
what to put right. A maintainer then reads it; once it is merged and the
checks pass on `main`, it is in the catalogue and on everybody's Add-ons
page within a few minutes.

By sending a widget you say that you wrote it, or may share it, and that
you offer it under the MIT licence this repository carries.
