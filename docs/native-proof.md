# Native (no-Docker) proof of the open-notebook stack

This document records the evidence that the whole stack this package installs
runs **natively, without Docker**, and that the YunoHost integration layer
(reverse proxy, patches, environment, data layout) behaves as designed.

It complements [`RUNBOOK.md`](RUNBOOK.md), which is the procedure to run *on the
YunoHost test instance*: here the commands were actually executed and the
observed output is recorded.

## Environment

| Tool | Version |
| --- | --- |
| Machine | macOS, arm64 (darwin) |
| SurrealDB | 2.7.0 (darwin-arm64 build of the same release the manifest pins for Linux) |
| Python | 3.12.13, installed by `uv` (equals `PYTHON_VERSION` in `scripts/_common.sh`) |
| uv | 0.11.21 |
| Node.js | 24 (the package requests Node 22 through the YunoHost `nodejs` resource) |
| npm | 11.6.2 |
| Next.js | 16.3.8 (from upstream `frontend/package.json`) |
| nginx | 1.31.7 |

Upstream source: `lfnovo/open-notebook` at tag `v1.15.0` — the tarball the
manifest pins (sha256 `544bcd…9920`, checksum re-verified).

## 1. Database — SurrealDB

Mirrors `conf/systemd-surreal.service`:

```bash
surreal start --log info --user root --pass localtestpass \
    --bind 127.0.0.1:18430 rocksdb:/tmp/onb_local/surreal_data
```

Observed: `GET /health` → `200`, and the API later applied all migrations to it.

## 2. Backend build — `open_notebook_build_backend`

```bash
uv python install 3.12
uv sync --frozen --no-dev --python 3.12
```

Observed: success. `uv.lock` exists, so `--frozen` is valid;
`requires-python = ">=3.11,<3.13"`, so Python 3.12 is the correct interpreter.
`.venv/bin/` contains `python`, `uvicorn`, `content-core` **and
`surreal-commands-worker`** — i.e. the exact `ExecStart` targets of the `-api`
and `-worker` units.

## 3. Patches — sub-path support (ADR-008)

```bash
patch --strip=1 < patches/main/frontend_next.config.ts.patch
patch --strip=1 < patches/main/frontend_src_lib_api_client.ts.patch
patch --strip=1 < patches/main/frontend_src_lib_config.ts.patch
```

Observed: all three apply cleanly (no fuzz, no rejects). This is exactly what
`ynh_setup_source` does automatically during install/upgrade/restore. The
patched files compiled in the real frontend build below.

## 4. API — `conf/systemd-api.service`

```bash
.venv/bin/python run_api.py      # API_HOST=127.0.0.1 API_PORT=15055 API_RELOAD=false
```

Observed log: `CORS ['http://127.0.0.1:13000']`, `Max request body size: 100MB`,
`commands` imported, migrations 1…25 applied, `Database is now at version 25`,
uvicorn listening on `127.0.0.1:15055`.

Endpoints: `/` 200, `/health` 200, `/docs` 200, `/api/health` **401**
(`Missing authorization header`), `/api/models` 401, and — with
`Authorization: Bearer <shared password>` — `/api/config` 200 returning
`{"version":"1.15.0","latestVersion":null,"hasUpdate":false,"dbStatus":"online"}`.

## 5. Worker — `conf/systemd-worker.service`

```bash
.venv/bin/surreal-commands-worker --import-modules commands --max-tasks 1
```

Observed: `Imported: commands`, `Successfully imported 1/1 modules`,
`Using 8 registered commands`, `Worker configured to handle up to 1 concurrent
tasks`, `Using custom chunk size: 400 tokens`, `Using custom chunk overlap: 60
tokens`, `Starting LIVE query listener for new commands...`

That exercises the database connection, the module import and the
`OPEN_NOTEBOOK_*` environment `conf/.env` provides.

## 6. Frontend — `conf/systemd-frontend.service`

```bash
npm ci
NEXT_BASE_PATH="" NEXT_PUBLIC_BASE_PATH="" \
INTERNAL_API_URL="http://127.0.0.1:15055" NODE_ENV=production npm run build
# then the standalone asset copy open_notebook_build_frontend performs:
#   cp -a .next/static  .next/standalone/.next/static
#   cp -a public        .next/standalone/public
PORT=13000 HOSTNAME=127.0.0.1 API_URL="http://127.0.0.1:13000" \
INTERNAL_API_URL="http://127.0.0.1:15055" NODE_ENV=production node start-server.js
```

Observed: `Compiled successfully in 7.8s`, TypeScript OK, 15 pages, and the log
line `[Next.js Rewrites] Proxying /api/* to http://127.0.0.1:15055/api/*`.
HTTP: `/` 307 → `/login`, `/login` 200, `/config` 200
(`{"apiUrl":"http://127.0.0.1:13000"}`), `/notebooks` 200, `/settings` 200, and
`/api/config` proxied to the API with the real JSON body.

