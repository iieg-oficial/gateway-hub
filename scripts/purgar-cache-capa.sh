#!/usr/bin/env bash
set -euo pipefail

if [ $# -ne 2 ]; then
    echo "Uso: $0 <workspace-de-geoserver> <capa>" >&2
    exit 2
fi

WS="$1"
CAPA="$2"
if ! [[ "$WS" =~ ^[A-Za-z0-9_]+$ && "$CAPA" =~ ^[A-Za-z0-9_]+$ ]]; then
    echo "Workspace y capa solo admiten letras, numeros y guion bajo" >&2
    exit 2
fi

CONTENEDOR="$(docker compose ps -q nginx 2>/dev/null || true)"
if [ -z "$CONTENEDOR" ]; then
    echo "No encuentro el contenedor nginx del gateway (corre esto desde la raiz de gateway-hub)" >&2
    exit 1
fi

PATRON="${WS}(:|%3A|%3a)${CAPA}([^A-Za-z0-9_]|\$)"
docker exec "$CONTENEDOR" sh -c "
    total=\$(grep -rlaE '^KEY: .*${PATRON}' /var/cache/nginx-data/sextante 2>/dev/null | tee /tmp/purga | wc -l)
    xargs -r rm -f < /tmp/purga
    rm -f /tmp/purga
    echo \"Entradas borradas de la cache de sextante para ${WS}:${CAPA}: \$total\"
"
