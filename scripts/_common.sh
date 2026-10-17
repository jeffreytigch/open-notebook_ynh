#!/bin/bash

# Shared helpers for the open-notebook YunoHost package.
# Sourced by every script (install/remove/upgrade/backup/restore/change_url).

# ---------------------------------------------------------------------------
# Tunables
# ---------------------------------------------------------------------------

# Keep SurrealDB pinned to a v2.x release: open-notebook's migrations and queries
# target SurrealDB v2 (upstream pins surrealdb/surrealdb:v2). Do NOT let the
# manifest auto-update this source (it would jump to v3).
SURREAL_MAJOR="v2"

# Python interpreter used to build the backend virtualenv.
PYTHON_VERSION="3.12"

# The four native processes of open-notebook. The user-facing frontend is the
# package's main service ($app); the others are suffixed with their component.

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Run a command as the app user, forwarding the environment needed by uv and by
# the frontend build. systemd units read their environment from $install_dir/.env;
# this helper is only for the install / upgrade / restore build steps.
run_as_app() {
    ynh_exec_as_app env \
        PATH="$PATH" \
        HOME="$install_dir" \
        UV_PYTHON_INSTALL_DIR="$data_dir/uv/python" \
        UV_CACHE_DIR="$data_dir/uv/cache" \
        UV_COMPILE_BYTECODE=1 \
        UV_LINK_MODE=copy \
        UV_HTTP_TIMEOUT=120 \
        "$@"
}

# Retrieve the upstream sources and lay out the data directory.
#   $1 = "full" to replace $install_dir (upgrade/restore), otherwise a fresh extract.
open_notebook_setup_source() {
    if [ "${1:-}" == "full" ]; then
        ynh_setup_source --dest_dir="$install_dir" --full_replace --keep=".env data"
    else
        ynh_setup_source --dest_dir="$install_dir"
    fi
    # Side binaries (uv, uvx, surreal) share $install_dir with the app sources.
    ynh_setup_source --dest_dir="$install_dir" --source=uv
    ynh_setup_source --dest_dir="$install_dir" --source=surreal

    chmod +x "$install_dir/uv" "$install_dir/surreal"
    chmod +x "$install_dir/uvx" 2>/dev/null || true

    # Data layout: everything persistent lives under $data_dir.
    #   $data_dir/surreal_data  -> SurrealDB (rocksdb)
    #   $data_dir/data          -> the app's ./data (uploads, podcasts, sqlite, tiktoken)
    #   $data_dir/uv            -> uv-managed interpreter + cache (survives upgrades)
    mkdir -p "$data_dir/data" "$data_dir/surreal_data" "$data_dir/uv/python" "$data_dir/uv/cache"
    mkdir -p "/var/log/$app"
    chown -R "$app:$app" "$data_dir" "/var/log/$app"

    # The app hardcodes ./data relative to its working directory ($install_dir).
    rm -rf "${install_dir:?}/data"
    ln -sfn "$data_dir/data" "$install_dir/data"
    chown -h "$app:$app" "$install_dir/data"
}

# Build the Python backend virtualenv and pre-download the tiktoken encoding.
open_notebook_build_backend() {
    pushd "$install_dir" >/dev/null
    run_as_app "$install_dir/uv" python install "$PYTHON_VERSION"
    run_as_app "$install_dir/uv" sync --frozen --no-dev --python "$PYTHON_VERSION"
    popd >/dev/null

    # Pre-download the tiktoken encoding so a later offline server still works.
    if ! run_as_app env TIKTOKEN_CACHE_DIR="$data_dir/data/tiktoken-cache" \
            "$install_dir/.venv/bin/python" -c "import tiktoken; tiktoken.get_encoding('o200k_base')"; then
        ynh_print_warn "Could not pre-download the tiktoken encoding. It will be fetched on first use."
    fi
}