Building with a sub-path (`NEXT_BASE_PATH=/open-notebook`) also succeeds, and
`.next/standalone/.next/routes-manifest.json` then contains
`"basePath": "/open-notebook"` — proof that the `next.config.ts` patch works.

## 7. Reverse proxy — `conf/nginx.conf`, end to end

nginx was started locally with the **real** YunoHost
`/etc/nginx/proxy_params_with_auth` include and the real
`map $http_upgrade $connection_upgrade` from YunoHost's `server.tpl.conf`,
using a sub-path rendering (`__PATH__` = `/open-notebook`) in front of the
frontend (13001) and the API (15055):

| Request through nginx (`:8080`) | Result |
| --- | --- |
| `/open-notebook` | 301 → `/open-notebook/` (the `#sub_path_only` redirect) |
| `/open-notebook/` | 308 |
| `/open-notebook/login` | 200 |
| `/open-notebook/config` | 200, `{"apiUrl":"http://127.0.0.1:13001/open-notebook"}` |
| `/open-notebook/notebooks`, `/settings` | 200 |
| `/open-notebook/api/config` + `Authorization: Bearer …` | 200, real API JSON |
| `POST` with a 2 MB body | 405 (body accepted — **not** 413) |
| `POST` with a 110 MB body | 413 `client intended to send too large body` |

That validates sub-path routing, the `/api/` `proxy_pass` path rewrite,
forwarding of the client `Authorization` header, and `client_max_body_size`
(nginx's default is 1 MB, so the accepted 2 MB request proves our directive is
in effect — and the 110 MB request proves the limit is enforced).

`nginx -t` also passes for a **root** install rendering (`__PATH__` = `/`), for
which the `#sub_path_only` line correctly stays a comment.

## Verified end-to-end on a real YunoHost 12 instance

A complete YunoHost 12 server was installed from scratch (official installer,
non-interactive `-f -a`) on Debian 12 *bookworm*, **arm64**, followed by
`yunohost tools postinstall -d ynh.local …`. Versions: YunoHost `12.1.41.2`,
yunohost-admin `12.1.15`, ssowat `12.1.1`, moulinette `12.1.4`.

The package was then installed straight from the local directory:

```bash
yunohost app install /root/open-notebook_ynh -f -n \
  -a "domain=ynh.local&path=/open-notebook&init_main_permission=all_users"
```

→ **exit 0, "Installation of open-notebook completed"**. The package never
invokes Docker.

### Services

| unit | `is-active` | `is-enabled` | `yunohost service status` |
|---|---|---|---|
| `open-notebook-surreal` | active | enabled | running |
| `open-notebook-api` | active | enabled | running |
| `open-notebook-worker` | active | enabled | running |
| `open-notebook` (frontend) | active | enabled | running |

All four are enabled, so they come back after a reboot. Logs land in
`/var/log/open-notebook/{surreal,api,worker,frontend}.log`, and
`/etc/logrotate.d/open-notebook` rotates them.

### Backend reachability (bound to `127.0.0.1`)

- SurrealDB: `GET /health` → `200`.
- API: `GET /api/config` with `Authorization: Bearer <app password>` → `200`
  `{"version":"1.15.0","dbStatus":"online"}`; missing or wrong bearer → `401`.
  Migrations ran on first boot (*"Database is now at version 25"*).
- `.env` and the four units render only from the app settings (data dir,
  ports, keys, password) — see `conf/.env`.

### Web access through nginx (SSO first, then the app password)

`https://ynh.local/open-notebook` is gated by YunoHost's SSO: without a
session it returns `302` to `/yunohost/sso?…`
(`x-sso-wat: You've just been SSOed`), **even when a valid `Authorization:
Bearer` app password is supplied** — the two-layer model of ADR-004. With a
valid SSO session:

| URL | status |
|---|---|
| `/open-notebook` | `200` |
| `/open-notebook/` | `308` → `/open-notebook` → `200` (single hop) |
| `/open-notebook/login` | `200` |
| `/open-notebook/config` | `200` |
| `/open-notebook/notebooks` | `200` |
| `/open-notebook/api/notebooks` + Bearer | `200` |
| `/open-notebook/api/notebooks` no/bad Bearer | `401` |

The `location /open-notebook` block has no trailing slash on `proxy_pass`, so
the Next.js `basePath` is preserved (ADR-008). The location itself also carries
no trailing slash: the frontend answers `/open-notebook` directly and only
redirects the trailing-slash form once (see bug 9 below).

### Streaming (SSE) and large uploads

- A temporary SSE emitter was pointed at the API port **without touching the
  nginx config**; five events 0.7 s apart were delivered through
  `https://ynh.local/open-notebook/api/…` with matching arrival times
  (`…663.034 → …665.855`), i.e. the responses are **not buffered**
  (`proxy_buffering off`). open-notebook's own SSE endpoints are
  `POST /api/search/ask` and `/api/source_chat/…`
  (`media_type="text/event-stream"`, `X-Accel-Buffering: no`).
- A 10 MB `POST` through nginx returned the app's `404`, not nginx's `413`,
  confirming `client_max_body_size` tracks `max_upload_size`.

### Config panel

