# HomeCanvas Widgets

The widgets for [HomeCanvas](https://github.com/vwillcox/HomeCanvas), the
self-hosted wall display for a Raspberry Pi — each one an **add-on** you
download to your panel from the editor's **Add-ons** page.

HomeCanvas has no widgets of its own. Every one lives here: the 52 that used
to be built in, the photo albums that used to be the kiosk's first screen,
and whatever anyone sends next.

## Getting one onto your panel

Open the dashboard editor in a browser (`http://<your panel>:8090`), choose
**Add-ons**, and press **Download** on the one you want. Pick several and
they are added together.

- An add-on **written in Dart** is built into the panel by the panel itself.
  That takes a few minutes and ends with a restart. If it does not build or
  the panel does not start with it, the panel goes back to how it was and
  the page says why.
- An add-on **described in JSON** is on the panel the moment you download
  it.

A panel that was set up when the widgets were built in keeps them: updating
it fetches whatever its dashboard uses.

## What is in here

```
widgets/<name>/        one add-on
  addon.json             what it is: name, author, category, version…
  screenshot.png         the picture the Add-ons page shows
  *.dart  or  <x>.json   the widget itself
  test/                  its own tests, if it has any
tests/                 tests that span several add-ons
templates/             a Dart and a JSON add-on to start from
tools/                 the checks, and scripts to run them yourself
app-ref                the HomeCanvas branch the add-ons are built against
```

## Making one and sending it in

See **[CONTRIBUTING.md](CONTRIBUTING.md)**. In short: copy a template into
`widgets/<your_name_for_it>/`, make it yours, draw its picture with
`tools/shots.sh`, and open a pull request.

## Or keeping a library of your own

You need not send a widget here for it to be used. A panel can read other
libraries beside this catalogue — any public repository laid out as this
one is. Nobody here tests or reads what is in them, and the Add-ons page
says so on every add-on that comes from one; what is installed from a
library is at the risk of whoever installs it.
**[docs/your-own-library.md](docs/your-own-library.md)** says how to set one
up.

## How a widget gets from a pull request to a panel

1. **Safety.** A GitHub Action reads every file of every add-on. It runs
   none of them. It refuses anything that is not a widget's own files, Dart
   that imports what add-ons have no use for (`dart:ffi`, `dart:mirrors`),
   that starts a shell, fetches without TLS, or carries a blob nobody can
   read — and it refuses Dart that reaches for the network, files, other
   programs or the environment **without saying so** under `permissions`
   in its `addon.json`. A JSON widget may fetch only from a public
   `https://` host written out in full.
2. **Compatibility.** A second Action builds every add-on into HomeCanvas
   itself, at the version the add-on says it needs, has Dart's analyser
   read it there, and runs its tests.
3. **A person.** Checks catch the careless and the obvious. Dart is a
   program, and a program can be written to look innocent — so every add-on
   written in Dart is read by a maintainer before it is merged, and whatever
   it asks for under `permissions` is theirs to agree to.
4. **The catalogue.** Only when both checks pass *on `main`* is the
   catalogue written: an `index.json` on the [`catalogue`
   branch](../../tree/catalogue) naming the commit each add-on was read at
   and the SHA-256 of each of its files. That index is all a panel reads,
   and a panel installs nothing that does not match its sum.

What a panel shows beside each add-on — its author, its category, what it
asks for — comes from that same index.

## Licence

MIT, as HomeCanvas is. By sending a widget you offer it under the same.