# Build the Next.js frontend (standalone output) for the current base path.
# $path is "" for a root install, or "/foo" for a sub-path install.
open_notebook_build_frontend() {
    export PATH="$path_with_nodejs:$PATH"
    pushd "$install_dir/frontend" >/dev/null
    run_as_app npm ci
    run_as_app env \
        NEXT_BASE_PATH="$path" \
        NEXT_PUBLIC_BASE_PATH="$path" \
        INTERNAL_API_URL="http://127.0.0.1:$port_api" \
        NODE_ENV=production \
        npm run build
    popd >/dev/null

    # Next.js standalone needs .next/static and public alongside server.js.
    mkdir -p "$install_dir/frontend/.next/standalone/.next"
    rm -rf "$install_dir/frontend/.next/standalone/.next/static" "$install_dir/frontend/.next/standalone/public"
    cp -a "$install_dir/frontend/.next/static" "$install_dir/frontend/.next/standalone/.next/static"
    cp -a "$install_dir/frontend/public" "$install_dir/frontend/.next/standalone/public"

    chown -R "$app:$app" "$install_dir/frontend"
}

# Render the .env file, the systemd units, the nginx configuration and logrotate.
open_notebook_configure() {
    ynh_config_add --template=".env" --destination="$install_dir/.env"
    chmod 600 "$install_dir/.env"
    chown "$app:$app" "$install_dir/.env"

    ynh_config_add_systemd --template="systemd-surreal.service" --service="$app-surreal"
    ynh_config_add_systemd --template="systemd-api.service" --service="$app-api"
    ynh_config_add_systemd --template="systemd-worker.service" --service="$app-worker"
    ynh_config_add_systemd --template="systemd-frontend.service" --service="$app"

    ynh_config_add_nginx
    ynh_config_add_logrotate "/var/log/$app"
}

open_notebook_register_services() {
    _register_service() {
        local name="$1" description="$2" logfile="$3"
        if ! ynh_hide_warnings yunohost service status "$name" >/dev/null; then
            yunohost service add "$name" --description="$description" --log="$logfile"
        fi
    }
    _register_service "$app-surreal" "SurrealDB database for open-notebook" "/var/log/$app/surreal.log"
    _register_service "$app-api" "open-notebook API" "/var/log/$app/api.log"
    _register_service "$app-worker" "open-notebook background worker" "/var/log/$app/worker.log"
    _register_service "$app" "open-notebook frontend" "/var/log/$app/frontend.log"
}

# Install one of the optional heavy runtimes (docling / crawl4ai) into the venv.
open_notebook_install_optional_runtime() {
    local extra="$1"
    local cc_version
    cc_version="$(run_as_app "$install_dir/.venv/bin/python" -c 'import importlib.metadata as m; print(m.version("content-core"))')"
    if ! run_as_app "$install_dir/uv" pip install --python "$install_dir/.venv/bin/python" "content-core[${extra}]==${cc_version}"; then
        ynh_print_warn "Failed to install the optional '${extra}' dependency. Check the logs."
        return
    fi
    if [ "$extra" == "crawl4ai" ]; then
        run_as_app env PLAYWRIGHT_BROWSERS_PATH="$data_dir/data/playwright" \
            "$install_dir/.venv/bin/playwright" install chromium \
            || ynh_print_warn "Failed to download Chromium for Crawl4AI. It can be installed later with 'playwright install --with-deps chromium'."
    fi
}

open_notebook_start_services() {
    ynh_systemctl --service="$app-surreal" --action=start
    # Give SurrealDB a moment to accept connections before the API probes it.
    sleep 2
    ynh_systemctl --service="$app-api" --action=start
    ynh_systemctl --service="$app-worker" --action=start
    ynh_systemctl --service="$app" --action=start
}

open_notebook_stop_services() {
    # Reverse of the start order.
    for service in "$app" "$app-worker" "$app-api" "$app-surreal"; do
        ynh_systemctl --service="$service" --action=stop --timeout=30 || true
    done
}

open_notebook_restart_services() {
    open_notebook_stop_services
    open_notebook_start_services
}

# Re-render the environment + nginx config after a config-panel change.
open_notebook_apply_config() {
    ynh_config_add --template=".env" --destination="$install_dir/.env"
    chmod 600 "$install_dir/.env"
    chown "$app:$app" "$install_dir/.env"
    ynh_config_add_nginx
    open_notebook_restart_services
}
