# Incident Report — ToroKard Ingestion API Out‑of‑Memory (502 outage)

| Field | Value |
|---|---|
| **Date of incident** | 2026‑07‑20 |
| **Detected** | 2026‑07‑20, ~12:21 UTC (user reported "add card" failing) |
| **Severity** | High — the "Add a card" feature was fully unavailable |
| **Affected service** | `bestcard-ingest` (card ingestion + merchant‑offer search API) |
| **Host** | Proxmox VE node `pve`, LXC container **104** (`bestcard-api`), Debian |
| **Public URL** | `https://bestcard-api.baadal.win` (behind Cloudflare + Nginx Proxy Manager) |
| **Status** | Root cause identified; remediation in progress |
| **Author** | Engineering |

---

## 1. Executive summary (non‑technical)

The part of our backend that reads a credit card's rewards from the web (the "ingestion API") stopped responding. Users trying to add a card saw an error; the public endpoint returned **HTTP 502 (Bad Gateway)**.

The server itself had not crashed in the usual sense. Instead, a single program on a small server slowly consumed **all available memory** over roughly two days of normal use, until the machine had nothing left to give. At that point the program could no longer respond, and Cloudflare (our front door) reported the server as unreachable.

There was **no traffic spike and no attack**. The cause is an efficiency problem in how our long‑running server holds on to memory after doing heavy work (downloading and parsing large web pages and PDF documents). The fix is a combination of a small code change, a configuration change to the server process, and giving the container a bit more memory headroom — none of which change the product's behaviour.

