# open-notebook for YunoHost

A [YunoHost](https://yunohost.org/) application package for
[**open-notebook**](https://github.com/lfnovo/open-notebook) — an open-source,
self-hosted research assistant (a "Google NotebookLM" alternative): import
documents, web pages, audio and video, then chat with them, generate notes,
insights and podcasts.

> **Status: verified on a live YunoHost 12 instance; submitted to the YunoHost
> catalog.** The package installs, runs and upgrades natively (no Docker) on a
> real YunoHost 12 box, where install / backup / restore / upgrade / `change_url`
> / `remove --purge`, the config panel, log rotation, the fail2ban jail and an
> end-to-end upload processed by the background worker were all exercised. The
> recorded evidence is in [`docs/native-proof.md`](docs/native-proof.md); the
> catalog submission is tracked in
> [`docs/catalog-submission.md`](docs/catalog-submission.md).

## Why this package exists

open-notebook's official installation routes all assume **Docker Compose** (or a
Docker-hosted database). This package installs it **natively, without Docker**,
so it integrates with the whole YunoHost ecosystem: permission-gated access,
backup & restore, upgrade, `change_url`, the admin log viewer, and the app store.

### How it runs

Four native systemd services, all owned by a dedicated system user:

| Service | Role | Bound to |
|---|---|---|
| `__APP__-surreal` | SurrealDB database (RocksDB) | `127.0.0.1` |
| `__APP__-api` | FastAPI backend (migrations, REST API) | `127.0.0.1` |
| `__APP__-worker` | Background jobs (indexing, embeddings, podcasts) | — |
| `__APP__` | Next.js frontend | `127.0.0.1` |

nginx reverse-proxies the frontend and the API (`/api/`), with buffering
disabled so chat/Ask responses can stream (Server-Sent Events). All persistent
data (database, uploads, podcasts, chat history) lives in the app's data
directory and is included in YunoHost backups.

## Requirements

* YunoHost 12 (Debian Bookworm), `amd64` or `arm64`.
* **≥ 2 GB RAM** (4 GB+ recommended).
* An **AI provider** (an API key, or a local model server such as Ollama) —
  configured **inside the app** after installation. open-notebook ships no model.

## Access control

Access is gated by the YunoHost permission system, **and** the app keeps its own
shared password. The generated password is shown in the post-install notification
and stays readable on the app's **Documentation** tab; it can be changed from the
**Configuration** tab (where it is masked). open-notebook has no per-user
accounts, so all allowed users share one workspace. Install a second instance if
you need separation.

## Installation (from this repository)

```bash
yunohost app install https://github.com/jeffreytigch/open-notebook_ynh
```

During development, install from a local clone:

```bash
yunohost app install /path/to/open-notebook_ynh
```

## Optional features

The config panel can enable two heavier, optional runtimes (off by default):
**Docling** (advanced document conversion) and **Crawl4AI** (the crawling of
JavaScript-heavy pages, which downloads a headless browser).

## Repository layout

```
manifest.toml            Package definition (format v2, helpers 2.1)
config_panel.toml        Admin-facing settings
conf/                    nginx, systemd units and .env templates
scripts/                 install / remove / upgrade / backup / restore / change_url / config
patches/                 Small upstream patches (sub-path support)
doc/                     User & admin documentation shown in YunoHost
tests.toml               YunoHost test-suite configuration
.github/workflows/       Lint CI (package_linter, shellcheck, TOML/schema)
docs/                    Design & planning documentation (see below)
```

## Documentation

| Document | Purpose |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | Objective, scope, phases and acceptance criteria. |
| [`docs/open-notebook-analysis.md`](docs/open-notebook-analysis.md) | What open-notebook is and the constraints it imposes. |
| [`docs/yunohost-packaging-reference.md`](docs/yunohost-packaging-reference.md) | Condensed YunoHost packaging reference (v2 / helpers 2.1). |
| [`docs/integration-matrix.md`](docs/integration-matrix.md) | Inventory of every YunoHost integration feature and its applicability. |
| [`docs/architecture-decisions.md`](docs/architecture-decisions.md) | Architecture decision records (processes, data, backup, SSO, sub-paths). |
| [`docs/open-questions.md`](docs/open-questions.md) | Decisions and verification results (all resolved). |
| [`docs/RUNBOOK.md`](docs/RUNBOOK.md) | Manual native install procedure used to validate the stack. |
| [`docs/native-proof.md`](docs/native-proof.md) | Recorded evidence that the stack runs natively (no Docker), and the bugs that proof found. |
| [`docs/catalog-submission.md`](docs/catalog-submission.md) | The `YunoHost/apps` entry, the pull request and how the catalog build is verified. |

## Quality checks

`.github/workflows/lint.yml` runs, on every push and pull request:
[`package_linter`](https://github.com/YunoHost/package_linter) (the official
static analyser), `bash -n` + `shellcheck` on the scripts, and TOML/schema
validation. The official YunoHost **integration** tests
([`package_check`](https://github.com/YunoHost/package_check)) run on YunoHost's
own CI once the app is registered in the catalog — that is what produces the
app's **level**, and it is tracked in
[`docs/catalog-submission.md`](docs/catalog-submission.md). Pull-request
templates include the `!testme` trigger for the dev CI.

## License

The **package** is licensed under **AGPL-3.0** (see [`LICENSE`](LICENSE)).
open-notebook itself is MIT-licensed; see its
[repository](https://github.com/lfnovo/open-notebook).
