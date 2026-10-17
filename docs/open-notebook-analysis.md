# open-notebook — Upstream Analysis

Facts about the application we are packaging, with the constraint each fact
imposes on a Docker-free YunoHost package. Sources are the upstream repository
(`github.com/lfnovo/open-notebook`, `main`) and its documentation.

| Fact | Source |
|---|---|
| Name / version | `open-notebook` **1.15.0** (`pyproject.toml`) |
| License | MIT (`pyproject.toml` classifier) |
| Tagline | Open-source research assistant inspired by Google NotebookLM |
| Repo | https://github.com/lfnovo/open-notebook |
| Docs | https://github.com/lfnovo/open-notebook/tree/main/docs |

---

## 1. Architecture: four processes

open-notebook is **not a single process**. A full instance runs four things:

```
Browser
   │  HTTPS
   ▼
nginx (YunoHost)
   │
   ▼
Next.js frontend  ──(proxies /api/* → INTERNAL_API_URL)──►  FastAPI API (:5055)
                                                              │
                                     submits jobs ────────────┤
                                                              ▼
                                          job queue in SurrealDB (:8000)
                                                              ▲
                                          background worker ──┘
```

| Process | Role | Default port | How it starts (source) |
|---|---|---|---|
| **SurrealDB** | Database: documents, graph edges, BM25 full-text + vector search | `8000` | `surrealdb start … rocksdb:/mydata/mydatabase.db` |
| **API** | FastAPI app; CRUD, chat/ask synchronous; runs DB migrations on startup | `5055` | `uv run run_api.py` → `uvicorn api.main:app` |
| **Worker** | Picks jobs from SurrealDB and runs `@command` functions (source processing, embeddings, insights, podcasts) | none | `surreal-commands-worker --import-modules commands` |
| **Frontend** | Next.js 16 App Router UI; talks only to the API | `3000` (dev) / `8502` (Docker) | `npm run build` then `node start-server.js` |

**Implication:** the package must run and supervise **four** native processes.
One systemd unit is not enough. See ADR-001.

## 2. Requirements

| Dependency | Constraint | Source | Implication for the package |
|---|---|---|---|
| Python | `>=3.11,<3.13`. 3.13+ unsupported. | `pyproject.toml` | Bookworm = 3.11 (OK). Prefer `uv`-managed 3.12 pinned for determinism. |
| `uv` | Required to install/sync the backend. | from-source doc | Bundle a pinned `uv` binary as an arch-specific source. |
| Node.js | **20.9+**, 22 LTS recommended (Next.js 16 rejects older). | from-source doc, `Dockerfile` (node:22) | Use the YunoHost `nodejs` resource, version `22`. |
| SurrealDB | **v2** (`surrealdb/surrealdb:v2`). Python client `surrealdb>=1.0.4`. | `docker-compose.yml` | Install the v2 Linux binary; **do not** use v3 (ADR-002). |
| ffmpeg | Required for audio/video sources and podcasts. | from-source doc, `Dockerfile` | `apt` dependency. |
| RAM | 4 GB min, 8 GB recommended (more for local models). | installation doc | Set `ram.runtime` estimate; warn in docs. |
| Disk | "Room for Docker images, documents, local models." | installation doc | Frontend `node_modules` + `.next` + Python venv + DB + uploads. Multi-GB. |

## 3. Configuration (environment variables)

From `.env.example` and the code. This is the input for `conf/.env`.

### Required
| Variable | Meaning |
|---|---|
| `OPEN_NOTEBOOK_ENCRYPTION_KEY` | Encrypts provider API keys stored in the DB. **Must not change** after install (changing it breaks decryption). Generate once at install. |

### Database
| Variable | Default | Note |
|---|---|---|
| `SURREAL_URL` | `ws://surrealdb:8000/rpc` | Must become `ws://127.0.0.1:<surreal_port>/rpc` (use `127.0.0.1`, not `localhost` — IPv6 pitfall). |
| `SURREAL_USER` / `SURREAL_PASSWORD` | `root`/`root` | Set to random values; shared by DB and API/worker. |
| `SURREAL_NAMESPACE` / `SURREAL_DATABASE` | `open_notebook` / `open_notebook` | Keep. |

### Auth / security
| Variable | Meaning |
|---|---|
| `OPEN_NOTEBOOK_PASSWORD` | Single shared password. **Auth is fully disabled if unset.** Acted on by `PasswordAuthMiddleware` as `Authorization: Bearer <password>`. |
| `CORS_ORIGINS` | Default `*`. Should be set to the app origin. |
| `OPEN_NOTEBOOK_MAX_UPLOAD_SIZE_MB` | Default 100. Raise for large media; nginx `client_max_body_size` must match. |

### Runtime / paths
| Variable | Meaning | Note |
|---|---|---|
| `API_HOST` / `API_PORT` | API bind. `run_api.py` defaults `127.0.0.1:5055`. | Set host to `127.0.0.1`, port to the booked API port. |
| `API_RELOAD` | Default **`true`** in `run_api.py`. | **Must set `false` in production.** |
| `TIKTOKEN_CACHE_DIR` | Where the tiktoken encoding is cached. | Default `./data/tiktoken-cache`. Docker pre-bakes it for offline use; we must ensure it persists or is pre-downloaded. |
| `OPEN_NOTEBOOK_WORKER_MAX_TASKS` | Worker concurrency (default 5). | Read by the worker at launch. |
| `HTTP_PROXY` / `HTTPS_PROXY` / `NO_PROXY` | Corporate proxy support. | `NO_PROXY` **must** include the SurrealDB host, or the DB websocket is tunnelled and startup fails. |
| `ESPERANTO_LLM_TIMEOUT` | LLM call timeout; defaults to 180 s if unset. | Leave default. |
| `LANGGRAPH_CHECKPOINT_FILE` | Chat history SQLite path. | **Hardcoded constant** in `open_notebook/config.py` → `./data/sqlite-db/checkpoints.sqlite` (relative). |

