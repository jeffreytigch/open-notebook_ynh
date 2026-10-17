# Catalog submission

The YunoHost catalog lives in [`YunoHost/apps`](https://github.com/YunoHost/apps),
which is **generated**: `apps.toml` only carries metadata for each app, and a
build tool (`apps-tools`) fetches each app repository to build the public
`apps.json` served to the webadmin/user portal. Registering the app therefore
means opening a small pull request against that repository.

## Pull request

| | |
|---|---|
| Pull request | <https://github.com/YunoHost/apps/pull/3662> |
| Base / head | `YunoHost/apps:main` ← `jeffreytigch:add-open-notebook` |
| Changes | `apps.toml` (+8) and `logos/open-notebook.png` (new) |

The entry is inserted alphabetically between `opcache-gui` and `open-web-calendar`:

```toml
[open-notebook]
antifeatures = [ "non-free-network" ]
branch = "main"
category = "productivity_and_management"
potential_alternative_to = [ "Google NotebookLM" ]
state = "working"
url = "https://github.com/jeffreytigch/open-notebook_ynh"
```

Why these values:

* **`antifeatures = [ "non-free-network" ]`** — open-notebook is useless without
  an LLM/embedding provider. It ships no model and its default providers are
  hosted, non-free services (OpenAI, Anthropic, Groq). A local Ollama works, so
  the package stays usable without one, but the catalog convention is to flag
  the dependency on a non-free network service.
* **`branch = "main"`** — **required**, not cosmetic; see the gotcha below.
* **`category = "productivity_and_management"`** — the closest existing
  category for a note-taking / research assistant.
* **`potential_alternative_to = [ "Google NotebookLM" ]`** — open-notebook is
  explicitly a NotebookLM alternative.
* **`state = "working"`** — installed, exercised and torn down successfully on a
  YunoHost 12 instance (see [`native-proof.md`](native-proof.md)).
* **`level`** is deliberately **absent**: the level is a *measured* result, not a
  claim. `YunoHost/ci` runs the official `package_check` suite against every
  catalog app and the `yunohost-bot` opens a pull request with the result every
  Friday evening. It will appear on its own once this PR is merged.

## Gotcha: the `branch` key is mandatory

`apps-tools` defaults to `master` when `branch` is missing:

* `appslib/app_caches.py` → `Repo.clone_from(..., single_branch=True, branch=info.get("branch", "master"))`
* `appslib/list_builder.py` → `infos["branch"] = infos.get("branch", "master")`

This repository's default branch is `main`, so a missing key makes the clone
fail and the app is **silently dropped from the catalog** (the builder logs an
error and skips it). Proof:

```
$ git clone --quiet --single-branch --branch master https://github.com/jeffreytigch/open-notebook_ynh
fatal: Remote branch master not found in upstream origin
$ git clone --quiet --single-branch --branch main   https://github.com/jeffreytigch/open-notebook_ynh   # ok
```

## Logo

`YunoHost/apps/README.md` asks for a **square** logo, named after the app id in
lower case, and "as small as possible"; existing logos weigh 3–20 KB. The
256×256 source PNG was 55 636 B, so it was quantised to a 128-colour RGB PNG
(FASTOCTREE) at **3747 B** with no visible change (RMSE 1.14 against the
original). The catalog build content-addresses the file, so the logo it serves
is `logos/<sha256>.png`.

## Verifying the entry locally

`apps-tools` reproduces exactly what the catalog build does:

```bash
T=$(mktemp -d)
git clone --quiet https://github.com/YunoHost/apps-tools "$T/apps-tools"
python3 -m venv "$T/venv" && "$T/venv/bin/pip" -q install -r "$T/apps-tools/requirements-ci.txt"
git clone --quiet https://github.com/jeffreytigch/apps "$T/apps"      # the fork with the entry
git clone --quiet https://github.com/jeffreytigch/open-notebook_ynh "$T/cache/open-notebook"

cd "$T/apps-tools"
"$T/venv/bin/python" ./catalog_linter.py --apps-dir "$T/apps"                       # metadata sanity
"$T/venv/bin/python" ./list_builder.py  --apps-dir "$T/apps" \
                                        --apps-cache "$T/cache" "$T/out"            # full build
```

The second command writes `$T/out/v3/apps.json`; `open-notebook` must be present
there with the expected `version`, `category`, `state`, `antifeatures`, `git`
block and `logo_hash`. A plain `list_builder.py` run without `--apps-cache`
skips every app whose manifest has not been cached yet, so it validates far less
than it appears to.

## What runs on the pull request

`.github/workflows/consistency_check.yml` runs, in order:

1. `python3 -c "import toml; toml.load(open('apps.toml'))"`
2. `./tools/catalog_linter.py --apps-dir .`
3. `./tools/list_builder.py --apps-dir .`

(plus `validate_json.yml` for the catalog JSON schema, and
`post_commit_chores.yml` afterwards). Workflows of a first-time fork
contributor need a maintainer's approval before they run, so the checks can stay
"pending" until a member of the YunoHost team reviews the pull request.

## After the merge

`yunohost-bot` will open a follow-up pull request adding the measured `level`
(and the `added_date`) once the weekly CI run has tested the app. Nothing needs
to be done manually.
