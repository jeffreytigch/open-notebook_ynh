# Native runbook (no Docker)

This runbook reproduces, **by hand**, exactly what the package does, so the
whole stack can be validated on a test YunoHost instance before/while the
packaging scripts are trusted. It is the concrete output of **Phase 1
(runtime proof)** in [`PLAN.md`](PLAN.md).

Values used here are examples. Replace them with the ones from your test
instance. The package stores its ports as `$port` (frontend), `$port_api` and
`$port_surreal`.

| Variable | Example |
|---|---|
| `APP_DIR` (install dir) | `/var/www/open-notebook` |
| `DATA_DIR` (data dir) | `/home/yunohost.app/open-notebook` |
| `PORT` (frontend) | `8001` |
| `PORT_API` | `8002` |
| `PORT_SURREAL` | `8003` |
| App user | `open-notebook` |

Everything below runs as the app user (or with `sudo -u open-notebook`).

## 0. Prerequisites

```bash
sudo apt-get update
sudo apt-get install -y ffmpeg curl
# Node.js 22 (the package uses the `nodejs` resource; by hand, use nodesource)
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs
```

## 1. Fetch the sources and verify the hashes

```bash
mkdir -p "$APP_DIR" && cd "$APP_DIR"

# open-notebook v1.15.0
curl -fsSL https://github.com/lfnovo/open-notebook/archive/refs/tags/v1.15.0.tar.gz -o on.tgz
echo "544bcd0751f3985cf045c694c31587606c3756923350ca162d089b40aa449920  on.tgz" | sha256sum -c -
tar -xzf on.tgz --strip-components=1
rm on.tgz

# uv 0.13.1 (amd64 shown; aarch64 has a different hash)
curl -fsSL https://github.com/astral-sh/uv/releases/download/0.13.1/uv-x86_64-unknown-linux-gnu.tar.gz -o uv.tgz
echo "eadd9d27c134ab5ac1ffd4473b97a741407f3ea238288f03121fc4deddf90220  uv.tgz" | sha256sum -c -
tar -xzf uv.tgz --strip-components=1 uv-x86_64-unknown-linux-gnu/uv uv-x86_64-unknown-linux-gnu/uvx
rm uv.tgz

# SurrealDB v2.7.0 — MUST be v2.x, NOT v3.x
curl -fsSL https://github.com/surrealdb/surrealdb/releases/download/v2.7.0/surreal-v2.7.0.linux-amd64.tgz -o surreal.tgz
echo "c5f53be46e287d15302d3467c629ad8df016c96fcf15451077633949dadb2028  surreal.tgz" | sha256sum -c -
tar -xzf surreal.tgz surreal
rm surreal.tgz
chmod +x uv uvx surreal
```

## 2. Apply the sub-path patch (only needed for a sub-path install)

```bash
cd "$APP_DIR"
for p in patches/main/*.patch; do patch -p1 --dry-run < "$p"; done
for p in patches/main/*.patch; do patch -p1 < "$p"; done
```

For a **root** install (`NEXT_BASE_PATH` empty) the frontend still needs the two
`NEXT_PUBLIC_BASE_PATH` fallbacks, but they evaluate to `''` — harmless.

## 3. Data directory

```bash
mkdir -p "$DATA_DIR"/{surreal_data,data,uv/python,uv/cache}
ln -sfn "$DATA_DIR/data" "$APP_DIR/data"     # the app hardcodes ./data
```

## 4. Environment

Create `$APP_DIR/.env`:

