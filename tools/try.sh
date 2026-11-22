#!/usr/bin/env bash
# What the catalogue's checks do, on your own machine: reads every add-on
# for what it should not do, builds them into the app, has the analyser
# read them, and runs their tests.
set -euo pipefail
python3 "$(dirname "${BASH_SOURCE[0]}")/catalogue.py" check
# shellcheck source=tools/app.sh
. "$(dirname "${BASH_SOURCE[0]}")/app.sh"
python3 "$HERE/tools/catalogue.py" check --app "$APP" >/dev/null
cd "$APP"
"$FLUTTER" analyze --no-pub --no-fatal-infos --no-fatal-warnings \
  lib/dashboard/widgets/custom test/addons
"$FLUTTER" test --no-pub test/addons test/editor_schema_test.dart
echo "All of it passes."
