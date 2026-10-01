#!/bin/bash
#
# ============================================================================
#  vpn-auto-script — uninstaller
#
#  Stops and removes everything install.sh created:
#    x-ui panel + database, nginx vhost/stream configs written by the
#    installer, UFW rules for the VPN ports, and (optionally) the
#    Let's Encrypt certificates and the swapfile.
#
#  USAGE:  sudo bash uninstall.sh [--yes]
#  Every destructive step asks first unless --yes is given.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"

AUTO_YES=0
[[ "${1:-}" == "--yes" ]] && AUTO_YES=1

require_root

ask() {
    # ask "question" -> 0 = yes
    if [[ "$AUTO_YES" == "1" ]]; then return 0; fi
    confirm "$1" "n"
}

step "vpn-auto-script uninstaller"
warn "This will remove the VPN server components installed by install.sh."
ask "Continue?" || { echo "Aborted."; exit 0; }

# --- 1. x-ui --------------------------------------------------------------------
if systemctl list-unit-files 2>/dev/null | grep -q '^x-ui'; then
    info "Stopping/disabling x-ui..."
    systemctl stop x-ui || true
    systemctl disable x-ui || true
fi
if [[ -d /usr/local/x-ui ]]; then
    if ask "Delete /usr/local/x-ui (panel binaries)?"; then
        rm -rf /usr/local/x-ui
        info "Removed /usr/local/x-ui."
    fi
fi
if [[ -d /etc/x-ui ]]; then
    if ask "Delete /etc/x-ui (panel database — ALL inbounds/clients/settings)?"; then
        backup_file /etc/x-ui/x-ui.db 2>/dev/null || cp -a /etc/x-ui/x-ui.db /root/x-ui.db.uninstall-backup 2>/dev/null || true
        info "Database backed up to /root/x-ui.db.uninstall-backup (if it existed)."
        rm -rf /etc/x-ui
        info "Removed /etc/x-ui."
    fi
fi

# --- 2. nginx configs ---------------------------------------------------------------
for f in /etc/nginx/sites-enabled/* /etc/nginx/sites-available/*; do
    [[ -L "$f" || -f "$f" ]] || continue
    # Only touch vhosts that carry our marker comment
    if grep -q 'vpn-auto-script' "$f" 2>/dev/null; then
        info "Removing nginx site: $f"
        rm -f "$f"
    fi
done
if [[ -f /etc/nginx/stream.conf ]] && grep -q 'vpn-auto-script' /etc/nginx/stream.conf; then
    info "Removing /etc/nginx/stream.conf (SNI router)."
    rm -f /etc/nginx/stream.conf
    if grep -q 'include /etc/nginx/stream.conf;' /etc/nginx/nginx.conf; then
        sed -i '\|include /etc/nginx/stream.conf;|d' /etc/nginx/nginx.conf
        info "Removed stream include from nginx.conf."
    fi
fi
if nginx -t 2>/dev/null; then
    systemctl reload nginx || true
else
    warn "nginx -t reports errors after cleanup — review /etc/nginx manually."
fi

# --- 3. UFW rules ---------------------------------------------------------------------
if command -v ufw >/dev/null && ufw status 2>/dev/null | grep -q 'Status: active'; then
    if ask "Remove UFW rules for VPN ports (keeps SSH/80/443)?"; then
        for rule in 443/udp 2053/tcp 2096/tcp 36878/tcp 8443/tcp 2087/tcp \
                    2089/tcp 40797/udp 58023/tcp 58023/udp; do
            ufw delete allow "$rule" >/dev/null 2>&1 || true
        done
        info "VPN port rules removed."
    fi
fi

# --- 4. Certificates (optional) ----------------------------------------------------------
if [[ -d /etc/letsencrypt ]]; then
    if ask "Delete Let's Encrypt certificates in /etc/letsencrypt?"; then
        rm -rf /etc/letsencrypt
        info "Removed /etc/letsencrypt."
    else
        info "Certificates kept."
    fi
fi

# --- 5. Swapfile (optional) ---------------------------------------------------------------
if [[ -f /swapfile ]] && grep -q '^/swapfile ' /etc/fstab 2>/dev/null; then
    if ask "Disable and remove the /swapfile created by the installer?"; then
        swapoff /swapfile || true
        sed -i '\|^/swapfile |d' /etc/fstab
        rm -f /swapfile
        info "Swapfile removed."
    fi
fi

# --- 6. Credentials file ------------------------------------------------------------------
if [[ -f /root/vpn-credentials.env ]]; then
    if ask "Delete /root/vpn-credentials.env (generated passwords/keys)?"; then
        shred -u /root/vpn-credentials.env 2>/dev/null || rm -f /root/vpn-credentials.env
        info "Credentials file destroyed."
    else
        warn "Kept /root/vpn-credentials.env — delete it manually when no longer needed."
    fi
fi

cat << DONE

==============================================================
 UNINSTALL COMPLETE
==============================================================
 Removed: x-ui, installer nginx configs, VPN UFW rules
 Kept (by your choice or by default):
   - nginx itself + any non-installer vhosts
   - UFW SSH/80/443 rules
   - system tuning in /etc/sysctl.conf and /etc/security/limits.conf
     (marked with 'vpn-auto-script' comments — remove manually if wanted)
   - unattended-upgrades, fail2ban (if installed)
DONE
