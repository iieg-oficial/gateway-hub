#!/usr/bin/env bash
# Genera nginx/version.json a partir de VERSION + docs/CHANGELOG.md.
# Llamado por `make version-json`. Idempotente.
set -euo pipefail

SERVICE="gateway-hub"
LABEL="Gateway Hub"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"

VERSION="$(tr -d '[:space:]' < "$ROOT/VERSION")"
RELEASED_AT="$(grep -m1 "^## \[$VERSION\]" "$ROOT/docs/CHANGELOG.md" \
    | sed -E 's/^## \[[^]]+\] - ([0-9-]+).*/\1/' || true)"

if [ -z "$RELEASED_AT" ]; then
    echo "WARN: no se encontro entrada '## [$VERSION] - YYYY-MM-DD' en docs/CHANGELOG.md" >&2
fi

printf '{"slug":"%s","label":"%s","version":"%s","released_at":"%s"}\n' \
    "$SERVICE" "$LABEL" "$VERSION" "$RELEASED_AT" \
    > "$ROOT/nginx/version.json"

echo "nginx/version.json -> $VERSION ($SERVICE, $RELEASED_AT)"
