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

### Reboot survival

The box was restarted (`docker restart`). `systemctl is-system-running` went
`initializing` → `running`, and all four units came back `active` + `enabled`.
SurrealDB `/health` → `200` and the API `/api/config` (with bearer) → `200`
without any manual step, and the public matrix below re-run unchanged. (On this
test box the domain is `ynh.local`, which YunoHost deliberately does not resolve
through dnsmasq — `.local` is meant for mDNS. The harness re-adds
`127.0.0.1 ynh.local` to `/etc/hosts`, which YunoHost rewrites on boot; that is
a quirk of the throwaway `.local` test domain, not of the package.)

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

### Log rotation

`/etc/logrotate.d/open-notebook` (rendered by `ynh_config_add_logrotate`) uses
`size 100M`, `rotate 12`, `compress`, `copytruncate`, `missingok` and
`notifempty` for `/var/log/open-notebook/*.log`. `copytruncate` matters because
the units log with `StandardOutput=append:`, which keeps the file descriptor
open. A forced `logrotate -f /etc/logrotate.d/open-notebook` rotated all four
logs into `*.log.1` and truncated the live files; the API kept serving and
kept writing to `api.log` afterwards.

### fail2ban

open-notebook writes no authentication-failure line of its own (the API's
`PasswordAuthMiddleware` only answers `401`), so the jail watches nginx's
per-domain access log, which records that `401`:

    /var/log/nginx/ynh.local-access.log

`open_notebook_configure` renders two templates — `conf/f2b_jail.conf` into
`/etc/fail2ban/jail.d/open-notebook.conf` and `conf/f2b_filter.conf` into
`/etc/fail2ban/filter.d/open-notebook.conf` — then reloads fail2ban. The
rendered filter is

    failregex = ^<HOST> - .* "(GET|POST|PUT|PATCH|DELETE) /open-notebook/api/[^"]*" 401

and `fail2ban-regex` matched the real `401` lines in that log (`Failregex: 3
total`). `fail2ban-client status open-notebook` lists the jail with the correct
file list (0 currently banned), and `yunohost service status fail2ban` stays
`configuration: valid` / `status: running`, so the jail never breaks fail2ban —
which would otherwise block every later app operation.

`maxretry` is 20 rather than the 5 the `ynh_config_add_fail2ban` helper
hard-codes: the frontend issues several API calls at once, so a browser holding
an out-of-date password can produce a handful of `401`s in a single page load.

Because the log path embeds `$domain` and the regex embeds the path, both
templates are rendered here rather than through the helper, `scripts/change_url`
re-runs `open_notebook_configure`, and `scripts/remove` calls
`ynh_config_remove_fail2ban`.

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

### Final acceptance sweep on a clean instance

The finished revision (`b8777e5`) was then re-verified from scratch on a second,
clean YunoHost 12 box, with the app not yet installed, to prove the whole
lifecycle is reproducible rather than an artefact of the long-lived test box.
The sweep ran three stages:

1. **`change_url`** `/open-notebook` → `/notebook` and back — the pages
   `/login`, `/notebooks` and `/config` returned `200` at each new path, and the
   rendered `failregex` followed the path (`/notebook/api/`, then back to
   `/open-notebook/api/`), i.e. no stale URL is left in the fail2ban filter.
2. **`remove --purge`** — both `/etc/fail2ban/jail.d/open-notebook.conf` and
   `/etc/fail2ban/filter.d/open-notebook.conf` were removed, `install_dir` and
   `data_dir` were gone, and `yunohost service status fail2ban` still reported
   `configuration: valid` / `status: running` (the package never leaves
   fail2ban in a broken state).
3. **A fresh `yunohost app install`** of the final revision — exit 0, all four
   units `active`, the API answered `200` **immediately** after install (the
   readiness wait removed the post-install 502 window), the page matrix was
   `/open-notebook` `200`, `/open-notebook/` `308`, `/login` `200`,
   `/notebooks` `200`, `/config` `200`, and the fail2ban jail loaded with
   `maxretry = 20` and a filter that matched the real `401` lines
   (`fail2ban-regex … → Failregex: 3 total`).

Result: **19 checks passed, 1 failed** — and the single "failure" is a typo in
the *test script itself* (`lynoh.local-access.log` instead of
`ynh.local-access.log`); the value the package rendered was correct
(`logpath = /var/log/nginx/ynh.local-access.log`). No package defect.

### Install from the published repository URL (arm64)

