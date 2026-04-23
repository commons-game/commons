#!/usr/bin/env bash
# dev/run-scenario.sh — run a Puppet scenario under a virtual display so
# screenshot-diff assertions work on the headless dev server.
#
# Godot's --headless mode uses the dummy rendering driver, which doesn't
# populate get_viewport().get_texture() — screenshots come back null/blank.
# xvfb-run gives Godot a real (virtual) X display with no visible window.
#
# Usage:
#   dev/run-scenario.sh tests/scenarios/<name>.gd
#   dev/run-scenario.sh tests/scenarios/<name>.gd 60    # 60s timeout
#
# For pure-state scenarios (no screenshot assertions) prefer --headless
# directly for speed. This wrapper is for visual regressions.
set -euo pipefail

SCENARIO="${1:?usage: $0 <scenario.gd path> [timeout_sec]}"
TIMEOUT_SEC="${2:-60}"

# Normalise to res:// form if a filesystem-relative path was passed.
case "$SCENARIO" in
  res://*) RES_PATH="$SCENARIO" ;;
  /*)      RES_PATH="res://${SCENARIO#/home/adam/development/freeland/}" ;;
  *)       RES_PATH="res://$SCENARIO" ;;
esac

cd "$(dirname "$0")/.."

exec timeout "$TIMEOUT_SEC" xvfb-run -a \
  godot4 --path . -- --puppet-scenario="$RES_PATH"
