# Architecture Decisions (ADRs)

The concrete design of the package, recorded as decision records. Each ADR states
the context, the decision, and the consequences, so implementers and reviewers
understand *why*. Decisions marked **[verify]** need confirmation during Phase 1
on the test YunoHost and may be revised with recorded evidence.

---

## ADR-001 — Run all four processes as native systemd services

**Context.** open-notebook is four processes: SurrealDB, the FastAPI API, the
`surreal-commands` worker, and the Next.js frontend. Upstream runs them under
Docker/supervisord. Docker is forbidden here.

**Decision.** Provide four systemd units, all owned by the app's system user:

| Unit | ExecStart (sketch) | Purpose |
|---|---|---|
| `open_notebook-surreal.service` | `<install_dir>/surreal start --log info --user <u> --pass <p> rocksdb:<data_dir>/surreal_data --bind 127.0.0.1:<port_surreal>` | Database |
| `open_notebook-api.service` | `<install_dir>/.venv/bin/python run_api.py` (WorkingDirectory=`<install_dir>`) | REST API + migrations |
| `open_notebook-worker.service` | `<install_dir>/.venv/bin/surreal-commands-worker --import-modules commands --max-tasks <N>` (WorkingDirectory=`<install_dir>`) | Background jobs |
| `open_notebook-frontend.service` | `node start-server.js` (WorkingDirectory=`<install_dir>/frontend`, `PORT=<port>`, `HOSTNAME=127.0.0.1`) | Web UI |

Ordering: API/worker `After=`/`Requires=` SurrealDB; frontend `After=` API.
Each unit logs to `/var/log/$app/<component>.log` and is registered with
`yunohost service add`. All share `EnvironmentFile=<install_dir>/.env`.

**Consequences.**
- Full lifecycle control (`yunohost service start|stop|status $app-*`), clean
  logs, reboot survival.
- Deviates from the common "single `$app` service" convention; we document why.
- **[verify]** Whether YunoHost is happy registering several services for one
  app (it is, in practice, but confirm on the test box). Alternative fallback: a
  single `$app.service` with `Type=oneshot`/`RemainAfterExit` orchestrating the
  others, or a systemd target. Prefer the four-unit layout if it passes.

---

## ADR-002 — Pin SurrealDB to v2.x (do **not** track latest)

**Context.** Upstream pins `surrealdb/surrealdb:v2`; the app's migrations and
queries target v2. The latest SurrealDB release upstream is **v3.3.0**. A naive
`autoupdate.strategy = "latest_github_release"` would jump the app to v3 and
break the database layer.

**Decision.**
- Install SurrealDB from the official release tarball
  (`surreal-v<X.Y.Z>.linux-{amd64,arm64}.tgz`, extracts a `surreal` binary),
  **pinned to the newest v2.x** at packaging time, with `sha256` per arch.
- Do **not** attach an unconstrained autoupdate to this source. Either leave it
  without autoupdate (manual bumps) or use a strategy/asset combination that
  cannot cross the v2 boundary, and add a note in the repo.
- The open-notebook source source (`main`) *may* use
  `autoupdate.strategy = "latest_github_release"` (or `…_tag`).

**Consequences.**
- Stable DB behaviour; a deliberate, tested upgrade path when upstream moves to
  support v3.
- Maintenance burden: SurrealDB security updates must be tracked manually.
- **[verify]** Latest v2.x version number and per-arch sha256 at implementation.

---

## ADR-003 — Data layout and backup strategy

**Context.** `open_notebook/config.py` hardcodes `DATA_FOLDER = "./data"`,
relative to the process working directory. That folder holds chat-history SQLite
checkpoints. SurrealDB holds everything else. The YunoHost `data_dir`
(`/home/yunohost.app/<app>`) is what must survive upgrades and be backed up —
`install_dir` is **not** backed up.

**Decision.**
- The **real** data root is `$data_dir`:
  - `$data_dir/surreal_data/` — SurrealDB rocksdb files.
  - `$data_dir/data/` — uploads, podcasts, `sqlite-db/`, `tiktoken-cache/`.
- Make `<install_dir>/data` a **symlink** to `$data_dir/data` (created by
  `install`), so the app's relative `./data` resolves into `$data_dir` without
  patching upstream. Services run with `WorkingDirectory=<install_dir>`
  (API/worker) so `./data` is found.
- `scripts/backup` backs up:
  - `$data_dir` (DB + data),
  - the rendered configs (nginx, systemd units, logrotate, fail2ban),
  - `/etc/$app/` if we use it.
- `scripts/restore` restores those paths, re-applies ownership, and **re-creates
  the `data` symlink** before starting services.

