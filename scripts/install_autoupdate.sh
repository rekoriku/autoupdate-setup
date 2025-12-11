#!/usr/bin/env bash
#
# Helper to install and optionally run autoupdate.sh.
# Defaults:
#   SOURCE: repo-root/autoupdate.sh
#   DEST:   /usr/local/sbin/autoupdate.sh
#   RUN_AFTER_INSTALL: true

set -euo pipefail

log() {
    printf '[%s] %s\n' "$(date '+%F %T')" "$*"
}

err() {
    printf '[%s] ERROR: %s\n' "$(date '+%F %T')" "$*" >&2
    exit 1
}

main() {
    if [[ "$(id -u)" -ne 0 ]]; then
        err "Run as root (sudo)."
    fi

    local script_dir repo_root
    script_dir="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
    repo_root="$(cd -- "${script_dir}/.." && pwd -P)"

    local src dst run_after
    src="${SOURCE:-${repo_root}/autoupdate.sh}"
    dst="${DEST:-/usr/local/sbin/autoupdate.sh}"
    run_after="${RUN_AFTER_INSTALL:-true}"

    [[ -f "$src" ]] || err "Source script not found: $src"

    if ! command -v install >/dev/null 2>&1; then
        err "'install' command is required (usually from coreutils)."
    fi

    if [[ "$dst" == /mnt/c/* ]]; then
        log "Warning: installing to /mnt/c may cause permission issues on WSL."
    fi

    log "Installing $src -> $dst (owner root:root, mode 755)..."
    install -o root -g root -m 755 "$src" "$dst"

    log "Done."

    if [[ "${run_after,,}" == "true" || "${run_after,,}" == "yes" || "${run_after}" == "1" ]]; then
        log "Running $dst from its directory..."
        (
            cd -- "$(dirname "$dst")" || err "Failed to cd into $(dirname "$dst")"
            "./$(basename "$dst")"
        )
    else
        log "Skipping run (RUN_AFTER_INSTALL=${run_after})."
    fi
}

main "$@"

