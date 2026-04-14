#!/usr/bin/env bash
# visual_test.sh — helpers for xpra-based visual testing of Freeland
#
# Usage:
#   visual_test.sh start-host [port]       Start Godot as host (default port 7777)
#   visual_test.sh start-client [ip] [port] Start Godot as client (default 127.0.0.1:7777)
#   visual_test.sh stop-all                Kill all Godot processes
#   visual_test.sh status                  Show running Godot PIDs
#   visual_test.sh key-js <key> [code] [keyCode]  Print JS snippet for one keydown
#   visual_test.sh walk <dir> <frames>     Print JS snippet to walk in direction for N frames
#   visual_test.sh ensure-xpra            Start xpra service if not running
#
# Key dispatch works via xpra's web client (Playwright browser_evaluate).
# Example keys: ArrowLeft ArrowRight ArrowUp ArrowDown
# xdotool does NOT work through xpra — always use the JS path.

set -euo pipefail

GODOT="${GODOT:-$HOME/bin/godot4}"
PROJECT="/home/adam/development/freeland"
DISPLAY_NUM="${DISPLAY_NUM:-:100}"
RENDERING="opengl3"

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
    echo "Starting host on port $port..."
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      -- --host --port "$port" \
      > /tmp/freeland-host.log 2>&1 &
    echo "Host PID: $!"
    echo "$!" > /tmp/freeland-host.pid
    ;;

  start-client)
    ip="${1:-127.0.0.1}"
    port="${2:-7777}"
    echo "Starting client → $ip:$port ..."
    DISPLAY="$DISPLAY_NUM" "$GODOT" \
      --rendering-driver "$RENDERING" \
      --path "$PROJECT" \
      -- --client --host-ip "$ip" --port "$port" \
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

  # Print a JS snippet that dispatches a single keydown+keyup event.
  # Paste into Playwright browser_evaluate.
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
  # Paste into Playwright browser_evaluate.
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
    ms=$(( frames * 16 ))
    cat <<JS
(async () => {
  const ev = (t) => document.dispatchEvent(new KeyboardEvent(t, {
    key: '$key', code: '$code', keyCode: $kc, bubbles: true
  }));
  ev('keydown');
  await new Promise(r => setTimeout(r, $ms));
  ev('keyup');
})();
JS
    ;;

  help|*)
    sed -n '3,13p' "$0"
    ;;
esac
