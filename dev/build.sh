#!/usr/bin/env bash
# dev/build.sh — export Commons to a self-contained binary for playtesting.
# Run on the dev server. Writes to build/commons.x86_64.
#
# The laptop-side dev/play.sh pulls this file via rsync.
#
# Stamp: before exporting, sed-replaces the GAME_VERSION constant in
# autoloads/GameVersion.gd with the current git SHA + ISO timestamp so the
# resulting binary's boot log answers "is this build current?" trivially.
# A trap restores the file via `git checkout --` even if the export fails,
# so the working tree is never left dirty.
#
# Why: dev/play.sh used to rsync build/ blindly. We ran an Apr-23 binary for
# a week thinking the Apr-30 fix was live; nothing in the binary's logs
# revealed which commit it came from. Now it does.
set -euo pipefail

cd "$(dirname "$0")/.."
mkdir -p build

GV_FILE="autoloads/GameVersion.gd"
SHA="$(git rev-parse --short HEAD)"
ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
STAMP="${SHA} ${ISO}"

# Snapshot the file's *current* contents (NOT HEAD) before stamping, then
# restore it on exit. Snapshotting from disk preserves any uncommitted edits
# the developer happens to have in GameVersion.gd — `git checkout --` would
# silently erase them. Trap fires on success, failure, and Ctrl-C.
GV_BACKUP="$(mktemp -t game_version.gd.XXXXXX)"
cp "$GV_FILE" "$GV_BACKUP"
trap 'cp "$GV_BACKUP" "$GV_FILE" && rm -f "$GV_BACKUP"' EXIT

# Replace the literal: const GAME_VERSION:     String = "dev"
# Match flexibly on whitespace so reformatting doesn't silently break this.
sed -i -E "s|^(const GAME_VERSION:[[:space:]]+String[[:space:]]*=[[:space:]]*)\"[^\"]*\"|\1\"${STAMP}\"|" "$GV_FILE"

# Sanity-check the substitution actually happened — sed is silent on no-match.
if ! grep -q "\"${STAMP}\"" "$GV_FILE"; then
  echo "ERROR: failed to stamp ${GV_FILE} with version ${STAMP}" >&2
  echo "       (the const-line shape may have changed; update the sed regex)" >&2
  exit 1
fi

godot4 --headless --path . --export-release LinuxX11 build/commons.x86_64

echo "Built: build/commons.x86_64 ($(du -h build/commons.x86_64 | cut -f1))  stamp=${STAMP}"
