#!/usr/bin/env bash
# scripts/run-freenet-integration.sh — Tier-2 multiplayer test runner.
#
# Runs the commons-proxy round-trip integration tests against a live Freenet
# node. Needs: Freenet node running on localhost, fdev installed, contracts
# built. This is the manual guard you flip BEFORE flipping use_freenet=true
# in production — catches wire-protocol drift, contract-format drift, and
# node version mismatches.
#
# Usage:
#   scripts/run-freenet-integration.sh
#
# Environment overrides:
#   FREENET_NODE_URL  — default ws://127.0.0.1:50509/v1/contract/command?encodingProtocol=native
#   SKIP_BUILD        — set to 1 to skip the contract rebuild step
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR/.."
FREENET_DIR="$REPO_ROOT/backend/freenet"

export FREENET_NODE_URL="${FREENET_NODE_URL:-ws://127.0.0.1:50509/v1/contract/command?encodingProtocol=native}"
export PATH="$HOME/.cargo/bin:$PATH"

if [[ -z "${SKIP_BUILD:-}" ]]; then
  echo "=> Building contracts and delegates (set SKIP_BUILD=1 to skip) ..."
  "$SCRIPT_DIR/build_contracts.sh"
fi

# Point the tests at the fdev-built packages.
export COMMONS_CONTRACT_PATH="$FREENET_DIR/contracts/chunk-contract/build/freenet/commons_chunk_contract"
export COMMONS_LOBBY_CONTRACT_PATH="$FREENET_DIR/contracts/lobby-contract/build/freenet/commons_lobby_contract"
export COMMONS_PAIRING_CONTRACT_PATH="$FREENET_DIR/contracts/pairing-contract/build/freenet/commons_pairing_contract"
export COMMONS_PLAYER_DELEGATE_PATH="$FREENET_DIR/delegates/player-delegate/build/freenet/commons_player_delegate"

for v in COMMONS_CONTRACT_PATH COMMONS_LOBBY_CONTRACT_PATH COMMONS_PAIRING_CONTRACT_PATH COMMONS_PLAYER_DELEGATE_PATH; do
  eval "p=\$$v"
  if [[ ! -f "$p" ]]; then
    echo "ERROR: $v points at $p which does not exist." >&2
    echo "       Make sure fdev build succeeded; remove SKIP_BUILD=1 if you set it." >&2
    exit 1
  fi
done

echo "=> Running cargo test --features integration against $FREENET_NODE_URL ..."
cd "$FREENET_DIR"
exec cargo test -p commons-proxy --features integration -- --nocapture
