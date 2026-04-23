#!/usr/bin/env bash
# play-remote.sh — sync the Commons project from the dev server to this
# laptop and launch Godot locally. Native input, no streaming latency.
#
# Requirements on the laptop:
#   - Godot 4.3 in PATH as `godot4` (override via GODOT env var)
#   - rsync + ssh access to the dev server
#
# Usage (from the laptop):
#   SERVER=adam@your-server ./play-remote.sh
#
# Optional overrides:
#   REMOTE_DIR  path on the server       (default: /home/adam/development/freeland)
#   LOCAL_DIR   path on this laptop      (default: $HOME/commons)
#   GODOT       godot binary to run      (default: godot4)
#
# Bootstrap (once):
#   ssh adam@your-server 'cat development/freeland/dev/play-remote.sh' \
#     > ~/play-remote.sh && chmod +x ~/play-remote.sh
set -euo pipefail

SERVER="${SERVER:?set SERVER to user@host of the dev box}"
REMOTE_DIR="${REMOTE_DIR:-/home/adam/development/freeland}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/commons}"
GODOT="${GODOT:-godot4}"

mkdir -p "$LOCAL_DIR"

echo "Syncing $SERVER:$REMOTE_DIR → $LOCAL_DIR ..."
# Skip: git history (200MB, not needed to play), Rust build artifacts (5.7GB),
# Godot's import cache (regenerates locally), test reports, and repo-root PNGs
# that are legacy debug screenshots.
rsync -azh --info=progress2 --delete \
  --exclude='.git/' \
  --exclude='backend/freenet/target/' \
  --exclude='.godot/' \
  --exclude='reports/' \
  --exclude='/[a-z_]*.png' \
  --exclude='/[a-z_]*.png.import' \
  --exclude='*.tmp' \
  "$SERVER:$REMOTE_DIR/" "$LOCAL_DIR/"

cd "$LOCAL_DIR"
echo "Launching Godot: $GODOT --path $LOCAL_DIR"
exec "$GODOT" --path .
