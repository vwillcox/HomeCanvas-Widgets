#!/usr/bin/env bash
# Finds, or fetches, a checkout of HomeCanvas to build the add-ons into, and
# builds them in. Sourced by shots.sh and try.sh; leaves $APP set.
#
# HOMECANVAS_APP names a checkout you already have. Without it, one is
# cloned into .app/ here, at the branch app-ref names.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="${HOMECANVAS_APP:-}"
if [ -z "$APP" ] && [ -f "$HERE/../HomeCanvas/scripts/widget-build.sh" ]; then
  APP="$(cd "$HERE/../HomeCanvas" && pwd)"
fi
if [ -z "$APP" ]; then
  APP="$HERE/.app"
  REF="$(cat "$HERE/app-ref")"
  if [ -d "$APP/.git" ]; then
    git -C "$APP" fetch --depth 1 origin "$REF" && git -C "$APP" checkout -q FETCH_HEAD
  else
    git clone --depth 1 --branch "$REF" https://github.com/vwillcox/HomeCanvas "$APP"
  fi
fi
FLUTTER="$(command -v flutter || echo "$HOME/flutter/bin/flutter")"
[ -x "$FLUTTER" ] || { echo "Flutter is needed: https://docs.flutter.dev/get-started" >&2; exit 1; }

STATE="$(mktemp -d)"
trap 'rm -rf "$STATE"' EXIT
# Every add-on here, and their tests, copied into the app's source.
HOMECANVAS_ADDONS="$HERE/widgets" HOMECANVAS_ADDON_TESTS=1 \
  HOMECANVAS_WIDGETS="$STATE/src" HOMECANVAS_WIDGET_STATE="$STATE/state" \
  bash "$APP/scripts/widget-build.sh" generate
(cd "$APP" && "$FLUTTER" pub get >/dev/null)
