#!/usr/bin/env bash
# Build all Freenet contract and delegate packages using fdev.
#
# Usage:
#   scripts/build_contracts.sh
#
# Outputs:
#   backend/freenet/contracts/chunk-contract/build/freenet/commons_chunk_contract
#   backend/freenet/contracts/lobby-contract/build/freenet/commons_lobby_contract
#   backend/freenet/contracts/pairing-contract/build/freenet/commons_pairing_contract
#   backend/freenet/delegates/player-delegate/build/freenet/commons_player_delegate
#
# NOTE: Always use these fdev-built packages, never the raw
# target/wasm32-unknown-unknown/*.wasm files. The raw WASM files are missing
# the API version metadata that the Freenet node requires, and will produce
# "unsupported incremental API version" errors.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FREENET_DIR="$SCRIPT_DIR/../backend/freenet"

# fdev uses `cargo` internally; ~/.cargo/bin is not always on PATH.
export PATH="$HOME/.cargo/bin:$PATH"

FDEV="${HOME}/.local/bin/fdev"
if ! command -v "$FDEV" &>/dev/null; then
    echo "ERROR: fdev not found at $FDEV" >&2
    echo "Install it via: curl -fsSL https://freenet.org/install.sh | sh" >&2
    exit 1
fi

CONTRACTS=(chunk-contract lobby-contract pairing-contract)
DELEGATES=(player-delegate)

for contract in "${CONTRACTS[@]}"; do
    dir="$FREENET_DIR/contracts/$contract"
    echo "=== Building contract $contract ==="
    (cd "$dir" && CARGO_TARGET_DIR="$FREENET_DIR/target" "$FDEV" build)
done

for delegate in "${DELEGATES[@]}"; do
    dir="$FREENET_DIR/delegates/$delegate"
    echo "=== Building delegate $delegate ==="
    (cd "$dir" && CARGO_TARGET_DIR="$FREENET_DIR/target" "$FDEV" build --package-type delegate)
done

echo ""
echo "Contract packages written to:"
for contract in "${CONTRACTS[@]}"; do
    name="${contract//-/_}"          # chunk-contract → chunk_contract
    name="${name/commons_/}"        # strip any existing prefix
    pkg="$FREENET_DIR/contracts/$contract/build/freenet/commons_${name//-/_}"
    echo "  $pkg"
done

echo ""
echo "Delegate packages written to:"
for delegate in "${DELEGATES[@]}"; do
    name="${delegate//-/_}"          # player-delegate → player_delegate
    pkg="$FREENET_DIR/delegates/$delegate/build/freenet/commons_${name}"
    echo "  $pkg"
done