**DB consistency.** A live rocksdb directory is not guaranteed crash-consistent
when copied. Options (choose during Phase 4, recorded as evidence):
  1. Stop the DB service during backup (`ynh_systemctl --action=stop`) and
     restart after — simplest and safest.
  2. Use `surreal export` to a `.surql` dump for the DB, and copy the plain files
     for `$data_dir/data` — smaller, portable, but must be re-imported on restore.
  Preferred: (1) for correctness, documenting the brief downtime.
  **[verify]** whether the YunoHost backup framework already stops the app's
  services around `backup`/`restore`; if so, rely on it and document.

**Consequences.**
- All user data lives in one backed-up location; upgrades never touch it.
- Requires creating/repairing a symlink in install, restore, and upgrade.

---

## ADR-004 — SSO / access control approach

**Context.** open-notebook has **one shared password** (`OPEN_NOTEBOOK_PASSWORD`)
and no user accounts, LDAP or header-based identity. YunoHost's SSOwat can
**gate** the URL (only permitted users reach the app) and can inject an
`Authorization: Basic …` / `YNH_USER*` header, but open-notebook only understands
`Authorization: Bearer <its own password>`. Therefore; classic "logged into the
portal → automatically logged into the app" is **not achievable without an
upstream change**.

**Decision (confirmed 2026-10-17) — two layers.**
- Put the app behind a YunoHost permission (`main.url = "/"`,
  `init_main_permission`), so access is SSO-gated at the nginx/SSOwat layer.
- Set `[integration] sso = false`, `ldap = false` (the app has a login notion, so
  `"not_relevant"` would be wrong).
- **Also set `OPEN_NOTEBOOK_PASSWORD`** (generated at install) as a second layer,
  and expose it in the config panel for admins to view/rotate. Users therefore
  authenticate once to YunoHost (SSO gate) and once inside the app.
- Document clearly that all permitted users share **one** notebook space (no
  per-user separation).

**Consequences / caveats.**
- Highest-value integration, but with a real limitation to state in `doc/` and
  the app description.
- Requires the config panel to manage `OPEN_NOTEBOOK_PASSWORD` (ADR-006).
- **Future enhancement:** patch or upstream-support header-based auth
  (trust `YNH_USER`) to get true SSO auto-login and per-user separation.

---

## ADR-005 — nginx configuration: SSE streaming and large uploads

**Context.** Chat/Ask responses stream (SSE) from the API; users upload media up
to `OPEN_NOTEBOOK_MAX_UPLOAD_SIZE_MB` (default 100). Naive proxying breaks
streaming (buffering) and rejects large bodies (413).

**Decision.** `conf/nginx.conf`:
- `location __PATH__/` → `proxy_pass` to the **frontend** port; include the
  YunoHost SSO auth params so the gate applies.
- `location __PATH__/api/` → `proxy_pass` to the **API** port directly, with
  streaming-friendly settings: `proxy_buffering off;`, `proxy_cache off;`,
  `proxy_read_timeout` long (e.g. 300s+), `proxy_http_version 1.1`,
  `proxy_set_header Connection "";`, and
  `client_max_body_size` ≥ `OPEN_NOTEBOOK_MAX_UPLOAD_SIZE_MB`.
- Set the frontend/API CORS origin to the app's public origin.

**Consequences.**
- Reliable streaming and uploads.
- Must keep `client_max_body_size` and the app's max-upload setting in sync
  (config panel should update both).
- **[verify]** whether to route `/api/` straight to the API (chosen) vs through
  the Next.js proxy (`INTERNAL_API_URL`); confirm the browser's API base URL
  (`API_URL`/`NEXT_PUBLIC_API_URL`) semantics during Phase 1. Routing directly is
  preferred to avoid a streaming double-hop.

---

## ADR-006 — Config panel scope

**Context.** Several settings are realistically admin-tunable; most are
install-time only.

**Decision.** Ship a `config_panel.toml` (+ `scripts/config`) for:
- app password (set/rotate; if we keep it),
- max upload size (kept in sync with nginx),
- worker concurrency (`OPEN_NOTEBOOK_WORKER_MAX_TASKS`),
- chunk size / overlap,
- opt-in heavy runtimes: Docling, Crawl4AI (+ remote `CRAWL4AI_API_URL`/token).

Excluded from the panel (install-time constants or UI-managed): the encryption
key, SurrealDB credentials/ports, and AI provider keys (managed in the app UI).

**Consequences.**
- Admins can tune cost/performance without SSH.
- Adds a `scripts/config` to maintain and test.

---

## Cross-cutting: install-time build

- Dependencies: `apt` gives `ffmpeg`/`curl`; the `nodejs` resource gives Node 22;
  a pinned `uv` binary is fetched via `sources`; Python 3.12 is provisioned by
  `uv` (fallback: system 3.11 on Bookworm).