**Customer impact:** the "Add a card" and "merchant offer" features were unavailable until the service was restarted. No data was lost. No personal data was exposed (the app stores card data on the user's device; the server only holds a public catalog).

---

## 2. Impact

- **Feature down:** adding a card and merchant‑offer lookups failed (both are served by this API).
- **User‑visible:** the mobile app showed its friendly error ("something went wrong"); the raw cause was `HTTP 502` from the edge.
- **Duration:** the memory had been climbing for ~2 days; hard failure surfaced when a request finally could not be served. Full recovery is a service restart (seconds).
- **Data:** none lost. The catalog is rebuildable from source and cached in SQLite; user card data lives only on‑device.
- **Blast radius:** limited to container 104. Other containers on the node (Vaultwarden, Nextcloud, Pi‑hole, etc.) were unaffected.

---

## 3. System architecture (what the code is)

The ingestion API is a small Python service. Relevant facts:

- **Entry point:** `python3 -m ingestion.server`, working directory `/opt/dapp`, managed by systemd unit `bestcard-ingest.service`.
- **Web server:** Python standard‑library `ThreadingHTTPServer` — **it spawns a new OS thread for every incoming request**.

  ```python
  # ingestion/server.py
  from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

  def main() -> None:
      # Threaded so concurrent card-adds don't serialize behind a slow LLM call.
      server = ThreadingHTTPServer((HOST, PORT), Handler)
      server.serve_forever()
  ```

- **What a request does (the heavy part):** on `POST /ingest`, if the card is not already cached in SQLite, the server goes to the web:
  1. Runs several search queries and downloads multiple candidate pages.
  2. Downloads and parses **PDF** documents (bank "MITC"/schedule‑of‑charges files) with `pdfplumber`, and HTML with a text extractor.
  3. Sends large blocks of extracted text to the LLM (DeepSeek) for structured extraction.

  ```python
  # ingestion/discover.py  (illustrative)
  with pdfplumber.open(io.BytesIO(resp.content)) as pdf:   # whole PDF in memory
      ...
  text = html_to_text(resp.text)                            # whole HTML in memory
  ```

- **Co‑tenants in the same 1 GiB container:** SearXNG (self‑hosted search) + Valkey (its cache) running under Docker, plus the Docker daemon.

Each of steps 1–3 allocates **large, short‑lived buffers** (page HTML, PDF bytes, extracted text). They are logically freed at the end of the request — but, as explained in §6, the memory was not being returned to the operating system.

---

## 4. Symptoms observed

1. **Public API returned 502** via Cloudflare:

   ```
   HTTP/2 502
   server: cloudflare
   cf-ray: a1e1ec5c2ec4beb8-NRT
   error code: 502
   ```

   A `502` from Cloudflare means Cloudflare is healthy but **could not get a response from our origin server**. This ruled out a DNS/edge problem and pointed at the origin.

2. **Proxmox container 104 dashboard** (at the time of the incident):

   | Metric | Reading |
   |---|---|
   | Status | running (uptime 2d 08h) |
   | **CPU** | **97 % of 1 core** |
   | **Memory** | **99.46 % (1018 / 1024 MiB)** |
   | **Swap** | **99.95 % (511 / 512 MiB)** |

   The container was **not down** — it was **resource‑exhausted**: RAM and swap both essentially full, CPU pinned.

---

## 5. Investigation — every command, what it means, why we ran it

The investigation followed a top‑down path: **edge → origin health → container resources → per‑process memory → source code**. Each step narrowed the fault to the next layer.

### 5.1 Confirm the failure and where it originates

```bash
curl -sS -i -X POST https://bestcard-api.baadal.win/ingest \
  -H 'Content-Type: application/json' \
  -d '{"card":"Mashreq Cashback Credit Card","country":"AE"}'
```

- **What it does:** sends a real ingest request to the public endpoint and prints the full HTTP response **including headers** (`-i`), failing loudly on errors (`-sS`).
- **Why:** to reproduce the user's failure independently and read the exact status code + which layer answered.
- **Result:** `HTTP/2 502`, `server: cloudflare`. → **Cloudflare is up; our origin is not answering.** Move to the origin.

### 5.2 Inspect the container's resources (Proxmox UI)

- **What:** the Proxmox summary graphs for CT 104 (CPU, Memory, Swap).
- **Why:** a 502 with a *running* container usually means the origin is overloaded or a process died. The graphs immediately showed **RAM 99.46 %, Swap 99.95 %, CPU 97 %.**
- **Meaning:** the container is out of memory and thrashing swap (constantly moving pages between RAM and disk), which also explains the pinned CPU. A process under this pressure cannot respond in time → 502 upstream.

### 5.3 Confirm memory exhaustion from the host CLI

The container's own web console was unresponsive (too starved to open a shell), so we drove it from the Proxmox **host** using `pct`, the LXC management tool.

```bash
pct exec 104 -- free -h
```

- **`pct exec 104 -- <cmd>`:** run `<cmd>` *inside* container 104 from the host, without needing a shell in the container.
- **`free -h`:** show memory usage in human‑readable units.
- **Output:**

  ```
                 total        used        free      shared  buff/cache   available
  Mem:           1.0Gi       1.0Gi       4.1Mi        76Ki       3.5Mi       7.4Mi
  Swap:          512Mi       511Mi       220Ki
  ```

- **Meaning:** **7.4 MiB "available"** — effectively nothing. RAM full, swap full. Critically, this was true **with no traffic**, which means something was *holding* the memory at rest, not just using it during a burst. That reframed the problem from "overload" to "a process is retaining memory."

### 5.4 Find which process holds the memory

```bash
pct exec 104 -- bash -c 'ps -eo pid,ppid,rss,comm --sort=-rss | head -15'
```

- **`ps -eo pid,ppid,rss,comm`:** list every process showing PID, parent PID, **RSS** (Resident Set Size = actual physical RAM used, in KB), and command name.
- **`--sort=-rss`:** sort by memory, largest first. `head -15`: top 15.
- **Why:** pinpoint the single biggest memory consumer.
- **Output (top rows):**

  ```
      PID    PPID   RSS COMMAND
    12544       1 905348 python3          <-- ~884 MB
    12356   11479  49272 searxng worker-  <-- ~48 MB
    10954       1  22780 dockerd          <-- ~22 MB
    11389   11365   2436 valkey-server    <-- ~2 MB
  ```

- **Meaning — this is the key finding.** Our own `python3` process (`ingestion.server`) was holding **~884 MB** of RAM. SearXNG, Valkey and Docker were all small and healthy. **The leak/retention is in our application, not the infrastructure.** This eliminated the common suspects (an unbounded Valkey cache, too many SearXNG workers).

### 5.5 Confirm it is our server and how it is launched

```bash
pct exec 104 -- bash -c 'tr "\0" " " < /proc/12544/cmdline; echo; readlink /proc/12544/cwd'
```

- **`/proc/<pid>/cmdline`:** the exact command line the process was started with (arguments are NUL‑separated, so `tr "\0" " "` makes it readable).
- **`readlink /proc/<pid>/cwd`:** the process's working directory.
- **Output:** `/usr/bin/python3 -m ingestion.server`, cwd `/opt/dapp`, parent PID `1`.
- **Meaning:** confirmed the 884 MB process **is** our ingestion server; parent PID 1 indicates it is managed by systemd.

```bash
pct exec 104 -- bash -c 'grep -rl "ingestion.server" /etc/systemd/system/ 2>/dev/null'
```

- **What:** find which systemd unit file starts our server.
- **Result:** `/etc/systemd/system/bestcard-ingest.service` → the unit is **`bestcard-ingest.service`**, so recovery is a clean `systemctl restart`.

### 5.6 Rule out a data‑structure leak in code (read the source)

We inspected the server for anything that grows without bound across requests:

- The in‑memory search cache `_search_cache` stores only small payloads (merchant, category, offers list, source_ref) — **not** raw page text:

  ```python
  # ingestion/merchant.py
  def result_to_dict(r: MerchantResult) -> dict:
      return {
          "merchant": r.merchant,
          "category": r.category,
          "offers": [asdict(o) for o in r.offers],
          "source_ref": r.source_ref,
      }
  ```

- The LLM client is **stateless** — a fresh client and a plain `requests.post` per call, no accumulated history:

  ```python
  # ingestion/llm/deepseek.py
  def complete(self, system: str, user: str) -> str:
      resp = requests.post(self.base_url, headers=..., json={...}, timeout=self.timeout)
      resp.raise_for_status()
      return resp.json()["choices"][0]["message"]["content"]
  ```

- Thread pools used during a request are **scoped** (`with ThreadPoolExecutor(...) as pool:`) and cleaned up when the request finishes.

**Conclusion:** there is no runaway list/dict or accumulating cache. The memory is consumed by **large transient buffers per request that are not returned to the OS** — see root cause below.

---

## 6. Root cause

**The long‑running, thread‑per‑request Python server does not return freed memory to the operating system, so its RSS ratchets up to the high‑water mark of the heaviest work it has ever done and stays there.**

Two mechanisms combine:

1. **`ThreadingHTTPServer` = one thread per request, and glibc gives each thread its own memory "arena."**
   The C memory allocator underneath Python (glibc `malloc`) creates a separate memory pool (arena) per thread, up to a default of `8 × number_of_CPUs`. When a request thread allocates large buffers (a multi‑MB PDF, a big HTML page, a large LLM prompt) and then frees them, that memory is **kept in the thread's arena for reuse**, not handed back to the kernel. With many arenas each holding onto large freed blocks, the process's resident memory multiplies far beyond what is actually live.

2. **CPython heap fragmentation for large, short‑lived objects.**
   Parsing PDFs/HTML and building large strings creates many big allocations of varying sizes. Even after they are freed, fragmentation prevents whole memory pages from being released, so RSS does not drop back.

**The result:** every heavy card‑add nudges RSS up toward a new peak; it never comes back down. Over ~2 days of normal use the process reached ~884 MB and, together with SearXNG/Valkey/Docker (~75 MB) and the OS, exhausted the container's 1 GiB RAM **and** its 512 MiB swap. Once swap is full, the kernel spends CPU thrashing (hence 97 % CPU with no traffic) and the server can no longer allocate memory to serve a request → it stops responding → Cloudflare returns 502.

### Why CPU also spiked

The CPU pinning at 97 % is a **symptom, not a cause**. When RAM and swap are both full, the Linux kernel constantly pages memory in and out of disk and runs memory‑reclaim routines; that overhead saturates the single CPU even though the application is doing no useful work.

### Why it looked fine "yesterday"

Memory grew gradually. Yesterday the process was below the cliff; by today the accumulated high‑water mark crossed the container's total memory, so the next allocation failed. This is the classic signature of a **slow retention problem**, not a sudden bug.

---

## 7. Contributing factors

- **Undersized container:** 1 GiB RAM + 512 MiB swap is tight for a workload that parses large PDFs/HTML and co‑hosts SearXNG + Valkey + Docker.
- **No per‑service memory limit:** nothing capped the Python process, so it grew until it took down the whole container instead of just restarting itself.
- **No memory monitoring/alerting** on the container, so the slow climb went unnoticed until hard failure.
- **Default allocator settings** (`MALLOC_ARENA_MAX` unset) are the worst case for a threaded server on a small box.

---

## 8. Remediation plan

Layered so that even if one layer is imperfect, the service cannot take down the container again.

### 8.1 Immediate (recovery)

```bash
# Give the container headroom (applied live; no reboot needed for LXC memory).
pct set 104 -memory 2048 -swap 1024

# Restart the service to release the 884 MB.
pct exec 104 -- systemctl restart bestcard-ingest

# Verify.
pct exec 104 -- free -h
curl -sS -i https://bestcard-api.baadal.win/health
```

### 8.2 Code — return memory to the OS after every request

The highest‑leverage, lowest‑risk change. After each request finishes, force Python garbage collection and ask glibc to trim freed arenas back to the kernel, so RSS returns to baseline instead of ratcheting up.

```python
# ingestion/server.py
import ctypes, ctypes.util, gc

# Bind glibc malloc_trim(0): returns free heap memory to the OS.
try:
    _libc = ctypes.CDLL(ctypes.util.find_library("c"))
    _malloc_trim = _libc.malloc_trim
except (OSError, AttributeError):
    _malloc_trim = None

def _release_memory() -> None:
    gc.collect()
    if _malloc_trim:
        _malloc_trim(0)

class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        try:
            ...  # existing handling
        finally:
            _release_memory()   # drop RSS back to baseline after heavy work
```

Optional defensive cap on the in‑memory search cache (evict oldest when large), so it can never grow unbounded even though today its entries are small.

### 8.3 Process — cap arenas and hard‑limit the service (systemd)

The shipped unit `ingestion/deploy/bestcard-ingest.service` now (a) caps glibc
arenas — the main fix for the thread‑per‑request bloat, (b) trims aggressively,
(c) sets a soft/hard memory ceiling on **the service only**, and (d) auto‑restarts.

```ini
# ingestion/deploy/bestcard-ingest.service  [Service] section
Environment=MALLOC_ARENA_MAX=2
Environment=MALLOC_TRIM_THRESHOLD_=131072
MemoryHigh=600M
MemoryMax=768M
Restart=always
RestartSec=3
```

Apply on the server:

```bash
cp /opt/dapp/ingestion/deploy/bestcard-ingest.service /etc/systemd/system/
pct exec 104 -- systemctl daemon-reload
pct exec 104 -- systemctl restart bestcard-ingest
pct exec 104 -- systemctl show bestcard-ingest -p MemoryMax,MemoryHigh,Restart
```

> **Note on `MALLOC_ARENA_MAX=2`:** this alone typically cuts a threaded‑Python server's resident memory by a large factor, because it prevents glibc from creating a separate (memory‑hoarding) arena per request thread.

### 8.4 Reduce peak memory per request (defence in depth)

- Skip/stream PDFs above a size threshold instead of loading the whole file into memory.
- Truncate extracted HTML/PDF text before sending to the LLM (a cap on prompt length).
- Bound the number of candidate pages fetched per card.

### 8.5 Contain the co‑tenants

```yaml
# deploy/searxng/docker-compose.yml  (add limits)
services:
  valkey:
    command: ["valkey-server", "--save", "", "--maxmemory", "128mb",
              "--maxmemory-policy", "allkeys-lru"]
    mem_limit: 192m
  searxng:
    mem_limit: 256m
```

### 8.6 Monitoring & alerting

- Alert when CT 104 memory > 80 % for 10 min (early warning of the climb).
- Alert on `bestcard-ingest` restarts (so recovery is visible, not silent).
- Optional: log RSS per request in the server to trend the footprint.

---

## 9. Verification

After applying §8.2–§8.3:

1. `systemctl show bestcard-ingest -p MemoryMax` reports `768M`.
2. Drive several `/ingest` requests, then check `free -h` / process RSS returns to baseline (a few tens of MB), not hundreds.
3. Force the cap: confirm that if RSS exceeds `MemoryMax`, systemd restarts **only** the service and the container stays up (`journalctl -u bestcard-ingest`).
4. Endpoint healthy: `curl -i https://bestcard-api.baadal.win/health` → `200`.

---

## 10. Lessons learned

- **Long‑running threaded Python on a small box needs `MALLOC_ARENA_MAX` set and periodic `malloc_trim`.** This should be our default for any such service.
- **Every service needs a memory ceiling** (`MemoryMax`) so a single process can never take down its host.
- **Gradual resource climbs need monitoring**, not just crash alerts — the failure mode here was slow and predictable.
- **Small containers must account for co‑tenants** (SearXNG + Valkey + Docker) when sizing.

---

## 11. Action items

| # | Action | Owner | Priority |
|---|---|---|---|
| 1 | Restart service + raise CT 104 to 2 GiB RAM / 1 GiB swap | Eng | Immediate (recovery) |
| 2 | Add `malloc_trim`/`gc.collect()` after each request (§8.2) | Eng | High |
| 3 | systemd drop‑in: `MALLOC_ARENA_MAX`, `MemoryMax`, `Restart=always` (§8.3) | Eng | High |
| 4 | Cap PDF/HTML/LLM input sizes (§8.4) | Eng | Medium |
| 5 | Docker mem limits + Valkey `maxmemory` (§8.5) | Eng | Medium |
| 6 | Memory/restart alerting for CT 104 (§8.6) | Eng | Medium |

---

## Appendix A — Glossary

- **RSS (Resident Set Size):** the amount of physical RAM a process is actually using. The number we care about for memory pressure.
- **Swap:** disk space used as overflow when RAM is full. Fast to fill, slow to use; when full, the system thrashes.
- **OOM (Out Of Memory):** the state where no memory can be allocated; the kernel starts killing processes or everything stalls.
- **Arena (glibc):** a memory pool the C allocator maintains, one or more per thread; freed memory can be retained here instead of returned to the OS.
- **`malloc_trim`:** a glibc call that returns retained free memory from arenas back to the operating system.
- **502 Bad Gateway:** the reverse proxy/CDN (Cloudflare) reached but got no valid response from the origin server.
- **LXC / `pct`:** Linux Containers on Proxmox; `pct` is the host‑side command to manage and run commands inside them.

## Appendix B — Command quick reference

| Command | Purpose |
|---|---|
| `curl -sS -i <url>` | Reproduce the request; read status + headers |
| `pct exec 104 -- free -h` | Memory/swap usage inside the container |
| `pct exec 104 -- ps -eo pid,ppid,rss,comm --sort=-rss \| head` | Rank processes by RAM |
| `cat /proc/<pid>/cmdline` / `readlink /proc/<pid>/cwd` | Identify a process's command + working dir |
| `grep -rl "ingestion.server" /etc/systemd/system/` | Find the managing systemd unit |
| `pct set 104 -memory 2048 -swap 1024` | Resize container memory (live) |
| `systemctl restart bestcard-ingest` | Recover the service |
| `systemctl show <unit> -p MemoryMax,Restart` | Verify limits/restart policy |
