# Open Questions

This file tracked **(a) decisions for the maintainer** and **(b) facts to verify
on the test YunoHost**. Both sets are now **resolved**: section A by the
maintainer on 2026-10-17, sections B and C by the live verification recorded in
[`native-proof.md`](native-proof.md). Section **D** is deliberately open: those
are optional future improvements, not blockers.

## A. Decisions — RESOLVED (2026-10-17)

Confirmed by the maintainer and baked into the design docs
([`architecture-decisions.md`](architecture-decisions.md),
[`integration-matrix.md`](integration-matrix.md)).

| # | Question | Decision |
|---|---|---|
| A1 | Access model / SSO | **Two layers:** SSOwat gates the URL **and** open-notebook keeps its own shared `OPEN_NOTEBOOK_PASSWORD` (editable via config panel). No per-user separation. ADR-004. |
| A2 | Multi-instance | **Enabled** (`multi_instance = true`); all ports/dirs/services are `$app`-scoped. ADR-007. |
| A3 | Heavy optional runtimes (Docling / Crawl4AI) | **Config-panel toggles, OFF by default.** ADR-006. |
| A4 | Package license | **AGPL-3.0** for the package; upstream is MIT (free software, as the catalog requires). |
| A5 | Repo / publishing | **Public GitHub repo `open-notebook_ynh`** under `jeffreytigch`, plus the `YunoHost/apps` pull request — see [`catalog-submission.md`](catalog-submission.md). |

## B. Questions — RESOLVED

### B0. `change_url` and frontend build
→ **Yes: rebuild the frontend when the path changes.** Implemented in
`scripts/change_url`. A path change alters the baked `basePath`, so the Next.js
build is re-run; a domain-only change skips it. Verified by moving the app
`/open-notebook` → `/notebook` → `/open-notebook`, each hop serving 200 on the
new paths.

### B1. GitHub owner/org
→ The authenticated account **`jeffreytigch`**.

## C. Verifications — RESOLVED (live YunoHost 12 box)

### C1. Frontend standalone layout & env
`.next/standalone` is produced and the asset copy performed by
`open_notebook_build_frontend` is what makes it runnable. `ynh_setup_source`
does apply `patches/<source_id>/*.patch` automatically (all three patches
applied, and `routes-manifest.json` contains `"basePath": "/open-notebook"` for
a sub-path build). Runtime semantics confirmed: `INTERNAL_API_URL` for the
Next `rewrites()` and SSE route handlers, `API_URL` for the browser bundle.

### C2. Python provisioning
→ **`uv`-managed Python 3.12** (`uv python install 3.12` →
cpython-3.12.13), then `uv sync --frozen --no-dev --python 3.12`. `uv.lock` is
respected (`--frozen`); upstream declares `requires-python >=3.11,<3.13`.
Backend build (Python + frontend `npm ci`/`npm run build`) is the slowest part
of an install; it needs network the first time.

### C3. apt/build prerequisites
→ **Only `ffmpeg` and `curl`.** Every Python dependency resolved to a prebuilt
wheel on amd64/arm64 (no compiler needed), and `ffmpeg` (5.1.9 on Bookworm) is
what open-notebook shells out to for audio/video handling.

### C4. SurrealDB exact version
→ **2.7.0**, the newest v2.x, with per-architecture sha256 pinned in
`manifest.toml`. v3 is deliberately never used (the upstream code has no
auto-update path).

### C5. Backup service handling
→ **The framework does not stop app services.** `scripts/backup` therefore stops
the four services itself, copies a consistent RocksDB snapshot into the backup
directory, **always restarts**, and aborts the backup if the snapshot fails.
Verified with a sentinel round trip (backup → `remove --purge` → restore left
only the pre-backup notebook).

### C6. Multiple services registration
→ Registering four `yunohost service add` units for one app is clean (ADR-001);
all four show `active` + `enabled`, survive a reboot, and log under
`/var/log/open-notebook`.

### C7. fail2ban
→ **Applicable, and configured.** nginx logs a `401` for every API request
carrying a missing or wrong Bearer token (`/var/log/nginx/$domain-access.log`),
which is the only reliably parseable authentication-failure signal — the API
itself logs none. The jail is **not** added through `ynh_config_add_fail2ban`,
because that helper hardcodes `maxretry = 5` (the frontend fires several API
calls at once, so a stale stored password would lock a legitimate user out) and
because a `__PATH__` token inside a helper *value* is never substituted. Instead
`open_notebook_configure` renders `conf/f2b_jail.conf` and `conf/f2b_filter.conf`
with `maxretry = 20`, `findtime`/`bantime = 10m`, and a failregex built from
`${path%/}` so it follows the app path. Verified live with `fail2ban-regex`
(`Failregex: 3 total`), `fail2ban-client status open-notebook`, and
`yunohost service status fail2ban` staying `valid` / `running`.

### C8. `client_max_body_size` sync
→ Implemented in `scripts/config`: changing *Maximum upload size* rewrites
`OPEN_NOTEBOOK_MAX_UPLOAD_SIZE_MB` in `.env` **and** both
`client_max_body_size` directives in the nginx config, then restarts.

## D. Lower-priority / future

- Header-based SSO patch (per-user identity) as an upstream contribution.
- Periodic `surreal export` for extra backup safety (config-panel action).
- Sub-permissions (e.g. `/api`) and share links, if upstream grows sharing.
- The app's **level** in the catalog: produced by YunoHost's own CI after the
  catalog pull request — see [`catalog-submission.md`](catalog-submission.md).
