# SearXNG — keyless web search for ingestion

The ingestion service prefers a self-hosted SearXNG instance for its web
searches (card docs, fees/APR pages, merchant offers). Free, no API key, no
rate limits, works from any IP — fixes the search-engine blocking that hits
raw scrapers from a server IP.

## Set up (on the ingestion host)

```bash
cd deploy/searxng

# 1. Set a random secret (SearXNG won't run with the placeholder):
sed -i "s/CHANGE_ME_TO_A_RANDOM_SECRET/$(openssl rand -hex 32)/" config/settings.yml

# 2. Start it:
docker compose up -d

# 3. Point the ingestion service at it:
echo 'SEARXNG_URL=http://localhost:8888' >> /opt/dapp/.env
# (ensure the systemd unit has: EnvironmentFile=/opt/dapp/.env)
systemctl restart bestcard-ingest
```

## Verify

```bash
# SearXNG returns JSON results:
curl -s 'http://localhost:8888/search?q=Emirates+NBD+Platinum&format=json' \
  | python3 -c "import sys,json;print(len(json.load(sys.stdin)['results']),'results')"

# End-to-end add-a-card:
curl -s -X POST https://bestcard-api.baadal.win/ingest -H 'Content-Type: application/json' \
  -d '{"card":"Emirates NBD Mastercard Platinum Credit Card"}' | python3 -m json.tool
```

## Notes
- If SearXNG runs on a different host/container than the ingestion service, set
  `SEARXNG_URL` to that address instead of `localhost`.
- If some engines get throttled, SearXNG rotates the rest; enable more in
  `config/settings.yml` under `engines:`.
- No key is needed. `SEARXNG_URL` is just the instance address, not a secret.