```ini
OPEN_NOTEBOOK_ENCRYPTION_KEY=<64 hex chars>
OPEN_NOTEBOOK_PASSWORD=<shared password>
OPEN_NOTEBOOK_MAX_UPLOAD_SIZE_MB=100
OPEN_NOTEBOOK_WORKER_MAX_TASKS=1
SURREAL_URL=ws://127.0.0.1:8003/rpc
SURREAL_USER=root
SURREAL_PASSWORD=<random>
SURREAL_NAMESPACE=open_notebook
SURREAL_DATABASE=open_notebook
API_HOST=127.0.0.1
API_PORT=8002
API_RELOAD=false
CORS_ORIGINS=https://<domain>
PORT=8001
HOSTNAME=127.0.0.1
API_URL=https://<domain><path>
INTERNAL_API_URL=http://127.0.0.1:8002
TIKTOKEN_CACHE_DIR=<DATA_DIR>/data/tiktoken-cache
```

`SURREAL_URL` **must** use `127.0.0.1`, not `localhost` (the DB is bound to
IPv4; `localhost` may resolve to `::1` first).

## 5. SurrealDB

```bash
export HOME="$APP_DIR" UV_PYTHON_INSTALL_DIR="$DATA_DIR/uv/python" UV_CACHE_DIR="$DATA_DIR/uv/cache"
"$APP_DIR/surreal" start --log info --user root --pass "<random>" \
  --bind 127.0.0.1:8003 "rocksdb:$DATA_DIR/surreal_data" &
```

**Check:** `curl -s http://127.0.0.1:8003/health` returns `{"status":"ok"}`.

## 6. Backend (venv + migrations)

```bash
cd "$APP_DIR"
./uv python install 3.12
./uv sync --frozen --no-dev --python 3.12
# pre-warm the tokenizer used by the chunker
./.venv/bin/python -c "import tiktoken; tiktoken.get_encoding('o200k_base')"
```

## 7. API

```bash
cd "$APP_DIR"
set -a; . ./.env; set +a
./.venv/bin/python run_api.py &
```

**Check:** `curl -s http://127.0.0.1:8002/health` → `{"status":"healthy"}`;
`http://127.0.0.1:8002/docs` shows the OpenAPI UI. Startup runs the migrations.

## 8. Worker

```bash
cd "$APP_DIR"
set -a; . ./.env; set +a
./.venv/bin/surreal-commands-worker --import-modules commands --max-tasks 1 &
```

Without the worker, sources stay **queued** forever.

## 9. Frontend

```bash
export PATH="$(dirname "$(command -v node)"):$PATH"
cd "$APP_DIR/frontend"
npm ci
NEXT_BASE_PATH="<path>" NEXT_PUBLIC_BASE_PATH="<path>" \
  INTERNAL_API_URL="http://127.0.0.1:8002" NODE_ENV=production npm run build
# standalone server needs the static assets next to it
rm -rf .next/standalone/.next/static .next/standalone/public
cp -a .next/static .next/standalone/.next/static
cp -a public .next/standalone/public
PORT=8001 HOSTNAME=127.0.0.1 API_URL="https://<domain><path>" \
  INTERNAL_API_URL="http://127.0.0.1:8002" node start-server.js &
```

**Check:** `curl -s http://127.0.0.1:8001/` returns the app HTML; `GET
/config` (under the base path) returns `{"apiUrl":"https://<domain><path>"}`.

## 10. Things to record (feeds the package defaults)

| # | Observation | Why it matters |
|---|---|---|
| B1 | Does the standalone server serve assets correctly, and does the browser reach the API via `API_URL`? | validates the ADR-005 nginx routing and the ADR-008 patch |
| B2 | Do uploads/podcasts/checkpoints land in `$DATA_DIR/data`? | validates ADR-003 |
| B3 | Is `ffmpeg` found for audio/video sources and podcasts? | validates the apt dependency |
| B4 | Confirm the newest SurrealDB **v2.x** and re-record the per-arch sha256. | keeps the pin current |
| B5 | How large does `$DATA_DIR` get, and how long does a backup take? | validates the backup strategy |
| C6 | Do all four services register cleanly with `yunohost service add`? | validates ADR-001 |

## Teardown

```bash
pkill -f surreal-commands-worker
pkill -f run_api.py
pkill -f 'next' ; pkill -f start-server.js
pkill -f 'surreal start'
```
