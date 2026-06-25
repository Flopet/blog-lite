#!/bin/bash
set -e
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

case "$1" in
  --start)
    TMPFILE=$(mktemp /tmp/Caddyfile.XXXXXX)
    sed "s|root \* /srv|root * ${SCRIPT_DIR}/site|" "${SCRIPT_DIR}/Caddyfile" > "$TMPFILE"
    caddy stop 2>/dev/null || true
    caddy start --config "$TMPFILE"
    rm "$TMPFILE"
    ;;
  --stop)
    caddy stop
    ;;
  *)
    echo "Usage: $0 --start | --stop"
    exit 1
    ;;
esac
