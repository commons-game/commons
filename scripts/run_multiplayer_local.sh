#!/usr/bin/env bash
# run_multiplayer_local.sh — start two game instances for local multiplayer testing.
#
# Modes:
#   (no args)              — start freeland-dev-proxy (in-memory, no Freenet node needed)
#   --freenet              — start real Freenet node + freeland-proxy (requires `freenet` on PATH)
#   ws://192.168.1.10:7510 — external proxy, nothing local started
#
# Requires:
#   - dev proxy:     cd backend/freenet && cargo build --bin freeland-dev-proxy
#   - freenet proxy: cargo build --bin freeland-proxy  AND  fdev build in each contract dir
#   - godot4 on PATH
#
# NOTE: `freenet local` binds its WS API on [::1]:7509 (IPv6 loopback), not 127.0.0.1.
# The proxy uses FREENET_NODE_URL=ws://[::1]:7509/... to match this.
#
# Both instances use --dev-instant-merge so they merge as soon as they discover
# each other. Watch the terminals for:
#   "WebRTC pairing needed"   → offer/answer exchange started
#   "WebRTC peer established" → connection done
#   "merge_ready"             → CRDT sync complete

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND="$PROJECT_ROOT/backend/freenet"

PROXY_URL="${1:-}"
PROXY_PID=""
FREENET_PID=""

if [ -z "$PROXY_URL" ]; then
    # No arg — start local dev proxy (default)
    PROXY_BIN="$BACKEND/target/debug/freeland-dev-proxy"
    if [ ! -f "$PROXY_BIN" ]; then
        echo "Dev proxy not built. Building now..."
        (cd "$BACKEND" && ~/.cargo/bin/cargo build --bin freeland-dev-proxy)
    fi
    PROXY_URL="ws://127.0.0.1:7510"
    echo "Starting dev proxy on $PROXY_URL ..."
    "$PROXY_BIN" 127.0.0.1:7510 &
    PROXY_PID=$!
    trap "kill $PROXY_PID 2>/dev/null; exit" INT TERM EXIT
    sleep 0.5   # let the proxy bind

elif [ "$1" = "--freenet" ]; then
    # Real Freenet mode: start local node + freeland-proxy
    PROXY_URL="ws://127.0.0.1:7510"

    echo "Starting Freenet local node on [::1]:7509 ..."
    freenet local > /tmp/freenet_node.log 2>&1 &
    FREENET_PID=$!
    sleep 1   # wait for node to bind

    PROXY_BIN="$BACKEND/target/debug/freeland-proxy"
    if [ ! -f "$PROXY_BIN" ]; then
        echo "freeland-proxy not built. Building now..."
        (cd "$BACKEND" && ~/.cargo/bin/cargo build --bin freeland-proxy)
    fi

    echo "Starting freeland-proxy on $PROXY_URL ..."
    FREENET_NODE_URL="ws://[::1]:7509/v1/contract/command?encodingProtocol=native" \
    FREELAND_CONTRACT_PATH="$BACKEND/contracts/chunk-contract/build/freenet/freeland_chunk_contract" \
    FREELAND_LOBBY_CONTRACT_PATH="$BACKEND/contracts/lobby-contract/build/freenet/freeland_lobby_contract" \
    FREELAND_PAIRING_CONTRACT_PATH="$BACKEND/contracts/pairing-contract/build/freenet/freeland_pairing_contract" \
    FREELAND_PLAYER_DELEGATE_PATH="$BACKEND/delegates/player-delegate/build/freenet/freeland_player_delegate" \
    "$PROXY_BIN" > /tmp/freeland_proxy.log 2>&1 &
    PROXY_PID=$!
    trap "kill $PROXY_PID $FREENET_PID 2>/dev/null; exit" INT TERM EXIT
    sleep 0.5

    echo "Freenet node log:  /tmp/freenet_node.log"
    echo "Proxy log:         /tmp/freeland_proxy.log"

else
    echo "Using external proxy: $PROXY_URL"
fi

echo ""
echo "Starting game instance A..."
godot4 --headless --path "$PROJECT_ROOT" -- --dev-instant-merge --proxy-url="$PROXY_URL" \
    > /tmp/freeland_A.log 2>&1 &
PID_A=$!

sleep 0.3

echo "Starting game instance B..."
godot4 --headless --path "$PROJECT_ROOT" -- --dev-instant-merge --proxy-url="$PROXY_URL" \
    > /tmp/freeland_B.log 2>&1 &
PID_B=$!

echo ""
echo "Both instances running (proxy: $PROXY_URL)."
echo "  Instance A log: /tmp/freeland_A.log"
echo "  Instance B log: /tmp/freeland_B.log"
echo ""
echo "Watch for WebRTC connection:"
echo "  tail -f /tmp/freeland_A.log | grep -i 'webrtc\|merge\|peer'"
echo ""
echo "Press Ctrl+C to stop everything."

wait $PID_A $PID_B
