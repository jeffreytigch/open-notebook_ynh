# Open Questions

Things that are either **(a) decisions for the user** or **(b) facts to verify on
the test YunoHost / during Phase 1**.

## A. Decisions — RESOLVED (2026-10-17)

These were confirmed by the maintainer and are now baked into the design docs
([`architecture-decisions.md`](architecture-decisions.md),
[`integration-matrix.md`](integration-matrix.md)).

| # | Question | Decision |
|---|---|---|
| A1 | Access model / SSO | **Two layers:** SSOwat gates the URL **and** open-notebook keeps its own shared `OPEN_NOTEBOOK_PASSWORD` (editable via config panel). No per-user separation. ADR-004. |
| A2 | Multi-instance | **Enabled** (`multi_instance = true`); all ports/dirs/services are `$app`-scoped. ADR-007. |
| A3 | Heavy optional runtimes (Docling / Crawl4AI) | **Config-panel toggles, OFF by default.** ADR-006. |
| A4 | Package license | **AGPL-3.0** for the package; upstream is MIT. |
| A5 | Repo / publishing | **New public GitHub repo `open-notebook_ynh`**; also prepare the `YunoHost/apps` catalog PR draft. |

## B. Remaining questions

### B0. `change_url` and frontend build
A Next.js production build can bake in absolute URLs, which can complicate
`change_url`. Acceptable to **rebuild the frontend** on `change_url` if needed
(slower but correct)?
→ **Default: yes, rebuild if required.**

### B1. GitHub owner/org
Which GitHub account/organization should own the new `open-notebook_ynh` repo?
(Needed before creating it.)
→ **Default: create under the account you have authenticated, and confirm first.**

## C. Verifications (Phase 1, on the test instance)

### C1. Frontend standalone layout & env — MOSTLY RESOLVED
Resolved by reading upstream v1.15.0 source: `output: "standalone"`, no
`basePath`; API is proxied by a Next `rewrites()` to **build-time**
`INTERNAL_API_URL` (`/api/:path*`), plus runtime SSE route handlers that read
`INTERNAL_API_URL` at request time; the browser uses `axios` with
`baseURL = ${apiUrl}/api`, where `apiUrl` comes from the runtime `/config` route
(auto-detect hardcodes `:5055`, so `API_URL` **must** be set). Sub-path support
requires a small patch (ADR-008). Remaining to verify on the test box: exact
`.next/standalone` layout, and that `ynh_setup_source` applies
`patches/<source_id>/*.patch` automatically.

### C2. Python provisioning
Prefer `uv`-managed Python 3.12 (deterministic, network download at install) or
Bookworm's system 3.11? Confirm `uv sync` succeeds offline-ish and how long it
takes.

### C3. apt/build prerequisites
Does the dependency set need anything beyond `ffmpeg`/`curl` (e.g. build tools
for any wheel without a binary)? Confirm on a clean Bookworm.

### C4. SurrealDB exact version
Identify the newest **v2.x** release and compute per-arch sha256 for the
`amd64`/`arm64` tarballs.

### C5. Backup service handling
Does the YunoHost backup framework stop the app's services automatically? Decide
between stopping the DB in `scripts/backup` vs relying on the framework (ADR-003).

### C6. Multiple services registration
Confirm registering four `yunohost service add` units for one app is clean
(ADR-001); fall back to a target/oneshot if not.

### C7. fail2ban — RESOLVED
Yes: nginx logs a `401` for every API request that carries a missing or wrong
Bearer token, on `/var/log/nginx/$domain-access.log`. The package therefore
ships a jail on that line (`ynh_config_add_fail2ban`), validated against the
real log with `fail2ban-regex`; it is reachable only after passing SSOwat.

### C8. `client_max_body_size` sync
Make the config panel keep the nginx body-size limit and
`OPEN_NOTEBOOK_MAX_UPLOAD_SIZE_MB` consistent.

## D. Lower-priority / future

- Header-based SSO patch (per-user identity) as an upstream contribution.
- Periodic `surreal export` for extra backup safety (config-panel action).
- Sub-permissions (e.g. `/api`) and share links, if upstream grows sharing.
