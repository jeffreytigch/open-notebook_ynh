# open-notebook_ynh

A [YunoHost](https://yunohost.org/) application package for
[**open-notebook**](https://github.com/lfnovo/open-notebook) — an open-source,
self-hosted research assistant (a "Google NotebookLM" alternative).

> **Status: planning / not yet installable.** This repository currently contains
> the design documentation and implementation plan only. The package itself
> (manifest, scripts, conf templates) has not been written yet.

## Why this repo exists

open-notebook's official installation routes all assume **Docker Compose**
(or a Docker-hosted database). This package targets a **Docker-free** install
that runs natively on YunoHost (Debian/Bookworm), so it can be integrated with
the YunoHost ecosystem: SSO-gated access, backup/restore, upgrade, `change_url`,
the app store, and the standard YunoHost tooling.

## Documentation

| Document | Purpose |
|---|---|
| [`docs/PLAN.md`](docs/PLAN.md) | The objective, scope, phases and acceptance criteria the implementation follows. |
| [`docs/open-notebook-analysis.md`](docs/open-notebook-analysis.md) | What open-notebook is: components, requirements, config, data, auth, and the constraints each imposes on the package. |
| [`docs/yunohost-packaging-reference.md`](docs/yunohost-packaging-reference.md) | Condensed YunoHost packaging reference (v2 / helpers 2.1): structure, resources, scripts, SSO, and how app CI actually works. |
| [`docs/integration-matrix.md`](docs/integration-matrix.md) | **Inventory of every YunoHost integration feature** and how (or whether) it applies to open-notebook. |
| [`docs/architecture-decisions.md`](docs/architecture-decisions.md) | The chosen native architecture: processes, ports, services, data layout, backup strategy, SSO approach (ADRs). |
| [`docs/open-questions.md`](docs/open-questions.md) | Decisions and verifications still required before/while implementing. |

## Quick facts

| | |
|---|---|
| Upstream | `lfnovo/open-notebook`, MIT, v1.15.0 |
| Runtime (no Docker) | Python 3.11–3.12 + `uv`, Node.js 22, SurrealDB **v2.x**, ffmpeg |
| Target | YunoHost 12 (Debian Bookworm), packaging format v2, helpers 2.1 |
| Architectures | `amd64`, `arm64` |
| License (package) | AGPL-3.0 (to be confirmed) |

## Contributing

This package will be published to GitHub. See `docs/PLAN.md` for the roadmap
and `docs/open-questions.md` for open decisions. In line with the YunoHost
packaging policy, this package aims to closely follow the
[`example_ynh`](https://github.com/YunoHost/example_ynh) template.
