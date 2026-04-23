#!/usr/bin/env bash
# dev/play.sh — run on the LAPTOP. Pulls the latest Commons playtest binary
# from the dev server, runs it, then ships logs and screenshots back so the
# server agent can inspect what happened in this session.
#
# Requirements on the laptop: rsync + ssh access. No Godot install needed —
# the exported binary is self-contained.
#
# Usage:
#   SERVER=adam@your-server ./play.sh
#
# Optional overrides:
#   REMOTE_DIR  repo path on the server    (default: /home/adam/development/freeland)
#   LOCAL_DIR   where the binary lives     (default: $HOME/commons-playtest)
#
# Bootstrap (once):
#   ssh <server> 'cat development/freeland/dev/play.sh' > ~/play.sh
#   chmod +x ~/play.sh
set -euo pipefail

SERVER="${SERVER:?set SERVER to user@host of the dev server}"
REMOTE_DIR="${REMOTE_DIR:-/home/adam/development/freeland}"
LOCAL_DIR="${LOCAL_DIR:-$HOME/commons-playtest}"

mkdir -p "$LOCAL_DIR"

echo "=> Pulling latest build from $SERVER ..."
# Pulls commons.x86_64 and any sibling runtime libs (e.g. libwebrtc_native.so).
rsync -azh --info=progress2 --delete \
  "$SERVER:$REMOTE_DIR/build/" \
  "$LOCAL_DIR/"
chmod +x "$LOCAL_DIR/commons.x86_64"

# Ensure logs and screenshots from any previous session are shipped even if
# the user hard-kills this run. Trap runs on normal exit, Ctrl+C, or error.
ship_back() {
  local userdata="$HOME/.local/share/godot/app_userdata/Commons"
  local stamp
  stamp="$(date -u +%Y%m%d-%H%M%S)"
  local dest="$REMOTE_DIR/playtest-reports/$stamp"
  echo "=> Shipping session to $SERVER:$dest ..."
  if [[ -d "$userdata/logs" ]]; then
    rsync -azh "$userdata/logs/" "$SERVER:$dest/logs/" || true
  fi
  if [[ -d "$userdata/screenshots" ]]; then
    rsync -azh "$userdata/screenshots/" "$SERVER:$dest/screenshots/" || true
  fi
  echo "=> Done: $dest"
}
trap ship_back EXIT

echo "=> Launching Commons ..."
"$LOCAL_DIR/commons.x86_64" || true   # don't abort the trap on ctrl-C