### Deprecated / UI-configured
`OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GOOGLE_API_KEY`, `GROQ_API_KEY`,
`OLLAMA_API_BASE`, `OMLX_API_BASE` — documented as **deprecated fallbacks**;
providers are configured through the UI and stored encrypted in the DB. Do not
build automation on them.

## 4. Data locations (critical for backup)

Defined in `open_notebook/config.py`. **All paths are relative to the process
working directory** (`DATA_FOLDER = "./data"`):

| Path (relative) | Contents | Back up? |
|---|---|---|
| `./data/sqlite-db/checkpoints.sqlite` | LangGraph chat history | **Yes** |
| `./data/uploads/` | Uploaded files | **Yes** |
| `./data/podcasts/` | Generated podcast audio | **Yes** |
| `./data/tiktoken-cache/` | tiktoken encoding cache | Optional (regenerable) |
| SurrealDB data dir (`rocksdb:` path) | All notebooks, sources, embeddings, credentials, settings | **Yes — the database** |
| `./data/.cache/{uv,playwright,huggingface}` | Opt-in heavy runtimes' caches | No (regenerable, large) |

**Implication:** the app hardcodes `./data`. The package must make `./data`
resolve to the YunoHost `data_dir`, otherwise user data is scattered inside
`install_dir` (which is not backed up). See ADR-003.

## 5. Authentication & identity — the SSO problem

`api/auth.py` → `PasswordAuthMiddleware`:

- Reads `OPEN_NOTEBOOK_PASSWORD` (or `OPEN_NOTEBOOK_PASSWORD_FILE`).
- If unset → **auth disabled entirely**.
- Otherwise requires the header `Authorization: Bearer <password>` (constant-time
  compared). It accepts **only** the `Bearer` scheme. Excluded paths: `/`,
  `/health`, `/docs`, `/openapi.json`, `/redoc`, `/api/auth/status`, `/api/config`.

There is **no** notion of multiple users, no LDAP, no header-based identity, and
no group/role model. The API is not designed to trust `X-Remote-User`/`YNH_USER`.

**Implication:** YunoHost's classic "SSO = auto-login with the portal identity"
is **not natively achievable**. We can still *gate access* with YunoHost's SSO
(the whole app sits behind an SSOwat permission), but the app itself will not
know who the user is. Several options are analysed and one is recommended in
ADR-004.

## 6. Build & run details that affect packaging

- **Backend install:** `uv sync --frozen --no-dev` (uses `uv.lock`, committed).
  Docker sets `UV_COMPILE_BYTECODE=1`, `UV_LINK_MODE=copy`, `UV_NO_SYNC=1` at
  runtime. The venv ends up at `.venv` in the project root.
- **API entry:** `run_api.py` inserts its own directory into `sys.path` and calls
  `uvicorn.run("api.main:app", …)`. Migrations run in the FastAPI `lifespan`
  startup, with retry/wait for the DB — so **the API must start after SurrealDB
  is reachable** (systemd `After=`/`Requires=`).
- **Worker entry:** `surreal-commands-worker --import-modules commands --max-tasks N`.
- **Frontend:** `npm ci` (uses `package-lock.json`), then `npm run build`
  (Next.js standalone output), then `node start-server.js` which sets
  `PORT` default `8502` and requires the standalone `server.js`. The Dockerfile
  layers `.next/standalone`, `.next/static` and `public`. Env: `API_URL`
  (browser-facing) and `INTERNAL_API_URL` (server-side `/api` proxy). **Exact
  standalone file layout and the rewrite/env semantics must be verified on the
  test box** (see `open-questions.md`).
- **tiktoken offline:** Docker pre-downloads the `o200k_base` encoding. For a
  possibly-offline server we should either pre-download it at install (with
  `TIKTOKEN_CACHE_DIR` pointing into the data dir) or accept a first-use
  network fetch.
- **Optional heavy runtimes:** Docling (`OPEN_NOTEBOOK_ENABLE_DOCLING`),
  Crawl4AI (`OPEN_NOTEBOOK_ENABLE_CRAWL4AI`, or a remote `CRAWL4AI_API_URL`).
  These download large ML stacks/Chromium on first start. Keep **off** by
  default; consider exposing via the config panel.

## 7. Versioning / update surface

open-notebook releases frequently. The package should:
- download a pinned upstream **tag tarball** (GitHub `vX.Y.Z`), and
- declare `autoupdate.strategy = "latest_github_release"` (or `…_tag`) in the
  manifest so the YunoHost bot can propose bumps.

SurrealDB must be pinned to **v2.x** and must **not** follow the unconstrained
"latest release" (currently v3.3.0). See ADR-002.

## 8. Open-source / catalog acceptability

- Upstream is **MIT** → acceptable in the YunoHost catalog (free software).
- The app is a *client* of external AI providers; it sends content to whichever
  provider the admin configures. This is a privacy consideration to state in the
  description — but the app itself imposes no tracking or non-free network
  dependency. Any "antifeature" is likely unnecessary, though `ai-*` style
  caveats may be worth mentioning in `doc/`.
