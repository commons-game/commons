#!/usr/bin/env bash
# run_multiplayer_local.sh — start two game instances for local multiplayer testing.
#
# Requires:
#   - freeland-dev-proxy built:
#       cd backend/freenet && ~/.cargo/bin/cargo build --bin freeland-dev-proxy
#   - godot4 on PATH
#
# Usage:
#   ./scripts/run_multiplayer_local.sh
#
# Both instances use --dev-instant-merge so they merge as soon as they discover
# each other (no pressure build-up wait). Watch the terminals for:
#   "WebRTC pairing needed"  → offer/answer exchange started
#   "WebRTC peer established" → connection done
#   "merge_ready"            → CRDT sync complete

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PROXY_BIN="$PROJECT_ROOT/backend/freenet/target/debug/freeland-dev-proxy"

if [ ! -f "$PROXY_BIN" ]; then
    echo "Dev proxy not built. Building now..."
    (cd "$PROJECT_ROOT/backend/freenet" && ~/.cargo/bin/cargo build --bin freeland-dev-proxy)
fi

echo "Starting dev proxy on ws://127.0.0.1:7510 ..."
"$PROXY_BIN" 127.0.0.1:7510 &
PROXY_PID=$!
trap "kill $PROXY_PID 2>/dev/null; exit" INT TERM EXIT
sleep 0.5   # let the proxy bind

echo ""
echo "Starting game instance A (player-A)..."
godot4 --headless --path "$PROJECT_ROOT" -- --dev-instant-merge \
    > /tmp/freeland_A.log 2>&1 &
PID_A=$!

sleep 0.3

echo "Starting game instance B (player-B)..."
godot4 --headless --path "$PROJECT_ROOT" -- --dev-instant-merge \
    > /tmp/freeland_B.log 2>&1 &
PID_B=$!

echo ""
echo "Both instances running."
echo "  Instance A log: /tmp/freeland_A.log"
echo "  Instance B log: /tmp/freeland_B.log"
echo ""
echo "Watch for WebRTC connection:"
echo "  tail -f /tmp/freeland_A.log | grep -i 'webrtc\|merge\|peer'"
echo ""
echo "Press Ctrl+C to stop everything."

wait $PID_A $PID_B