The last arm64 run removes the local checkout entirely and installs the app the
way a user (or the catalog) would, straight from GitHub:

```bash
yunohost app install https://github.com/jeffreytigch/open-notebook_ynh \
  -f -a "domain=ynh.local&path=/open-notebook&init_main_permission=all_users"
```

The core cloned the repository's default branch and ran the package's own
`scripts/install`; no local path was involved (`-f` accepts the install without
an interactive confirmation, `-a` supplies the answers). Result: **23 checks
passed, 0 failed**:

* `SUCCESS Installation completed`, version `1.15.0~ynh1`;
* all four units — `open-notebook`, `-api`, `-worker`, `-surreal` — `active`
  **and** `enabled`;
* `GET 127.0.0.1:<port_api>/api/config` → `200`, i.e. the API is already serving
  when the install finishes (no post-install 502 window);
* page matrix: `/open-notebook` `200`, `/open-notebook/` `308` (the Next.js
  trailing-slash redirect), `/login` `200`, `/notebooks` `200`, `/config` `200`;
* unauthenticated `/notebooks` and `/api/notebooks` → `302` to the SSO portal;
* `/api/notebooks` → `401` without a Bearer token, `200` with it;
* the fail2ban jail is present, carries `maxretry = 20`, its failregex points at
  `/open-notebook/api/`, and `fail2ban-client status open-notebook` confirms the
  jail is loaded;
* `/etc/logrotate.d/open-notebook` is in place.

### Install at the root path (`path = /`)

The official YunoHost CI installs every web app at the **root** of a domain first
(`install.root`, `path=/`); it then also tests a sub-path (`install.subdir`) and a
second simultaneous instance (`install.multi`, because this package declares
`multi_instance = true`). A root install exercises a different code path here:
`open_notebook_build_frontend` normalises the literal `/` that YunoHost puts in
`$path` to an empty `basePath`, and `conf/nginx.conf` renders a root `location` and
a root-scoped fail2ban regex. It was therefore verified explicitly:

```bash
yunohost app install https://github.com/jeffreytigch/open-notebook_ynh \
  -f -a "domain=ynh.local&path=/&init_main_permission=all_users"
```

Result: **22 checks passed, 1 failed** — the single failure was the checker itself
(curl without `-L`: `/` answers `307` to `/login`, which the CI's pycurl follows
because `FOLLOWLOCATION=True` before it compares the code to `200`):

* `SUCCESS Installation completed`; all four units `active` **and** `enabled`;
* `GET 127.0.0.1:<port_api>/api/config` → `200`;
* page matrix at the domain root: `/` `307` → `/login` `200`, `/notebooks` `200`,
  `/config` `200`, `/api/notebooks` `200` with a Bearer token;
* unauthenticated `/notebooks` → `302` to the SSO portal;
* the fail2ban jail renders **root-scoped**: `maxretry = 20`, `logpath =
  /var/log/nginx/ynh.local-access.log`, and a failregex of `/api/` that explicitly
  does *not* contain `/open-notebook/api/` — the regex is derived from the real
  path, not hard-coded;
* `fail2ban-client status open-notebook` confirms the jail is loaded;
* `/etc/logrotate.d/open-notebook` and `/var/log/open-notebook` are in place.

### What the official CI will run

`YunoHost/package_check` (branch `main`) derives the test list from the manifest and
`tests.toml` (`lib/parse_tests_toml.py`): `package_linter`, **`install.root`**,
`install.subdir` (this is not a full-domain-only app), **`install.multi`** (because
`multi_instance = true`), `backup_restore`, `upgrade` and `change_url` (web app). Its
install args come from `lib/default_install_args.py` — notably `path=/<app id>`, so
the sub-path default is `/open-notebook` — plus a forced `is_public=1` and
`init_main_permission=visitors`; it then checks the URL with `lib/curl_tests.py`: an
anonymous GET of the app root that must end in `200` with redirects followed,
together with the first stylesheet and script of the landing page.

That extra `is_public` argument is harmless even though this manifest declares no
such question: `yunohost/utils/form.py` turns `-a` into a plain dict and
`prompt_or_validate_form()` only ever reads the options the manifest defines, so an
unused prefilled key is ignored.

### Two simultaneous instances (the official CI's `install.multi`)

Because `manifest.toml` declares `multi_instance = true`, the official suite also
installs the app twice at the same time. That configuration is verified live, with
the exact arguments `package_check` passes — including the extra `is_public=1` and
`init_main_permission=visitors`:

