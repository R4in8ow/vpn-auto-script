#!/bin/bash
# ============================================================================
# lib/common.sh — shared helpers for the vpn-auto-script installer
# Sourced by install.sh and uninstall.sh. Not meant to be run directly.
# ============================================================================

# --- Colors / logging --------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*" >&2; }
die()   { error "$*"; exit 1; }
step()  { echo -e "\n${BOLD}== $* ==${NC}"; }

# --- Preconditions -----------------------------------------------------------
require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root. Try: sudo bash $0"
    fi
}

require_ubuntu() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        if [[ "${ID:-}" != "ubuntu" ]]; then
            warn "This installer targets Ubuntu (detected: ${PRETTY_NAME:-unknown}). Continuing anyway."
        elif [[ "${VERSION_ID:-}" != "24.04" && "${VERSION_ID:-}" != "22.04" ]]; then
            warn "Tested on Ubuntu 22.04/24.04 (detected: ${VERSION_ID:-unknown}). Continuing anyway."
        fi
    fi
}

# --- .env handling -----------------------------------------------------------
# Loads KEY=VALUE pairs from a .env file if present. Values already exported
# in the environment take precedence over the file.
load_env_file() {
    local env_file="$1"
    if [[ -f "$env_file" ]]; then
        info "Loading configuration from $env_file"
        set -a
        # shellcheck disable=SC1090
        . "$env_file"
        set +a
        return 0
    fi
    return 1
}

# --- Interactive prompts -----------------------------------------------------
# prompt_with_default VAR "Question" "default"
#   Uses $VAR if already set (from .env/env), otherwise asks interactively.
#   In non-interactive mode (NONINTERACTIVE=1), dies if $VAR is unset and no
#   default is acceptable.
prompt_with_default() {
    local var_name="$1" question="$2" default="$3"
    local current="${!var_name:-}"
    if [[ -n "$current" ]]; then
        return 0
    fi
    if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
        if [[ -n "$default" ]]; then
            printf -v "$var_name" '%s' "$default"
            return 0
        fi
        die "Non-interactive mode: required variable $var_name is not set (check your .env file)."
    fi
    local answer
    if [[ -n "$default" ]]; then
        read -rp "$question [$default]: " answer
        printf -v "$var_name" '%s' "${answer:-$default}"
    else
        while true; do
            read -rp "$question: " answer
            if [[ -n "$answer" ]]; then
                printf -v "$var_name" '%s' "$answer"
                break
            fi
            warn "Value cannot be empty."
        done
    fi
}

# prompt_secret VAR "Question" — like above but silent input, min length 8.
prompt_secret() {
    local var_name="$1" question="$2"
    local current="${!var_name:-}"
    if [[ -n "$current" ]]; then
        return 0
    fi
    if [[ "${NONINTERACTIVE:-0}" == "1" ]]; then
        die "Non-interactive mode: required secret $var_name is not set (check your .env file)."
    fi
    local pw1 pw2
    while true; do
        read -rsp "$question (min 8 chars): " pw1; echo ""
        if [[ ${#pw1} -lt 8 ]]; then
            warn "Too short, use at least 8 characters."
            continue
        fi
        read -rsp "Confirm: " pw2; echo ""
        if [[ "$pw1" != "$pw2" ]]; then
            warn "Passwords did not match, try again."
            continue
        fi
        printf -v "$var_name" '%s' "$pw1"
        break
    done
}

# confirm "Question" "default(y/n)" -> returns 0 on yes
confirm() {
    local question="$1" default="${2:-n}"
    local hint="[y/N]" def_no=0
    if [[ "$default" == "y" ]]; then hint="[Y/n]"; def_no=1; fi
    # Allow pre-seeding via env, e.g. CONFIRM_X=yes
    local answer
    read -rp "$question $hint: " answer
    answer="${answer:-$default}"
    if [[ "$def_no" == "1" ]]; then
        [[ "${answer,,}" != "n" ]]
    else
        [[ "${answer,,}" == "y" ]]
    fi
}

# --- Idempotent file helpers -------------------------------------------------
# append_once FILE MARKER_LINE CONTENT — appends CONTENT only if MARKER_LINE
# is not already present in FILE.
append_once() {
    local file="$1" marker="$2" content="$3"
    touch "$file"
    if ! grep -qF "$marker" "$file"; then
        printf '%s\n' "$content" >> "$file"
    fi
}

backup_file() {
    local file="$1"
    if [[ -f "$file" && ! -f "${file}.bak-vpn-installer" ]]; then
        cp -a "$file" "${file}.bak-vpn-installer"
        info "Backed up $file -> ${file}.bak-vpn-installer"
    fi
}

# --- Random credential generators (never logged) -----------------------------
gen_uuid()    { cat /proc/sys/kernel/random/uuid; }
gen_hex()     { openssl rand -hex "$1"; }          # gen_hex 8 -> 16 hex chars
gen_password(){ openssl rand -base64 "$1" | tr -d '\n'; }  # base64
