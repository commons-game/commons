#!/usr/bin/env bash
# build_export.sh — build all backend binaries and copy them into the export bin/ directory.
#
# Run this before exporting the Godot project.
# Output goes to export/bin/ (create it if needed).
#
# Usage: ./scripts/build_export.sh [output_dir]
#   output_dir defaults to ./export/bin

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BACKEND="$PROJECT_ROOT/backend/freenet"
OUT="${1:-$PROJECT_ROOT/export/bin}"

mkdir -p "$OUT"
export PATH="$HOME/.cargo/bin:$PATH"

echo "Building backend binaries..."

# freeland-proxy
echo "  freeland-proxy..."
(cd "$BACKEND" && cargo build --bin freeland-proxy --release 2>&1 | tail -3)
cp "$BACKEND/target/release/freeland-proxy" "$OUT/freeland-proxy"

# Build and copy all contract/delegate WASM packages
echo "  contracts and delegate..."
for dir in \
    "contracts/chunk-contract" \
    "contracts/lobby-contract" \
    "contracts/pairing-contract" \
    "contracts/error-contract" \
    "contracts/version-manifest"; do
    (cd "$BACKEND/$dir" && CARGO_TARGET_DIR=../../target fdev build 2>&1 | tail -2)
done

(cd "$BACKEND/delegates/player-delegate" && CARGO_TARGET_DIR=../../target fdev build --package-type delegate 2>&1 | tail -2)

cp "$BACKEND/contracts/chunk-contract/build/freenet/freeland_chunk_contract"       "$OUT/"
cp "$BACKEND/contracts/lobby-contract/build/freenet/freeland_lobby_contract"       "$OUT/"
cp "$BACKEND/contracts/pairing-contract/build/freenet/freeland_pairing_contract"   "$OUT/"
cp "$BACKEND/contracts/error-contract/build/freenet/freeland_error_contract"       "$OUT/"
cp "$BACKEND/contracts/version-manifest/build/freenet/freeland_version_manifest"   "$OUT/"
cp "$BACKEND/delegates/player-delegate/build/freenet/freeland_player_delegate"     "$OUT/"

# freenet binary — copy from ~/.local/bin if available
if [ -f "$HOME/.local/bin/freenet" ]; then
    echo "  freenet binary (from ~/.local/bin)..."
    cp "$HOME/.local/bin/freenet" "$OUT/freenet"
else
    echo "  WARNING: freenet binary not found at ~/.local/bin/freenet"
    echo "  Install it with: curl -fsSL https://freenet.org/install.sh | sh"
fi

echo ""
echo "Export bin/ contents:"
ls -lh "$OUT/"
echo ""
echo "Done. Copy the game binary alongside export/bin/ before distributing."
