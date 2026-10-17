# YunoHost Integration Matrix

An inventory of every YunoHost integration feature, whether it applies to
open-notebook, how we will implement it, and any caveats. This directly answers
the request to "use all available features (backup and restore, SSO, etc.),
inventorise them, and see what can be configured".

Legend — **Status**: ✅ used · 🟡 partial · ⛔ not applicable · ❓ open (see
[`open-questions.md`](open-questions.md)).

| # | Feature | Status | How we implement it | Caveats |
|---|---|---|---|---|
| 1 | Installer (`scripts/install`) | ✅ | Native install: sources → `uv`/Python → frontend build → config → services → start. | Heavy (Node build + Python sync). |
| 2 | Remover (`scripts/remove`, `--purge`) | ✅ | Stop & unregister services, remove configs; `data_dir` wiped only on purge (core handles it). | — |
| 3 | Backup (`scripts/backup`) | ✅ | Back up `$data_dir` (DB + uploads + podcasts + sqlite) and app configs. | DB consistency — see ADR-003. |
| 4 | Restore (`scripts/restore`) | ✅ | `ynh_restore` each path, re-own, re-register services, restart. | Must restore *before* services start. |
| 5 | Upgrade (`scripts/upgrade`) | ✅ | Re-render configs, `uv sync`, rebuild frontend when needed, run DB migrations, restart. | Must not clobber the encryption key. |
| 6 | `change_url` (`scripts/change_url`) | ✅ | `ynh_config_change_url_nginx` + update any URL baked into env/config. | Frontend env may embed the URL; verify. |
| 7 | Systemd service(s) | ✅ | Four units: `-surreal`, `-api`, `-worker`, `-frontend` (ADR-001). | YunoHost convention often assumes one `$app` service; document multi-service rationale. |
| 8 | SSO login (SSOwat auto-login) | 🟡 | Not natively possible — the app has one shared password and no user model. **Two-layer** model: SSOwat gates the URL **and** the app keeps its own shared password (ADR-004). | No per-user separation; the biggest integration limitation. |
| 9 | LDAP integration (YunoHost accounts) | ⛔ | App cannot consume LDAP. `ldap = false`. | Would need an upstream patch. |
| 10 | Permissions / groups | ✅ | `[resources.permissions] main.url = "/"`, `init_main_permission`; portal tile. | One permission only (no per-area split needed). |
| 11 | Portal tile (`show_tile`) | ✅ | Default on for `main`. | — |
| 12 | Ports / firewall | 🟡 | Book internal ports (`main`, `api`, `surreal`); keep them **not exposed** (nginx fronts them). | Only `main` is user-facing. |
| 13 | nginx reverse proxy | ✅ | `'/' → frontend`, `'/api/' → API`, tuned for SSE + large uploads (ADR-005). | — |
| 14 | HTTPS | ✅ | Provided by YunoHost automatically for the app domain/path. | App must be told to trust the proxy. |
| 15 | Data dir (`data_dir`) | ✅ | Real `/data`: SurrealDB rocksdb, uploads, podcasts, sqlite. | Relocated from the app's default `./data` (ADR-003). |
| 16 | Log rotation | ✅ | `ynh_config_add_logrotate`; each unit logs under `/var/log/$app/`. | Ensure all four services log there. |
| 17 | fail2ban | 🟡 | Add a jail only if a usable log/failregex exists (e.g. app auth failures). | App logs auth failures? verify; otherwise skip. |
| 18 | Config panel (`config_panel.toml`) | ✅ | Expose: app password, upload size limit, worker concurrency, chunk size, opt-in Docling/Crawl4AI. | ADR-006. |
| 19 | Multi-instance | ✅ | `multi_instance = true`; all ports/dirs/services are `$app`-scoped (ADR-007). | Very resource-heavy per instance. |
| 20 | `ynh_config_add` / templating | ✅ | `.env`, the 4 systemd units and nginx conf rendered from `conf/`. | Track checksums so upgrades preserve admin edits. |
| 21 | Actions / buttons (config panel) | 🟡 | Possible actions: "test AI provider", "rebuild embeddings", "restart worker". | Post-v1; only if clearly useful. |
| 22 | `autoupdate` (manifest) | ✅ | Upstream tag tarball follows latest release; **SurrealDB stays pinned to v2** (ADR-002). | SurrealDB pin needs a constrained strategy. |
| 23 | Catalog publication (`apps.toml`) | ✅ | Submit PR to `YunoHost/apps` once CI is green. | Level auto-assigned by bot. |
| 24 | App store description / screenshots | ✅ | `doc/DESCRIPTION.md` (+_fr), screenshots; antifeatures if needed. | Privacy caveat about external AI providers. |
| 25 | `tests.toml` / official CI | ✅ | Minimal `tests.toml`; rely on `ci-apps(.dev).yunohost.org`. | No GH Action for this. |
| 26 | github CI (`package_linter` etc.) | ✅ | Our own `lint.yml` (PLAN Phase 6). | Complements, not replaces, official CI. |
| 27 | Email sending / SMTP | ⛔ | App sends no email. | `allow_email` not needed. |
| 28 | SSH/SFTP for the app user | ⛔ | Not needed. | — |
| 29 | PHP-FPM | ⛔ | No PHP. | — |
| 30 | MySQL/PostgreSQL resource | ⛔ | SurrealDB is not a YunoHost `database` resource; we manage the binary. | — |
| 31 | Cron / timers | 🟡 | The app has no cron; the worker is a long-running service. | A periodic `surreal export` backup could be a future action. |
| 32 | Hooks (`hooks/`) | ❓ | Could add `post_app_addaccess` / `post_user_create` later. | Low value here (no per-user model). |
| 33 | Translation (`_fr`) | ✅ | Ship French variants of description/docs. | Not on Weblate. |
| 34 | Diagnostics / service status | ✅ | Register services so `yunohost service status/log` works; ports resource adds a check. | — |

## Summary of what "all features" means here

- **Fully used:** install/remove/upgrade, backup/restore, change_url, systemd
  services, nginx + HTTPS, permissions/portal tile, data_dir, log rotation,
  config panel, autoupdate, catalog publication, CI/lint, docs + French.
- **Partially applicable / caveated:** SSO (two-layer: gating + app password;
  no auto-login), fail2ban (if usable logs exist), actions.
- **Not applicable:** LDAP mapping, PHP/MySQL/Postgres resources, email, SSH,
  app-side cron.

The two design-critical items are **SSO (ADR-004)** and **SurrealDB version
pinning + data/backup layout (ADRs 002–003)**.
