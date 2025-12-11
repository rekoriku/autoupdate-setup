#!/usr/bin/env bash
#
# ==============================================================================
# SCRIPT: secure-unattended-setup.sh
# PURPOSE: Configures secure, idempotent, and periodic unattended-upgrades.
# VERSION: 3.0.0 (Hardened Bash, Sudoers Fixes)
# DEPENDENCY: Requires Bash for robust scripting features (set -o pipefail, local).
# ==============================================================================

# --- Configuration & Environment Setup ---

# Strict error handling: Exit immediately if a command fails (-e),
# exit if any variable is unset (-u), and ensure pipelines fail correctly (-o pipefail).
set -euo pipefail

# --- Defaults ---
LOG_DIR="${LOG_DIR:-/var/log/unattended-upgrades}"
SETUP_LOG_FILE="${LOG_DIR}/setup.log"
SUDOERS_TARGET="${SUDOERS_TARGET:-/etc/sudoers.d/autoupdate}"
REBOOT_TIME="${REBOOT_TIME:-03:30}"
EXTRA_PACKAGES="${EXTRA_PACKAGES:-ytl-linux-digabi2}"
# Allow tests or alternative environments to override apt configuration directory
APT_CONF_DIR="${APT_CONF_DIR:-/etc/apt/apt.conf.d}"
# Optional: override PATH (used in tests to point at stub commands)
PATH_OVERRIDE="${PATH_OVERRIDE:-}"
# Optional: skip root check (test-only)
SKIP_ROOT_CHECK="${SKIP_ROOT_CHECK:-false}"
# Extra Allowed-Origins for unattended-upgrades (one per line); default includes Naksu/Digabi repo
ALLOWED_EXTRA_ORIGINS="${ALLOWED_EXTRA_ORIGINS:-linux.abitti.fi:ytl-linux}"
# Allow tests or alternative environments to override apt configuration directory
APT_CONF_DIR="${APT_CONF_DIR:-/etc/apt/apt.conf.d}"
# Optional: override PATH (used in tests to point at stub commands)
PATH_OVERRIDE="${PATH_OVERRIDE:-}"
# Optional: skip root check (test-only)
SKIP_ROOT_CHECK="${SKIP_ROOT_CHECK:-false}"

# Environment Setup
export DEBIAN_FRONTEND='noninteractive'
if [[ -n "$PATH_OVERRIDE" ]]; then
    export PATH="$PATH_OVERRIDE"
else
    export PATH='/usr/sbin:/usr/bin:/sbin:/bin'
fi
umask 022

# State variables
TARGET_USER="${TARGET_USER:-${SUDO_USER:-}}"
ENABLE_NOPASSWD="${ENABLE_NOPASSWD:-false}"
SCRIPT_PATH=''
DISTRO_ORIGIN=''
DISTRO_CODENAME=''
TMP_FILES=()

# --- Utility Functions ---

log() {
    printf '[%s] [INFO] %s\n' "$(date '+%F %T')" "$*"
}

error() {
    printf '[%s] [FATAL] %s\n' "$(date '+%F %T')" "$*" >&2
    exit 1
}

# Retry mechanism with exponential backoff
apt_retry() {
    local attempt=1 max=3 delay=5 cmd_status=0
    
    while (( attempt <= max )); do
        if "$@"; then return 0; fi
        cmd_status=$?
        
        if (( attempt == max )); then
            log "Command failed after $attempt attempts (rc=$cmd_status): $*"
            return "$cmd_status"
        fi
        
        log "Command failed (attempt $attempt/$max, rc=$cmd_status); retrying in ${delay}s: $*"
        sleep "$delay"
        delay=$((delay * 2))
        attempt=$((attempt + 1))
    done
}

is_true() {
    local v="${1,,}"
    [[ "$v" == "true" || "$v" == "1" || "$v" == "yes" ]]
}

# Idempotent file write: checks if content has changed before overwriting
write_if_changed() {
    local src="$1" dst="$2" mode="${3:-644}"
    
    if [[ -f "$dst" ]] && cmp -s "$src" "$dst"; then
        log "No changes required for $dst."
        rm -f "$src"
        return
    fi

    if ! command -v install >/dev/null 2>&1; then
        log "WARNING: 'install' not found, falling back to cp/chmod."
        cp "$src" "$dst"
        chmod "$mode" "$dst"
        chown root:root "$dst"
    else
        install -o root -g root -m "$mode" "$src" "$dst"
    fi
    rm -f "$src"
    log "Updated $dst with mode $mode."
}

# --- Cleanup and Trap ---