- Backend: `uv sync --frozen --no-dev` inside `$install_dir`.
- Frontend: `npm ci` then `npm run build` inside `$install_dir/frontend`; the
  standalone output is run by `node start-server.js`.
- tiktoken: pre-download `o200k_base` at install with `TIKTOKEN_CACHE_DIR`
  pointing into `$data_dir/data/tiktoken-cache` (offline-safe).
- **[verify]** exact Next.js standalone output layout and env var semantics
  (see ADR-005 and `open-questions.md`).

---

## ADR-007 — Multi-instance support

**Context.** YunoHost allows several instances of an app on one server when
`[integration] multi_instance = true`. open-notebook is resource-heavy (a DB, a
Python API, a worker and a Node frontend per instance).

**Decision (confirmed 2026-10-17).** Enable multi-instance
(`multi_instance = true`). This is already feasible by construction: every
resource is `$app`-scoped — ports (`$port`, `$port_api`, `$port_surreal`), paths
(`$install_dir`, `$data_dir`), the system user, the nginx conf, and the four
systemd unit names all derive from the app id.

**Consequences.**
- No extra work in the scripts beyond using `$app`-based names everywhere
  (already the plan).
- Server admins must have the RAM/disk for each instance; document the cost in
  `doc/ADMIN.md`.
- `package_check` will exercise the `install.multi` scenario.

---

## ADR-008 — Serving the frontend at a sub-path (basePath patch)

**Context.** open-notebook's Next.js frontend is built for **root** deployment
(the Docker image serves it at `:8502/`). Its `frontend/next.config.ts` sets
`output: "standalone"` and an API rewrite, but **no `basePath`**. YunoHost apps
are normally installed at a sub-path (e.g. `/open-notebook`), and
`package_check` exercises the `install.subdir` scenario. Without a `basePath`,
the built HTML/JS reference `/_next/...` absolutely and the app 404s when served
under a sub-path.

**Investigation (upstream v1.15.0).** The only browser-side paths that are
root-absolute and would **not** be rewritten by `basePath` are:

- `frontend/src/lib/config.ts` → `fetch('/config', …)`
- `frontend/src/lib/api/client.ts` → `window.location.href = '/login'` (on HTTP 401)

Everything else (`next/link`, `router.push`) is prefixed by Next.js
automatically. API access goes through `axios` with
`baseURL = \`${apiUrl}/api\`` where `apiUrl` is fetched at runtime from `/config`.

**Decision.** Ship a minimal, documented patch
`patches/main/frontend-basepath.patch`:

1. `next.config.ts` — read `NEXT_BASE_PATH` and set `basePath` when non-empty.
2. `src/lib/config.ts` — fetch `` `${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}/config` ``.
3. `src/lib/api/client.ts` — redirect to `` `${process.env.NEXT_PUBLIC_BASE_PATH ?? ''}/login` ``.

Build the frontend with `NEXT_BASE_PATH=$path` and `NEXT_PUBLIC_BASE_PATH=$path`
(empty string when installed at the domain root, so the app also works at `/`).
Next.js then automatically prefixes `basePath` to the `/api/:path*` rewrite and
serves the SSE route handlers under the sub-path too.

**Runtime env that matters (see ADR-005):**
- `API_URL` **must** be set to the public origin **including the path**
  (e.g. `https://domain.tld/open-notebook`). The `/config` route's auto-detection
  otherwise returns `…:5055`, which is not exposed.
- `INTERNAL_API_URL` (`http://127.0.0.1:$port_api`) must be set **at build** (the
  `rewrites()` destination is baked at build time) **and at runtime** (the
  `_sse-proxy` route handler reads it at request time).

**Consequences.**
- The app works both at the domain root and at any sub-path; two instances can
  coexist on one domain at different paths.
- The patch is small and explainable, but **must be re-validated on every
  upstream version bump**; if it fails to apply, the build fails loudly (good).
- `change_url` that changes the *path* requires rebuilding the frontend
  (consistent with B0 in `open-questions.md`).
- Rejected alternative: install only at the domain root (`path = "/"`) with no
  patch. Rejected because it fails `install.subdir` and blocks two instances on
  one domain.

**[verify C1]** `ynh_setup_source` applies `patches/<source_id>/*.patch`
automatically (confirm on the test box); the standalone output layout and
`PORT`/`HOSTNAME` handling.

---

## ADR-009 — The app tile logo comes from the permission, not from the package

**Context.** A first user installed the package on their own server and
reported *"the icon is missing from the YunoHost home screen / app switcher"*.
Investigation on YunoHost 12.1.41:

- the user portal and the admin app list resolve a tile logo **only** from a
  `logo_hash` attached to the app's permission, or from the `logo_hash` of the
  app's entry in the community catalog (`utils/app_utils.py`, `app.py`);
