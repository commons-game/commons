#!/usr/bin/env bash
# scripts/update_freenet_pin.sh — run Tier-2 integration, pin the node
# version we verified against on success.
#
# Flow:
#   1. Runs scripts/run-freenet-integration.sh (which builds contracts +
#      runs cargo test --features integration).
#   2. If green, queries `freenet --version` and writes the string to
#      backend/freenet/FREENET_VERSION (first line).
#   3. Prints the diff so you review it before committing.
#
# If step 1 fails, the pin is NOT updated. This is the whole point —
# drift between the pinned version and the installed node is the loud
# failure we want.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
PIN_FILE="$REPO_ROOT/backend/freenet/FREENET_VERSION"
FREENET_BIN="${FREENET_BIN:-$HOME/.local/bin/freenet}"

if ! command -v "$FREENET_BIN" &>/dev/null; then
  echo "ERROR: freenet binary not found at $FREENET_BIN." >&2
  echo "       Set FREENET_BIN=<path> or install via https://freenet.org/install.sh" >&2
  exit 1
fi

echo "=> Running Tier-2 round-trip tests ..."
"$SCRIPT_DIR/run-freenet-integration.sh"

echo "=> Tests passed. Capturing node version ..."
VERSION_LINE="$("$FREENET_BIN" --version 2>&1 | head -1)"
if [[ -z "$VERSION_LINE" ]]; then
  echo "ERROR: freenet --version produced no output." >&2
  exit 1
fi

TMP="$(mktemp)"
{
  echo "$VERSION_LINE"
  tail -n +2 "$PIN_FILE"
} > "$TMP"
mv "$TMP" "$PIN_FILE"

echo "=> Pinned: $VERSION_LINE"
echo "=> Diff:"
( cd "$REPO_ROOT" && git --no-pager diff -- backend/freenet/FREENET_VERSION ) || true
echo "=> Commit with: git add $PIN_FILE && git commit -m 'chore: pin Freenet version to $VERSION_LINE'"
