# Implementation Plan

This is the authoritative plan for the `open-notebook_ynh` package. It defines
the objective the implementation goal follows, the scope, the phases, and the
acceptance criteria. It is intentionally written so an implementing agent can
work through it without re-deriving decisions.

Companion documents:

- [`open-notebook-analysis.md`](open-notebook-analysis.md) — the upstream app.
- [`yunohost-packaging-reference.md`](yunohost-packaging-reference.md) — the platform.
- [`integration-matrix.md`](integration-matrix.md) — feature-by-feature applicability.
- [`architecture-decisions.md`](architecture-decisions.md) — the chosen design (ADRs).
- [`open-questions.md`](open-questions.md) — what still needs confirming.

---

## 1. Objective

Produce an open-source YunoHost package `open-notebook_ynh` that installs,
configures, integrates, backs up, restores, upgrades and removes the
open-notebook research assistant **natively on YunoHost without Docker**, using
all applicable YunoHost integration features, and that is ready to be submitted
to the YunoHost application catalog — with GitHub-based CI/CD and repository
hygiene suitable for open-source maintenance.

## 2. Scope

### In scope
- A complete packaging-format-v2 / helpers-2.1 YunoHost app package.
- Docker-free native execution of all four open-notebook processes
  (SurrealDB, API, background worker, frontend).
- Full YunoHost integration: permissions/SSO gating, backup & restore, upgrade,
  `change_url`, remove (with purge), systemd services, log rotation, firewall
  ports, and a config panel where it adds value.
- GitHub repository setup: license, README, issue/PR templates, GitHub Actions
  (lint/quality), and the standard YunoHost contribution flow (catalog PR).
- Documentation for admins/users (`doc/`).

### Out of scope (v1)
- Modifying/forking open-notebook upstream source (no patches to add LDAP or
  header-based auth). Any such change is a *future enhancement* (§7).
- Docker, Podman or container-based deployment in any form.
- Bundling heavy optional runtimes (Docling OCR, local Crawl4AI) by default.
  These stay opt-in (documented, and possibly exposed via the config panel).
- Local LLM runtimes (Ollama etc.) — the app is a *client* of providers; it does
  not port-forward those.
- `armhf` / `i386` architectures.

## 3. Guiding constraints

1. **No Docker.** Every component must run as a native process under systemd.
2. **Follow `example_ynh`.** YunoHost rejects generated packages that deviate
   from the template's structure and conventions.
3. **Understand every line.** Per YunoHost policy, the package must be
   maintainable by the community; no un-explainable generated code.
4. **SurrealDB v2 only.** Upstream pins `surrealdb/surrealdb:v2` and the app's
   migrations/queries target v2. Do **not** use SurrealDB v3.
5. **Python 3.11–3.12.** `pyproject.toml` is `>=3.11,<3.13`. Bookworm ships
   3.11; prefer a pinned, `uv`-managed 3.12 for determinism.
6. **Single shared password auth.** open-notebook has no per-user accounts, so
   classic LDAP/SSO auto-login is not natively supported. See ADR-004.

## 4. Proposed repository layout

```
open-notebook_ynh/
├── .github/
│   ├── ISSUE_TEMPLATE.md            # from example_ynh
│   ├── PULL_REQUEST_TEMPLATE.md     # from example_ynh (!testme instructions)
│   └── workflows/
│       ├── lint.yml                 # package_linter + schema + shellcheck
│       └── (dependabot.yml)         # gh-actions updates
├── conf/
│   ├── nginx.conf                   # reverse proxy to frontend + /api
│   ├── systemd-surreal.service
│   ├── systemd-api.service
│   ├── systemd-worker.service
│   ├── systemd-frontend.service
│   └── .env                         # app environment template
├── doc/
│   ├── DESCRIPTION.md / DESCRIPTION_fr.md
│   ├── ADMIN.md
│   ├── PRE_INSTALL.md / POST_INSTALL.md
│   └── screenshots/
├── scripts/
│   ├── _common.sh
│   ├── install
│   ├── remove
│   ├── upgrade
│   ├── backup
│   ├── restore
│   ├── change_url
│   └── config                     # only if config_panel.toml is used
├── config_panel.toml              # optional (see ADR-006)
├── manifest.toml
├── tests.toml
├── LICENSE
├── README.md
└── docs/                          # this planning documentation (may be trimmed
                                   # before catalog submission to keep the repo tidy)
```

## 5. Phases

Each phase lists concrete deliverables and how it is verified. Phases are
ordered by dependency; verification evidence must be recorded before a phase is
marked complete.

### Phase 0 — Groundwork
- Confirm the YunoHost target version and test-instance details (see
  `open-questions.md`).
- Freeze the design decisions in `architecture-decisions.md`.
- Create the repo skeleton (LICENSE, README, `.gitignore`, issue/PR templates).
- **Verify:** repo exists on GitHub; skeleton matches `example_ynh` conventions.

### Phase 1 — Native runtime proof (manual, on the test YunoHost)
Before writing packaging scripts, prove the whole stack runs natively on a
Debian/Bookworm box:
1. Install SurrealDB v2 binary, start it, confirm it binds a local port.
2. `uv sync` the backend against a pinned Python 3.12; run `run_api.py`
   (`API_RELOAD=false`) and confirm migrations apply against SurrealDB.
