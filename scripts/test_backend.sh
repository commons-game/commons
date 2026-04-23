#!/usr/bin/env bash
# Run all backend checks: unit tests + integration test type-check.
#
# The integration tests (round_trip.rs) are gated behind --features integration
# so they never run against a live node in normal CI. But their code still needs
# to compile. This script runs `cargo check --features integration` to catch
# signature mismatches (e.g. run_listener argument count changing) before they
# become silent surprises discovered only when running against a live node.
#
# Usage:
#   scripts/test_backend.sh             # check + unit tests
#   LIVE=1 scripts/test_backend.sh      # also run integration tests (needs env vars)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FREENET_DIR="$SCRIPT_DIR/../backend/freenet"

export PATH="$HOME/.cargo/bin:$PATH"

cd "$FREENET_DIR"

echo "=== Unit tests ==="
cargo test

echo ""
echo "=== Integration test type-check (--features integration) ==="
cargo check --features integration -p commons-proxy
echo "Type-check passed — integration test signatures are valid."

if [[ "${LIVE:-}" == "1" ]]; then
    echo ""
    echo "=== Live integration tests ==="
    : "${FREENET_NODE_URL:?FREENET_NODE_URL must be set}"
    : "${COMMONS_CONTRACT_PATH:?COMMONS_CONTRACT_PATH must be set}"
    : "${COMMONS_LOBBY_CONTRACT_PATH:?COMMONS_LOBBY_CONTRACT_PATH must be set}"
    : "${COMMONS_PAIRING_CONTRACT_PATH:?COMMONS_PAIRING_CONTRACT_PATH must be set}"
    : "${COMMONS_PLAYER_DELEGATE_PATH:?COMMONS_PLAYER_DELEGATE_PATH must be set}"
    cargo test --features integration -p commons-proxy -- --nocapture
fi

echo ""
echo "All backend checks passed."
