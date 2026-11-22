#!/usr/bin/env bash
# Draws an add-on's screenshot.png from its own stand-in content — the
# `preview` its widget declares — so that the picture has nobody's own
# calendar or address in it.
#
#   tools/shots.sh my_widget          one, or several with spaces between
#   tools/shots.sh all                every add-on
set -euo pipefail
[ $# -gt 0 ] || { echo "Which add-on? tools/shots.sh <name>… or all" >&2; exit 1; }
# shellcheck source=tools/app.sh
. "$(dirname "${BASH_SOURCE[0]}")/app.sh"
IDS="$(IFS=,; echo "$*")"
cd "$APP"
ADDONS_DIR="$HERE/widgets" ADDON_SHOTS="$IDS" "$FLUTTER" test --no-pub tool/addon_shots_test.dart
echo "Drawn: $*"
