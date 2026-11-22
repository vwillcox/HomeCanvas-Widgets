# Keeping a library of your own

You do not have to send a widget here for people to use it. A HomeCanvas
panel can read any number of **third-party libraries** beside this catalogue: a
repository of your own, laid out as this one is, that publishes its index
the same way. Yours to run, yours to answer for.

Use one when a widget is only for you or your household, when it is tied to
something few people have, when you would rather not wait for a review — or
simply because it is yours.

## What a library is

A public repository on GitHub with:

```
widgets/
  my_widget/
    addon.json        what it is — see CONTRIBUTING.md
    my_widget.dart    or my_widget.json
    screenshot.png
```

and a branch called `catalogue` holding one file, `index.json`: every
add-on in `widgets/`, the commit it was read at, and the SHA-256 of each of
its files. A panel reads that index, and installs only files that match it.

You do not write the index. The checks in this repository write it, and
they come with you when you copy it.

## Setting one up

1. **Copy this repository.** Fork it, or clone it and push it to a new
   repository of your own. It must be **public**: panels fetch from
   `raw.githubusercontent.com` without signing in.

2. **Clear it out.** Delete what is ours and keep what does the work:

   ```bash
   git rm -r -q widgets tests
   mkdir widgets
   cp -r templates/dart widgets/my_widget      # or templates/json
   ```

   Keep `tools/`, `.github/workflows/check.yml`, `app-ref`,
   `.flutter-version` and `templates/`. Put your own name in
   `.github/CODEOWNERS`, or delete it.

3. **Write your widget** as [CONTRIBUTING.md](../CONTRIBUTING.md)
   describes — the folder, `addon.json`, what an add-on may and may not
   do, the picture. The rules are the same; so are the tools:

   ```bash
   python3 tools/catalogue.py check    # what the checks will say
   tools/try.sh my_widget              # build it into HomeCanvas and look
   tools/shots.sh my_widget            # draw its screenshot.png
   ```

4. **Give it names of its own.** The catalogue comes first on every panel:
   an add-on in a library whose folder name, or whose widget `type`, is
   one the catalogue already has is left out of the list. Call yours
   something the catalogue is unlikely to — `yourname_tides`, not `tides`.

5. **Turn the checks on.** In your repository: *Actions* → enable
   workflows (GitHub switches them off in a fork). If your account or
   organisation restricts them, also *Settings → Actions → General →
   Workflow permissions → Read and write*, since publishing pushes to the
   `catalogue` branch.

6. **Push to `main`.** The workflow reads every add-on, builds them into
   HomeCanvas, runs any tests you have in `tests/` or
   `widgets/<name>/test/`, and — when all of that passes — writes
   `index.json` to the `catalogue` branch. Nothing is published from a run
   that fails, so a panel never sees a widget that does not build.

   Check it is there:
   `https://raw.githubusercontent.com/<you>/<repository>/catalogue/index.json`

## Adding it to a panel

In the editor, open **Add-ons**, then **Third-party libraries** at the
foot of the page. Type `you/repository`, tick the box, **Add library**.
Your add-ons appear in the list with the catalogue's, marked
**Untested — from you/repository**.

Two things to tell whoever you share it with:

- **Add-ons written in Dart from a library need a switch on the panel.**
  Settings → Dashboard → *Widgets written in Dart*, on the panel's own
  screen. It is off unless someone standing at the panel turns it on,
  because the editor has no password and Dart from a library is code that
  runs there. Add-ons described in JSON need no switch.
- **A panel reads up to eight libraries.**

## What people are told about your library

On the Add-ons page, in these words:

> Nobody at HomeCanvas has tested or read what is in another library. An
> add-on written in Dart is code: once installed it runs on the panel as
> the panel does, and can read whatever the panel can — its settings and
> keys among them. What a library says its add-ons use is its own word.
> Add only a library whose owner you trust; what you install from one is
> at your own risk.

That is fair to them and to you. The checks you copied are the same as
ours, but you can change them, nobody reviews what you push, and a panel
has no way to know whether you ran them at all: it checks only that the
files it fetched are the ones your index names. Keeping the checks as they
are, and keeping `"permissions"` honest, is how a library earns trust.

## Keeping it working

- `app-ref` names the HomeCanvas branch or tag your add-ons are built
  against, and `.flutter-version` the Flutter. When HomeCanvas moves on,
  pull the changes to `tools/` and the workflow from this repository and
  push; the checks will tell you if a widget needs to follow.
- Raise `"version"` in `addon.json` whenever you change an add-on. Panels
  that have it are offered **Update**.
- Removing a folder removes it from the list. Panels that installed it
  keep it until they remove it.

## Or send it in after all

A widget that has lived in your library is most of the way to the
catalogue. [CONTRIBUTING.md](../CONTRIBUTING.md) says how; the only
difference is that somebody else reads it first.