`yunohost app config set` changes take effect live: the setting is persisted,
`.env` is re-rendered, nginx's `client_max_body_size` and the worker unit's
`--max-tasks` value follow, and the services restart. See bug 7 below.

### Backup

`yunohost backup create --apps open-notebook -n onb-test` → `SUCCESS`, a
~3.8 MB archive holding the consistent RocksDB snapshot (`surreal_data/`:
`*.sst`, `*.log`, `CURRENT`, `IDENTITY`), the whole data directory
(`uploads/`, `podcasts/`, `sqlite-db/checkpoints.sqlite`, `tiktoken-cache/`),
the nginx conf, the four unit files and `/etc/logrotate.d/open-notebook`.

### Restore and data integrity round trip

A sentinel notebook was created through the API before the backup, and a second
one after it. `yunohost app remove open-notebook --purge` wiped the instance,
then `yunohost backup restore onb-test --apps open-notebook --force` brought it
back (*"Restoration completed"*). Afterwards the API listed **only the
sentinel** notebook — the post-backup one was gone — proving a true round trip
of the SurrealDB data. All settings were preserved (domain, path, and the
config-panel values `max_upload_size=200`, `worker_max_tasks=5`,
`chunk_size=512`).

### Remove / purge

`yunohost app remove open-notebook --purge` → `SUCCESS open-notebook
uninstalled`, with no leftovers (`/home/yunohost.app/open-notebook`,
`/var/www/open-notebook` and all four units gone).

## Bugs this proof found and fixed

1. **Fatal nginx duplicate directive.** YunoHost's `proxy_params_with_auth`
   already sets `proxy_http_version 1.1`; repeating it in our `location` blocks
   makes nginx refuse the entire configuration
   (`"proxy_http_version" directive is duplicate`), which would have broken
   every install. Removed from both blocks (commit `d83d444`). The earlier
   `nginx -t` run had passed only because that include was stubbed.
2. **Root installs store `/` as the path.** That value was baked into the
   Next.js `basePath` (invalid) and produced `//login` client URLs;
   `open_notebook_build_frontend` now normalises `/` to `""` (commit `eec8792`).
3. **Missing runtime caches.** `PLAYWRIGHT_BROWSERS_PATH` and `HF_HOME` were
   absent from `conf/.env`, so the Crawl4AI readiness probe could never find a
   Chromium build and Docling models would not persist. Both now live under
   `$data_dir`, and enabling Crawl4AI also installs Chromium's system libraries
   as root (commit `beec790`).
4. **Backup/restore edge cases.** `scripts/backup` read a variable the core
   never sets (`do_not_backup_data` is a *setting*), and `scripts/restore`
   hard-failed when restoring a pre-upgrade safety backup that contains no
   database snapshot (commit `5816827`).
5. **Wrong `ynh_setup_source` flag.** The real helpers 2.1 name the argument
   `--source_id=`, not `--source=`; the install aborted at the SurrealDB step
   (commit `eeabff3`).
6. **Settings are not exported to the script shell.** `ynh_app_setting_set`
   does not create a shell variable, and the core builds the script
   environment *before* the script runs, so values written by `scripts/install`
   were missing when templating `conf/.env`
   (*"Variable $chunk_overlap wasn't initialized …"*). `open_notebook_load_settings`
   now reads them back before rendering (commit `802935b`).
7. **Config-panel setters did not persist, and units were not re-rendered.**
   When a `set__<key>` function exists, the helper calls *only* that function,
   so each setter must save the setting itself; and
   `open_notebook_apply_config` only re-rendered `.env`/nginx, leaving the
   worker's `--max-tasks` (baked into its unit) stale. Both fixed
   (commit `39ea34e`).
8. **A restored data directory was left untraversable.** `ynh_restore` applies
   YunoHost's "default permissions" to its target, and anything that is neither
   `$install_dir` nor `$data_dir` *itself* is forced to mode `400`. The restored
   `$data_dir/data` directory therefore came back as `dr--------`, so the app
   user could not descend into it and the API crash-looped on
   `PermissionError: [Errno 13] './data/sqlite-db'` (the tiktoken prewarm failed
   the same way). `scripts/restore` now normalises the permissions of the
   restored data directory immediately afterwards.
9. **Infinite redirect loop on the application root.** `conf/nginx.conf` used
   the usual `#sub_path_only rewrite ^__PATH__$ __PATH__/ permanent;` line,
   which for a sub-path install appends a trailing slash (`/open-notebook/`).
   The Next.js frontend is built with `trailingSlash: false`, so it answers
   `308` back to `/open-notebook` — the two ping-ponged forever on the app root
   (exactly the URL the YunoHost user portal tile links to). The rewrite was
   removed and the frontend location matches `__PATH__` *without* a trailing
   slash, so `/open-notebook` is served directly (`200`) and `/open-notebook/`
   resolves in a single `308` hop. Re-verified through the real render pipeline
   for both a sub-path (`location /open-notebook`) and a root install
   (`location /` + `location /api/`, both accepted by `nginx -t`).