```bash
yunohost app install https://github.com/jeffreytigch/open-notebook_ynh -f \
  -a "domain=ynh.local&path=/open-notebook&is_public=1&init_main_permission=visitors"
yunohost app install https://github.com/jeffreytigch/open-notebook_ynh -f \
  -a "domain=ynh.local&path=/notebook2&is_public=1&init_main_permission=visitors"
```

Result: **88 checks passed, 0 failed** for the two-instance sweep and **6 passed,
0 failed** for the permission behaviour:

* both installs returned `SUCCESS Installation completed`; `open-notebook` and
  `open-notebook__2` each have their four units `active` **and** `enabled`;
* the three ports are distinct per instance (instance 1: main 23658, api 28621,
  surreal 20909; instance 2: main 16222, api 27563, surreal 34282);
* each instance serves its own page matrix — `/notebook2/`, `/notebook2/login`,
  `/notebook2/notebooks`, `/notebook2/config`, `/notebook2/api/notebooks` — with
  the first stylesheet and the first JS chunk of its landing page returning `200`
  (the exact `auto_test_assets` probe of `lib/curl_tests.py`);
* isolation holds: a separate data dir, `.env`, fail2ban jail, log dir and exactly
  two nginx confs on the domain, each jail's failregex scoped to its own prefix
  (`/open-notebook/api/` vs `/notebook2/api/`), and instance 1 still healthy after
  instance 2 was installed;
* with `init_main_permission=visitors` (the mode the CI installs) the app is
  reachable anonymously — no SSO redirect on `/` or `/notebooks` — while the API
  still answers `401` without a token and `200` with the application password;
  restoring the group-gated permission brings the `302` to the SSO portal back;
* the extra `is_public=1` argument the CI always adds is harmless in practice too:
  both installs accepted it although this manifest declares no such question.

### amd64: the source pins are verified; the emulated box cannot be provisioned

This package declares `architectures = ["amd64", "arm64"]`. The arm64 path is
proven end to end above. For amd64 the only environment available here was a
QEMU-emulated container (`docker run --platform linux/amd64`), and that box cannot
run YunoHost at all — before any package code is reached:

* `slapd` never binds: `daemon: bind(8) failed errno=98 (Address already in use)`,
  with systemd reporting `Found left-over process … (slapd) in control group while
  starting unit` and a restart counter of 36, so the `yunohost` package's
  post-installation script fails and leaves it half-configured (`iF`);
* netlink is incomplete under qemu-user:
  `socket(AF_NETLINK, SOCK_RAW, NETLINK_NETFILTER)` returns `EPROTONOSUPPORT`
  (93) inside the emulated box but succeeds on the native arm64 box, so `nft` cannot
  even open its socket (`mnl.c:60: Unable to initialize Netlink socket: Protocol not
  supported`) and YunoHost's post-install firewall step fails with
  `ERROR nftables does not seems to be working on your setup`.
  Two recovery attempts (kill the stray daemon + `dpkg --configure -a`; then a full
  container restart + re-applying the container workarounds) failed identically.

What *is* verified for amd64:

* every per-arch source in `manifest.toml` was re-downloaded and sha256-checked —
  the `main` v1.15.0 tarball, `surreal` `surreal-v2.7.0.linux-amd64.tgz` (25.0 MB)
  and `uv` `uv-x86_64-unknown-linux-gnu.tar.gz` (16.0 MB);
* the build and configure steps around those binaries are architecture-independent
  (`uv sync --frozen`, `npm ci && npm run build`, the same systemd/nginx/fail2ban
  templates), and the only arch-dependent inputs are the two pinned binaries above,
  whose amd64 checksums are confirmed;
* the official `package_check` runs on real amd64 hardware once the app is
  registered in the catalog, so an amd64 install is exercised there.

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
10. **`__PATH__` was left literal inside the fail2ban filter.** Rendering the
   jail through `ynh_config_add_fail2ban --failregex=...__PATH__...` produced a
   filter whose pattern still contained `__PATH__`, so `fail2ban-regex`
   reported `Failregex: 0 total`. `_ynh_replace_vars` only substitutes the
   tokens it finds *in the template file*, never a token that appears inside a
   value passed to a helper. The jail and filter are now rendered from
   `conf/f2b_jail.conf` / `conf/f2b_filter.conf`, and the regex is built in the
   script from `${path%/}` (empty for a root install, the sub path otherwise).
