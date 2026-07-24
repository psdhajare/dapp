#!/usr/bin/env bash
# Bring the ingestion stack up (idempotent). Run inside CT 104:
#   bash /opt/dapp/ingestion/deploy/up.sh
# Normally not needed — the service is enabled and Docker containers use
# restart:unless-stopped, so a reboot recovers automatically. This is a
# one-shot recovery / manual-start helper.
set -euo pipefail
cd /opt/dapp

echo "== Docker =="
systemctl start docker 2>/dev/null || true

echo "== Search stack (SearXNG + valkey) =="
if [ -f deploy/searxng/docker-compose.yml ]; then
  (cd deploy/searxng && (docker compose up -d || docker-compose up -d)) || \
    echo "  (search stack not started; Brave still works as primary)"
fi

echo "== Ingestion service =="
systemctl start bestcard-ingest

echo "== Health =="
for i in $(seq 1 20); do
  if curl -fsS http://localhost:8765/health >/dev/null 2>&1; then
    echo "  ingestion UP  ->  $(curl -s http://localhost:8765/health)"
    exit 0
  fi
  sleep 1
done
echo "  NOT healthy. Check: journalctl -u bestcard-ingest -n 50 --no-pager"
exit 1