cleanup() {
    for f in "${TMP_FILES[@]}"; do
        if [[ -n "${f:-}" && -e "$f" ]]; then
            # Attempt to remove; log only if removal fails
            if ! rm -f "$f"; then
                log "Failed to remove temporary file: $f"
            fi
        fi
    done
}
trap cleanup EXIT INT TERM

mktemp_tracked() {
    local tmp_file
    tmp_file="$(mktemp 2>/dev/null)" || error "Failed to create temporary file."
    TMP_FILES+=("$tmp_file")
    printf '%s' "$tmp_file"
}

# --- Pre-flight Checks and Assertions ---

check_dependencies() {
    # Set local IFS for correct space-delimited loop iteration
    local IFS=' '
    # stat is intentionally excluded and checked separately in assert_script_safe
    local deps="apt visudo mktemp cmp install dpkg apt-cache"
    
    for cmd in $deps; do
        [[ -n "$cmd" ]] || continue
        command -v "$cmd" >/dev/null || error "Required command '$cmd' not found."
    done
}

validate_inputs() {
    if is_true "$SKIP_ROOT_CHECK"; then
        log "WARNING: Root check skipped because SKIP_ROOT_CHECK=true."
    else
        [[ "$(id -u)" -eq 0 ]] || error "Please run as root (use sudo)."
    fi

    if command -v readlink >/dev/null 2>&1 && readlink -f "$0" >/dev/null 2>&1; then
        SCRIPT_PATH="$(readlink -f "$0")"
    else
        SCRIPT_PATH="$(pwd)/$(basename "$0")"
        log "WARNING: Using fallback SCRIPT_PATH: $SCRIPT_PATH"
    fi
    
    [[ "$REBOOT_TIME" =~ ^([01]?[0-9]|2[0-3]):[0-5][0-9]$ ]] || \
        error "Invalid REBOOT_TIME format: '$REBOOT_TIME'. Use HH:MM."
    
    if is_true "$ENABLE_NOPASSWD"; then
        [[ -n "$TARGET_USER" ]] || error "TARGET_USER is required when ENABLE_NOPASSWD=true."
    fi
}

assert_script_safe() {
    if ! command -v stat >/dev/null; then
        log "WARNING: 'stat' command not found. Skipping strict script safety checks."
        return 0
    fi
    
    local owner_uid perms
    
    if ! owner_uid="$(stat -c '%u' "$SCRIPT_PATH" 2>/dev/null)"; then
        log "WARNING: 'stat -c' failed. Skipping strict script safety checks."
        return 0
    fi
    
    [[ "$owner_uid" == "0" ]] || error "Script must be owned by root (UID 0) for security."

    if ! perms="$(stat -c '%a' "$SCRIPT_PATH" 2>/dev/null)"; then
        log "WARNING: 'stat -c' failed. Skipping strict script safety checks."
        return 0
    fi
    
    if [[ "$perms" =~ [2367][2367]$ ]]; then
        error "Script has unsafe permissions ($perms). Must not be group/other writable."
    fi
}

detect_distro() {
    if [[ ! -r /etc/os-release ]]; then
        error "Unable to read /etc/os-release. Cannot determine distribution."
    fi

    # shellcheck disable=SC1091
    source /etc/os-release
    
    DISTRO_ID="${ID:-ubuntu}"
    DISTRO_CODENAME="${VERSION_CODENAME:-}"

    case "${DISTRO_ID,,}" in
        debian) DISTRO_ORIGIN="Debian" ;;
        ubuntu) DISTRO_ORIGIN="Ubuntu" ;;
        *)
            log "WARNING: Using fallback DISTRO_ID as Origin: $DISTRO_ID"
            DISTRO_ORIGIN="$DISTRO_ID"
            ;;
    esac
    
    [[ -n "$DISTRO_CODENAME" ]] || error "Distro detection failed (missing CODENAME)."
    log "Detected distro: $DISTRO_ID $DISTRO_CODENAME (Origin: $DISTRO_ORIGIN)"
}

# --- Core Logic ---

configure_sudoers() {
    if ! is_true "$ENABLE_NOPASSWD"; then
        log "Skipping sudoers configuration."
        return
    fi
    
    if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
        error "Target user '$TARGET_USER' does not exist."
    fi
    
    assert_script_safe

    local tmp_sudo quoted_path_for_sudoers
    tmp_sudo="$(mktemp_tracked)"
    
    # FIX: Sudoers Quoting Fix (Correct backslash escaping)
    # Escapes backslashes, spaces, and common special/meta-characters used in sudoers rules
    quoted_path_for_sudoers="$(printf '%s' "$SCRIPT_PATH" | \
        sed -e 's/\\/\\\\/g' \
            -e 's/ /\\ /g' \
            -e 's/[\!\@\#\$\%\^\&\*\(\)\{\}\[\]\:\;\|\<\>\,\?\~]/\\&/g')"
    
    log "Writing NOPASSWD rule for $TARGET_USER to $SUDOERS_TARGET..."
    
    # The rule must use the backslash-escaped path
    printf '%s ALL=(root) NOPASSWD: %s\n' "$TARGET_USER" "$quoted_path_for_sudoers" > "$tmp_sudo"
    
    if visudo -cf "$tmp_sudo"; then
        write_if_changed "$tmp_sudo" "$SUDOERS_TARGET" 440
    else
        error "Generated sudoers rule is invalid. Aborting."
    fi
}

