#!/usr/bin/env bash
# dev/build.sh — export Commons to a self-contained binary for playtesting.
# Run on the dev server. Writes to build/commons.x86_64.
#
# The laptop-side dev/play.sh pulls this file via rsync.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

godot4 --headless --path . --export-release LinuxX11 build/commons.x86_64

echo "Built: build/commons.x86_64 ($(du -h build/commons.x86_64 | cut -f1))"