3. Start the worker (`surreal-commands-worker --import-modules commands`).
4. `npm ci && npm run build` the frontend; run the standalone server; confirm
   the UI loads and talks to the API.
5. Confirm ffmpeg is detected; confirm uploads, podcasts and the sqlite
   checkpoint land under the chosen data directory.
- **Verify:** a documented, reproducible manual runbook; recorded observations
  (exact commands, env, ports, gotchas) captured as a `doc/`-adjacent note.

### Phase 2 — Package skeleton and manifest
- Write `manifest.toml`: metadata, `[upstream]`, `[integration]` (helpers 2.1,
  arches, `ldap`/`sso` per ADR-004, disk/ram estimates), `[install]` questions,
  and `[resources]` (sources incl. arch-specific SurrealDB + `uv`; system_user;
  install_dir; data_dir; permissions; ports; apt; nodejs).
- Write `conf/` templates (nginx, four systemd units, `.env`).
- **Verify:** manifest passes YunoHost schema validation and `package_linter`
  (when runnable); `taplo`/toml parse clean.

### Phase 3 — Core scripts (install / remove)
- `scripts/install`: sources → dependencies (uv, Python, node deps, frontend
  build) → config render → services registered & started → post-install.
- `scripts/remove`: symmetric teardown; data purged only with `--purge`.
- **Verify:** install on the test instance, app reachable via its URL, all four
  services healthy; remove leaves no residue (and `--purge` wipes data).

### Phase 4 — Lifecycle scripts (backup / restore / upgrade / change_url)
- `scripts/backup` + `scripts/restore` covering the DB and the app data dir,
  configs, and services (see ADR-003).
- `scripts/upgrade` reconciling sources and re-running config/service setup,
  including migrations.
- `scripts/change_url` (nginx) plus any app config that embeds the URL.
- **Verify:** `yunohost backup create` then `restore` round-trips the full
  dataset; `change_url` moves the app to a new path/domain and it still works;
  upgrade from the previous committed version succeeds.

### Phase 5 — Integration polish
- Config panel (`config_panel.toml` + `scripts/config`) for the settings the
  admin realistically needs to change (see ADR-006).
- Fail2ban config (if a log signal exists), log rotation, `doc/` admin notes,
  translation stubs (`_fr`).
- **Verify:** settings edited via webadmin take effect; logs rotate; docs render.

### Phase 6 — CI/CD and quality gates
- GitHub Actions `lint.yml`: `package_linter`, manifest/tests schema checks,
  `shellcheck`, `bash -n`, toml/yaml validation.
- `.github/ISSUE_TEMPLATE.md`, `PULL_REQUEST_TEMPLATE.md`.
- Push a first release tag; add a `test_upgrade_from` entry to `tests.toml`.
- **Verify:** workflow is green on `main`; YunoHost official/dev CI reaches a
  good level (see §6).

### Phase 7 — Catalog & release readiness
- Publish the repo (public), submit the `apps.toml` PR to `YunoHost/apps`.
- Finalize README and documentation.
- **Verify:** app appears in the wishlist/catalog workflow; installs from the
  published repo on a clean instance.

## 6. Acceptance criteria

The package is "done" when **all** of the following hold:

1. **Installs cleanly** on a fresh YunoHost 12 instance (amd64 and, if
   available, arm64) via `yunohost app install <url>` — no Docker anywhere.
2. **All four processes** run as managed systemd services with logs, and survive
   a reboot.
3. **Web access** works behind nginx over the app's domain/path with no 404/502,
   including large uploads and SSE-based chat streaming.
4. **Access control** integrates with YunoHost: a `main` permission gates the
   app; the behaviour documented in ADR-004 (SSO gating) is in effect.
5. **Backup & restore** round-trips the database and all user data with
   integrity verified (restore to a clean instance yields the same content).
6. **Upgrade** from the previous version works and runs DB migrations.
7. **`change_url`** works.
8. **Remove** cleans up; `--purge` removes data.
9. **Quality gates pass:** `package_linter` clean (or only justified warnings),
   GitHub Actions green, YunoHost CI shows a maintained level.
10. **Documentation** exists: DESCRIPTION, ADMIN notes, PRE/POST_INSTALL, README.

## 7. Risks and mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| SurrealDB v3 exists upstream; naive autoupdate jumps versions | Broken DB | Pin to v2.x; do not use an unconstrained `latest_github_release` for SurrealDB (ADR-002). |
| `uv`-managed Python download at install time | Longer install; network reliance | Pin `uv` + Python version; document; allow system 3.11 fallback. |
| Frontend build is heavy (Node) | Minutes + RAM at install | Pre-build? No — build in `install`; set `ram.build` realistically; verify on test box. |
| SSE / large uploads through nginx | Chat breaks / 413 | Explicit nginx tuning (`proxy_buffering off`, long timeouts, `client_max_body_size`) — ADR-005. |
| Data written to `./data` (relative) | Backup misses data | WorkingDirectory + symlink data dir into `$data_dir` (ADR-003). |
| Single-password auth | Users expect SSO auto-login | ADR-004: SSO-gate at nginx layer; document the limitation. |
| YunoHost rejects generated code | Catalog refusal | Strictly follow `example_ynh`; human review; keep code idiomatic. |

## 8. Definition of done for this planning phase

- All five documentation files exist and are internally consistent.
- Open decisions are listed in `open-questions.md`.
- A goal is created whose objective matches §1 and whose plan mirrors §5.