configure_unattended() {
    local tmp_50 tmp_20 extra_origins_lines=""
    
    tmp_50="$(mktemp_tracked)"
    log "Configuring ${APT_CONF_DIR}/50unattended-upgrades..."

    # Build extra origins block for non-default repos (e.g., linux.abitti.fi:ytl-linux)
    if [[ -n "${ALLOWED_EXTRA_ORIGINS:-}" ]]; then
        while IFS= read -r origin; do
            [[ -z "$origin" ]] && continue
            extra_origins_lines+="    \"${origin}\";\n"
        done <<< "${ALLOWED_EXTRA_ORIGINS}"
    fi

    cat > "$tmp_50" <<-EOF
Unattended-Upgrade::Allowed-Origins {
    "${DISTRO_ORIGIN}:${DISTRO_CODENAME}";
    "${DISTRO_ORIGIN}:${DISTRO_CODENAME}-security";
    "${DISTRO_ORIGIN}:${DISTRO_CODENAME}-updates";
$(printf '%b' "$extra_origins_lines")
};
Unattended-Upgrade::Package-Blacklist {};
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "true";
Unattended-Upgrade::Automatic-Reboot-Time "${REBOOT_TIME}";
EOF
    write_if_changed "$tmp_50" "${APT_CONF_DIR}/50unattended-upgrades" 644

    tmp_20="$(mktemp_tracked)"
    log "Configuring ${APT_CONF_DIR}/20auto-upgrades schedule..."
    cat > "$tmp_20" <<-EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
APT::Periodic::Unattended-Upgrade "1";
EOF
    write_if_changed "$tmp_20" "${APT_CONF_DIR}/20auto-upgrades" 644
}

install_extra_packages() {
    log "Checking for additional required packages: $EXTRA_PACKAGES"
    
    # FIX: Set local IFS for correct space-delimited loop iteration
    local IFS=' '
    local pkg_name

    for pkg_name in $EXTRA_PACKAGES; do
        [[ -n "$pkg_name" ]] || continue

        log "Processing package: $pkg_name"
        
        dpkg -s "$pkg_name" >/dev/null 2>&1 && {
            log "Package $pkg_name is already installed. Skipping."
            continue
        }

        if ! apt-cache policy "$pkg_name" | grep -q 'Candidate:'; then
            log "WARNING: Package '$pkg_name' not found in repositories. Installation skipped."
            continue
        fi
        
        log "Installing required package: $pkg_name..."
        if ! apt_retry apt-get install -y "$pkg_name"; then
            error "Failed to install $pkg_name after retries."
        fi
    done
}

# --- Main Execution ---

main() {
    # Pre-flight checks *before* log redirection
    validate_inputs
    check_dependencies

    # Create log directory and redirect all output (stdout and stderr) to log file
    mkdir -p -m 755 "$LOG_DIR" || error "Failed to create log directory: $LOG_DIR"
    exec >"$SETUP_LOG_FILE" 2>&1
    log "--- Starting Unattended Setup (v3.0.0) ---"
    
    

    assert_script_safe 
    detect_distro
    
    [[ -d "$APT_CONF_DIR" ]] || error "$APT_CONF_DIR not found."

    configure_sudoers
    
    log "Updating repository cache..."
    if ! apt_retry apt-get update; then
        error "apt-get update failed."
    fi

    # unattended-upgrade installed here
    log "Installing base upgrade utilities..."
    apt_retry apt-get install -y unattended-upgrades apt-listchanges

    command -v unattended-upgrade >/dev/null || error "unattended-upgrade failed to install."

    configure_unattended
    install_extra_packages

    # Verification Step
    log "Running unattended-upgrade dry-run for verification..."
    if ! unattended-upgrade --dry-run --debug > "${LOG_DIR}/dryrun.log" 2>&1; then
        log "WARNING: Dry-run failed. Check ${LOG_DIR}/dryrun.log for details."
    fi

    log "--- Setup Completed Successfully ---"
}

main "$@"