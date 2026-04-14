#!/usr/bin/env bash
# visual_test.sh — helpers for xpra-based visual testing of Freeland
#
# Usage:
#   visual_test.sh start-host [port]              Start Godot as host (default port 7777)
#   visual_test.sh start-client [ip] [port]       Start Godot as client (default 127.0.0.1:7777)
#   visual_test.sh start-host-dev [port]          Start host with --dev-instant-merge (Phase 4 testing)
#   visual_test.sh start-client-dev [ip] [port]   Start client with --dev-instant-merge (Phase 4 testing)
#   visual_test.sh stop-all                       Kill all Godot processes
#   visual_test.sh status                         Show running Godot PIDs and tail logs
#   visual_test.sh key-js <key> [code] [keyCode]  Print JS snippet for one keydown+keyup
#   visual_test.sh walk <dir> <frames>            Print JS snippet to walk in direction for N frames
#   visual_test.sh run-tests                      Run full gdUnit4 test suite headless
#   visual_test.sh ensure-xpra                    Start xpra service if not running
#
# xpra runs in DESKTOP mode (xfwm4). The browser shows a single canvas rendering the full
# virtual desktop. Both Godot windows are pre-positioned side by side (host left, client right).
#
# Key/mouse dispatch in desktop mode:
#   - X11 focus follows the mouse: click the desired window area first (using browser click
#     at the xpra canvas coordinates), then dispatch keyboard events to document.
#   - The walk/key-js helpers below dispatch to document — the focused X11 window receives them.
#   - Host window: virtual desktop X 0–959, Y 0–719. Browser coords ≈ (0–500, 0–370) at 1920→1280 scale.
#   - Client window: virtual desktop X 960–1919, Y 0–719. Browser coords ≈ (500–1280, 0–370).

set -euo pipefail

GODOT="${GODOT:-$HOME/bin/godot4}"
PROJECT="/home/adam/development/freeland"
DISPLAY_NUM="${DISPLAY_NUM:-:100}"
RENDERING="opengl3"
# Side-by-side layout: host at left, client at right (960px each in a 1920x1080 desktop)
HOST_POS="0,0"
CLIENT_POS="960,0"
WIN_RES="960x720"

cmd="${1:-help}"
shift || true

case "$cmd" in

  ensure-xpra)
    if xpra list 2>/dev/null | grep -q "LIVE"; then
      echo "xpra: already running"
    else
      echo "xpra: starting service..."
      systemctl --user start xpra.service
      sleep 2
      xpra list
    fi
    ;;

  start-host)
    port="${1:-7777}"
    echo "Starting host on port $port (position $HOST_POS)..."
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      --position "$HOST_POS" \
      --resolution "$WIN_RES" \
      -- --host "$port" \
      > /tmp/freeland-host.log 2>&1 &
    echo "Host PID: $!"
    echo "$!" > /tmp/freeland-host.pid
    ;;

  start-client)
    ip="${1:-127.0.0.1}"
    port="${2:-7777}"
    echo "Starting client → $ip:$port (position $CLIENT_POS)..."
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      --position "$CLIENT_POS" \
      --resolution "$WIN_RES" \
      -- --join "$ip" "$port" \
      > /tmp/freeland-client.log 2>&1 &
    echo "Client PID: $!"
    echo "$!" > /tmp/freeland-client.pid
    ;;

  # Dev variants with --dev-instant-merge: pressure starts at 1.0, broadcast every 1s.
  # Also passes --host/--join so ENet connects immediately (single-machine UDP port
  # conflict prevents auto-discovery when both instances run on the same host).
  start-host-dev)
    port="${1:-7777}"
    echo "Starting host (dev-instant-merge) on port $port (position $HOST_POS)..."
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      --position "$HOST_POS" \
      --resolution "$WIN_RES" \
      -- --host "$port" --dev-instant-merge \
      > /tmp/freeland-host.log 2>&1 &
    echo "Host PID: $!"
    echo "$!" > /tmp/freeland-host.pid
    ;;

  start-client-dev)
    ip="${1:-127.0.0.1}"
    port="${2:-7777}"
    echo "Starting client (dev-instant-merge) → $ip:$port (position $CLIENT_POS)..."
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      --position "$CLIENT_POS" \
      --resolution "$WIN_RES" \
      -- --join "$ip" "$port" --dev-instant-merge \
      > /tmp/freeland-client.log 2>&1 &
    echo "Client PID: $!"
    echo "$!" > /tmp/freeland-client.pid
    ;;

  stop-all)
    echo "Stopping all Godot instances..."
    pkill -f "godot4.*freeland" 2>/dev/null && echo "killed" || echo "none running"
    rm -f /tmp/freeland-host.pid /tmp/freeland-client.pid
    ;;

  status)
    echo "=== Running Godot processes ==="
    pgrep -a -f "godot4.*freeland" || echo "none"
    echo ""
    echo "=== Logs: host ==="
    tail -20 /tmp/freeland-host.log 2>/dev/null || echo "(no log)"
    echo ""
    echo "=== Logs: client ==="
    tail -20 /tmp/freeland-client.log 2>/dev/null || echo "(no log)"
    ;;

  # Print a JS snippet that dispatches a single keydown+keyup event to the focused window.
  # In desktop mode, click the desired Godot window in the browser first to give it X11 focus,
  # then paste this into Playwright browser_evaluate.
  key-js)
    key="${1:?Usage: key-js <key> [code] [keyCode]}"
    code="${2:-$key}"
    keycode="${3:-0}"
    cat <<JS
document.dispatchEvent(new KeyboardEvent('keydown', {key:'$key', code:'$code', keyCode:$keycode, bubbles:true}));
document.dispatchEvent(new KeyboardEvent('keyup',   {key:'$key', code:'$code', keyCode:$keycode, bubbles:true}));
JS
    ;;

  # Print a JS snippet that holds a direction key for N animation frames (~16ms each).
  # In desktop mode: click the desired window first to focus it, then run this.
  walk)
    dir="${1:?Usage: walk <left|right|up|down> <frames>}"
    frames="${2:-60}"
    case "$dir" in
      left)  key="ArrowLeft";  code="ArrowLeft";  kc=37 ;;
      right) key="ArrowRight"; code="ArrowRight"; kc=39 ;;
      up)    key="ArrowUp";    code="ArrowUp";    kc=38 ;;
      down)  key="ArrowDown";  code="ArrowDown";  kc=40 ;;
      *) echo "Unknown direction: $dir (use left/right/up/down)"; exit 1 ;;
    esac
    # Use setInterval for reliability — setTimeout(keyup) is dropped if the tab loses focus mid-hold.
    count=$(( frames ))
    cat <<JS
(() => {
  let n = 0;
  const iv = setInterval(() => {
    document.dispatchEvent(new KeyboardEvent('keydown', {key:'$key', code:'$code', keyCode:$kc, bubbles:true}));
    if (++n >= $count) {
      clearInterval(iv);
      document.dispatchEvent(new KeyboardEvent('keyup', {key:'$key', code:'$code', keyCode:$kc, bubbles:true}));
    }
  }, 16);
})();
JS
    ;;

  # Run the full gdUnit4 test suite headless.
  run-tests)
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      --headless -s addons/gdUnit4/bin/GdUnitCmdTool.gd \
      -a res://tests/ -c --ignoreHeadlessMode
    ;;

  help|*)
    sed -n '3,23p' "$0"
    ;;
esac
