#!/usr/bin/env bash
# publish_version.sh — publish a version manifest to Freenet.
#
# Usage:
#   ./scripts/publish_version.sh <version> <download_url> [min_protocol_version]
#
# Examples:
#   ./scripts/publish_version.sh 0.3.0 https://github.com/you/freeland/releases/tag/v0.3.0
#   ./scripts/publish_version.sh 0.4.0 https://github.com/you/freeland/releases/tag/v0.4.0 2
#
# Requires:
#   - freenet network running and freeland-proxy running on ws://127.0.0.1:7510
#   - version-manifest contract built:
#       cd backend/freenet/contracts/version-manifest
#       CARGO_TARGET_DIR=../../target fdev build
#
# The manifest is PUT to the version-manifest contract on the Freenet network.
# All connected nodes will receive the update within minutes.

set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

VERSION="${1:-}"
DOWNLOAD_URL="${2:-}"
MIN_PROTO="${3:-1}"

if [ -z "$VERSION" ] || [ -z "$DOWNLOAD_URL" ]; then
    echo "Usage: $0 <version> <download_url> [min_protocol_version]"
    echo "Example: $0 0.3.0 https://github.com/you/freeland/releases/tag/v0.3.0"
    exit 1
fi

if [[ "$DOWNLOAD_URL" != https://github.com/* ]]; then
    echo "Error: download_url must start with https://github.com/"
    exit 1
fi

PROXY_URL="${FREELAND_PROXY_URL:-ws://127.0.0.1:7510}"
COMMIT=$(git -C "$PROJECT_ROOT" rev-parse --short HEAD 2>/dev/null || echo "unknown")
TS=$(date +%s)

MANIFEST_JSON="{\"version\":\"$VERSION\",\"commit\":\"$COMMIT\",\"published_at\":$TS.0,\"download_url\":\"$DOWNLOAD_URL\",\"min_protocol_version\":$MIN_PROTO}"

echo "Publishing version manifest:"
echo "  version:              $VERSION"
echo "  commit:               $COMMIT"
echo "  published_at:         $TS"
echo "  download_url:         $DOWNLOAD_URL"
echo "  min_protocol_version: $MIN_PROTO"
echo ""
echo "Proxy: $PROXY_URL"
echo ""

# Use a small Python script (available on all platforms) to send the WS message.
python3 - "$PROXY_URL" "$MANIFEST_JSON" <<'PYEOF'
import json, sys

proxy_url = sys.argv[1]
manifest_json = sys.argv[2]

try:
    import websocket
except ImportError:
    print("Error: websocket-client not installed. Run: pip install websocket-client")
    sys.exit(1)

request = {"op": "PutVersionManifest", "manifest_json": manifest_json}

ws = websocket.create_connection(proxy_url, timeout=10)
ws.send(json.dumps(request))
resp = json.loads(ws.recv())
ws.close()

if resp.get("op") == "PutVersionManifestOk":
    print("Version manifest published successfully.")
elif resp.get("op") == "Error":
    print("Error:", resp.get("message", "unknown"))
    sys.exit(1)
else:
    print("Unexpected response:", resp)
    sys.exit(1)
PYEOF
