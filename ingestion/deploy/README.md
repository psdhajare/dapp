# Ingestion service — Proxmox LXC deploy

Hosts the card-ingestion HTTP API on your home server. The Flutter web app
(on Cloudflare Pages) calls it to add cards. Home residential IP means the
web-search step works; full Python means PDFs parse.

## 1. Create the container

- Proxmox → create an **unprivileged LXC**, Debian 12 or Ubuntu 24.04, 1 vCPU /
  1 GB RAM / 8 GB disk is plenty. Give it a static IP on your LAN, e.g.
  `192.168.1.50`.

## 2. Install and place the code

```bash
apt update && apt install -y python3 python3-pip git
adduser --system --group --home /opt/dapp dapp

# Put the repo at /opt/dapp (git clone, or copy ingestion/ + db/ over scp).
git clone <your-repo-url> /opt/dapp        # or rsync the project
chown -R dapp:dapp /opt/dapp

pip3 install --break-system-packages -r /opt/dapp/ingestion/requirements.txt
```

The service needs `ingestion/`, `db/schema.sql`, `db/seed.sql` present. It
writes a working `db/cards.db` in the WorkingDirectory (harmless; the app only
uses the returned JSON).

## 3. Secrets

Create `/opt/dapp/.env`:

```
DEEPSEEK_API_KEY=sk-...          # your key
BRAVE_API_KEY=BSA...             # Brave Search API key (default web search)
SEARXNG_URL=http://localhost:8888  # free fallback when Brave is unset/errors
GEOIP_DB=/opt/geoip/GeoLite2-Country.mmdb  # local IP->country (optional)
INGEST_HOST=0.0.0.0
INGEST_PORT=8765
INGEST_DB=db/cards.db
```

`chown dapp:dapp /opt/dapp/.env && chmod 600 /opt/dapp/.env`

**Search provider:** Brave is used by default when `BRAVE_API_KEY` is set
(reliable from a server IP, and regionally biased by the caller's country); it
falls back to SearXNG then keyless scrapers when unset or on error. Get a free
key (~2000 queries/mo) at <https://brave.com/search/api/> and paste it into
`.env` as `BRAVE_API_KEY`, then `systemctl restart bestcard-ingest`.

## 3b. GeoLite2 country DB (optional but recommended)

Lets the server infer the user's country from the request IP (no client
involvement) to localize merchant-offer search. Lookups no-op gracefully if the
DB is absent, so this is optional.

```bash
# One-time: create a free MaxMind account -> generate a License Key.
#   https://www.maxmind.com/en/geolite2/signup
mkdir -p /opt/geoip
# Option A: geoipupdate (auto-refreshes monthly) — put AccountID + LicenseKey
#   in /etc/GeoIP.conf with EditionIDs=GeoLite2-Country, then:
apt-get install -y geoipupdate && geoipupdate            # -> /usr/share/GeoIP/GeoLite2-Country.mmdb
ln -sf /usr/share/GeoIP/GeoLite2-Country.mmdb /opt/geoip/GeoLite2-Country.mmdb
# Option B: download the tarball with your license key and extract the .mmdb
#   to /opt/geoip/GeoLite2-Country.mmdb
chown -R dapp:dapp /opt/geoip
```

The DB is **not** in the repo (MaxMind licence). Attribution required by their
terms. `pip3 install -r ingestion/requirements.txt` pulls the `geoip2` lib.

## 4. Run as a service

```bash
cp /opt/dapp/ingestion/deploy/bestcard-ingest.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now bestcard-ingest
systemctl status bestcard-ingest        # should be active (running)
curl -s http://localhost:8765/health    # {"status": "ok"}
```

## 5. Nginx Proxy Manager

Add a **Proxy Host**:

- Domain: `api.yourdomain.com`
- Scheme: `http`, Forward host: `192.168.1.50` (container IP), Port: `8765`
- SSL tab: request a Let's Encrypt cert, Force SSL on.
- Advanced (recommended — long LLM calls): raise timeouts so a 30–60s
  extraction doesn't 504:
  ```
  proxy_read_timeout 120s;
  proxy_send_timeout 120s;
  ```

CORS is handled by the service itself (`Access-Control-Allow-Origin: *`), so no
NPM CORS config is needed.

## 6. DNS

Point `api.yourdomain.com` at whatever reaches NPM (your home public IP with
443 forwarded to NPM, or a Cloudflare Tunnel to NPM). Then:

```bash
curl -s https://api.yourdomain.com/health   # {"status": "ok"} from outside
```

## 7. Wire the app

Build the web app against this endpoint and deploy to Cloudflare Pages:

```bash
cd app
flutter build web --release \
  --dart-define=INGEST_URL=https://api.yourdomain.com/ingest
npx wrangler pages deploy build/web --project-name bestcard --commit-dirty=true
```

## Smoke test (do before the demo, phone on cellular)

```bash
curl -s -X POST https://api.yourdomain.com/ingest \
  -H 'Content-Type: application/json' \
  -d '{"card":"Emirates NBD Titanium"}' | head -c 300
```

Then open the Pages URL on the phone → Wallet → Add a card → type a card name →
it should appear within ~a minute.