- `logo_hash` is only ever set by `user_permission_update(…, logo=<PNG>)`,
  which stores the file as `/usr/share/yunohost/applogos/<sha256>.png`;
- **nothing in the package format can supply it**: `APP_FILES_TO_COPY` copies
  only `manifest.toml`, `config_panel.toml`, `scripts/`, `conf/`, `hooks/` and
  `doc/` (a `logo.png` at the package root is simply ignored — `example_ynh`
  has none either), and the `[resources.permissions]` resource has no logo
  property (`PermissionsResource.default_perm_properties`);
- the catalog route works only *after* the app is merged into `YunoHost/apps`
  (`app.py` falls back to `apps_catalog[app_id]["logo_hash"]`).

So an install straight from a repository URL — the path our README documents,
and the only one available until the catalog PR is merged — has no logo at all.
On the test box `yunohost app list -f` reported `logo: None` for both
instances, which is exactly the blank tile the user saw.

**Decision.** Ship the 256×256 PNG (the same artwork as the catalog entry) as
`conf/logo.png` — a directory that *is* copied — and register it on the main
permission ourselves:

```bash
yunohost user permission update "$app.main" --logo "$logo_path"
```

via `open_notebook_set_logo()`, called from `scripts/install`,
`scripts/upgrade` and `scripts/restore` (so instances installed by an earlier
revision are fixed by a normal upgrade). It looks for the PNG in
`$YNH_APP_BASEDIR/conf/` first (the extracted package during install/restore)
and falls back to `/etc/yunohost/apps/$app/conf/` (the installed copy).

**Consequences.**
- The logo is set per instance, at install time, and needs no catalog entry; the
  symmetric catalog logo hash is identical, so once the app is in the catalog
  nothing changes for existing instances.
- `yunohost user permission update` is a CLI call, not a helper: `ynh_permission_update`
  (helpers 2.1) can only `--add`/`--remove` groups. The core requires the file to
  be a real PNG (magic `\x89PNG\r\n\x1a\n`), and the call also regenerates the
  per-domain portal data (`/etc/yunohost/portal/<domain>.json`) by itself.
- The logo is *not* versioned per instance: a later change of the artwork is
  applied by the next upgrade/restore.
- Rejected: `cp conf/logo.png /usr/share/yunohost/applogos/<app_id>.png`. That
  filename trick is only honoured by the admin app list (`app.py` returns the
  app id as its logo); the portal keeps using `logo_hash`, so it would fix half
  the symptom and depend on an undocumented path.

---

## ADR-010 — Surfacing the generated application password

**Context.** The same user reported *"the app password was set, but was
incorrect; I had to set a new app password in the admin panel, which then
worked."* Reproducing on the test box showed the password plumbing itself is
sound — `open_notebook_password` is byte-identical to `OPEN_NOTEBOOK_PASSWORD`
in `<install_dir>/.env`, and that value authenticates against the API for both
instances. The real defect is discoverability:

- `config_panel.toml` declares the password as `type = "password"`, and the
  webadmin renders it as a masked `<input type="password">` (placeholder
  `••••••••••••`) with no reveal control — the core exposes the real value only
  in `yunohost app config get --full` / the API payload, which the panel's
  JavaScript never unmasks;
- `yunohost app config get` without `--full` prints `**************`;
- `doc/ADMIN.md` and `doc/POST_INSTALL.md` nevertheless told the user to read
  the password *from the config panel*, which is impossible.

**Decision.** Surface the password from the app settings, which YunoHost
already interpolates into `doc/`, and stop pointing at the config panel:

- reference `__OPEN_NOTEBOOK_PASSWORD__` in `doc/POST_INSTALL.md` (the
  post-install notification) and in `doc/ADMIN.md` / `doc/ADMIN_fr.md` (the
  app's *Documentation* tab, always current);
- `_hydrate_app_template()` replaces `__SETTING_NAME__` tokens with
  `str(settings[token.strip("_").lower()])` when building both the docs and the
  notifications, so no extra machinery is needed;
- the install script prints a `ynh_print_info` explaining where the password
  can be read and changed, but deliberately does **not** echo the secret into
  the operation log (people paste those logs into bug reports);
- the config panel keeps the password editable (rotation) and its `help` now
  states that the field is masked and that the readable copy is on the
  Documentation tab.

**Consequences.**
- The password is readable by the YunoHost admin at any time without a
  rebuild, and survives password rotation.
- The value ends up in the app's documentation, which is admin-only — the same
  audience that could already read it in the panel payload.
- Users still share one notebook space (ADR-004), and the auth layer is
  unchanged: an empty `OPEN_NOTEBOOK_PASSWORD` disables upstream auth entirely,
  so the panel must never be allowed to store an empty value; the option stays
  `type = "password"` (min. 8 characters, enforced by the core's
  `PasswordOption`) rather than a plain string.
