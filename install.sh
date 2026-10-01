#!/bin/bash
#
# ============================================================================
#  vpn-auto-script v2.0 — one-shot VPN server installer
#  Ubuntu 22.04/24.04 + 3x-ui + Nginx (SNI routing) + Certbot + UFW
#
#  Produces a production-ready server with ZERO manual panel steps:
#    VLESS+Reality | VLESS+WS (CDN) | VLESS+gRPC | VLESS+XHTTP |
#    Hysteria2 | Shadowsocks 2022 | TUIC
#
#  USAGE:
#    git clone https://github.com/R4in8ow/vpn-auto-script.git
#    cd vpn-auto-script
#    sudo bash install.sh
#
#  Non-interactive (reads every value from .env, never prompts):
#    cp .env.example .env   # fill it in
#    sudo bash install.sh --non-interactive
#
#  Flags:
#    --env-file PATH     use a different env file instead of ./.env
#    --non-interactive   fail instead of prompting for missing values
#    --no-sni-routing    classic layout: nginx HTTPS directly on public 443
#                        (default: SNI-routing layout, see docs/ARCHITECTURE.md)
#    -h, --help          show this help
#
#  No domains, passwords, IPs or keys are hardcoded anywhere in this repo.
#  Everything is asked interactively or read from your own .env file.
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/common.sh"
# shellcheck disable=SC1091
. "$SCRIPT_DIR/lib/inbounds.sh"

# --- CLI flags ----------------------------------------------------------------
ENV_FILE="$SCRIPT_DIR/.env"
NONINTERACTIVE=0
SNI_ROUTING=yes
NO_SNI_FLAG=0

usage() { sed -n '/^#  vpn-auto-script/,/^# ==*$/p' "$0" | sed 's/^# \{0,1\}//'; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --env-file)        ENV_FILE="$2"; shift 2 ;;
        --non-interactive) NONINTERACTIVE=1; shift ;;
        --no-sni-routing)  NO_SNI_FLAG=1; shift ;;
        -h|--help)         usage; exit 0 ;;
        *) die "Unknown option: $1 (see --help)" ;;
    esac
done
export NONINTERACTIVE

require_root
require_ubuntu

# --- 0. Load .env if present ---------------------------------------------------
if [[ -f "$ENV_FILE" ]]; then
    load_env_file "$ENV_FILE"
else
    info "No env file at $ENV_FILE — running interactively."
fi
# Explicit CLI flag wins over .env for the SNI layout
if [[ "$NO_SNI_FLAG" == "1" ]]; then SNI_ROUTING=no; fi

# --- 1. Welcome ----------------------------------------------------------------
cat << 'BANNER'

==============================================================
   VPN AUTO-INSTALLER  v2.0
   VLESS+Reality / WS / gRPC / XHTTP / Hysteria2 / SS-2022 / TUIC
   3x-ui + Nginx SNI routing + Let's Encrypt + UFW
==============================================================
BANNER

echo ""
echo "Before continuing, create these DNS A records pointing at"
echo "this server's public IP:"
echo "   <panel domain>  -> server IP   (DNS-only / grey-cloud recommended)"
echo "   <cdn domain>    -> server IP   (Proxied / orange-cloud is OK)"
echo ""
if [[ "$NONINTERACTIVE" != "1" ]]; then
    read -rp "Press Enter once DNS is in place, or Ctrl+C to abort... "
fi

# --- 2. Configuration ----------------------------------------------------------
validate_domain() {
    [[ "$1" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]
}

step "Configuration"

prompt_with_default PANEL_DOMAIN "Panel domain (e.g. panel.example.com)" ""
prompt_with_default CDN_DOMAIN   "CDN domain (e.g. cdn.example.com)" ""
prompt_with_default SUB_DOMAIN   "Subscription domain (Enter = same as panel domain)" "$PANEL_DOMAIN"
prompt_with_default LE_EMAIL     "Email for Let's Encrypt notices" ""

for d in PANEL_DOMAIN CDN_DOMAIN SUB_DOMAIN; do
    validate_domain "${!d}" || die "Invalid domain name: ${!d}"
done
[[ "$LE_EMAIL" =~ ^[^[:space:]]+@[^[:space:]]+\.[^[:space:]]+$ ]] \
    || die "Invalid email address: $LE_EMAIL"

prompt_with_default PANEL_PORT   "x-ui panel port" "2053"
prompt_with_default SUB_PORT     "Subscription service port" "2096"
prompt_with_default REALITY_PORT "Reality inbound port (TCP)" "36878"
prompt_with_default WS_PORT      "VLESS+WS inbound port (TCP)" "8443"
prompt_with_default GRPC_PORT    "VLESS+gRPC inbound port (TCP)" "2087"
prompt_with_default XHTTP_PORT   "VLESS+XHTTP inbound port (TCP)" "2089"
prompt_with_default HY2_PORT     "Hysteria2 inbound port (UDP)" "40797"
prompt_with_default SS_PORT      "Shadowsocks inbound port (TCP+UDP)" "58023"
prompt_with_default TUIC_PORT    "TUIC inbound port (UDP)" "443"
prompt_with_default REALITY_DEST "Reality dest (host:port)" "web.dev:443"
prompt_with_default REALITY_SNI  "Reality SNI / serverName" "web.dev"

prompt_with_default ADMIN_USER "Panel admin username" "admin"
prompt_secret ADMIN_PASS "Panel admin password"

if [[ "$SNI_ROUTING" == "yes" ]]; then
    SNI_MODE_TXT="SNI routing (public 443 -> Reality or web by SNI)"
else
    SNI_MODE_TXT="classic (nginx HTTPS directly on public 443)"
fi

# Optional extras
if [[ -z "${INSTALL_FAIL2BAN:-}" ]]; then
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        INSTALL_FAIL2BAN="no"
    else
        confirm "Install fail2ban (SSH brute-force protection)?" "n" \
            && INSTALL_FAIL2BAN="yes" || INSTALL_FAIL2BAN="no"
    fi
fi
if [[ -z "${UFW_DEFAULT_DENY:-}" ]]; then
    if [[ "$NONINTERACTIVE" == "1" ]]; then
        UFW_DEFAULT_DENY="no"
    else
        echo ""
        echo "UFW default policy: 'deny incoming' is the secure choice, but it"
        echo "will block anything you did not explicitly allow below."
        confirm "Set UFW default policy to DENY incoming?" "n" \
            && UFW_DEFAULT_DENY="yes" || UFW_DEFAULT_DENY="no"
    fi
fi

# --- 3. Review -----------------------------------------------------------------
step "Review"
cat << REVIEW
  Panel domain      : $PANEL_DOMAIN
  CDN domain        : $CDN_DOMAIN
  Subscription dom. : $SUB_DOMAIN
  LE email          : $LE_EMAIL
  Panel port        : $PANEL_PORT      Sub port: $SUB_PORT
  Reality           : $REALITY_PORT/tcp   (dest $REALITY_DEST, SNI $REALITY_SNI)
  VLESS+WS          : $WS_PORT/tcp        VLESS+gRPC : $GRPC_PORT/tcp
  VLESS+XHTTP       : $XHTTP_PORT/tcp     Hysteria2  : $HY2_PORT/udp
  Shadowsocks 2022  : $SS_PORT/tcp+udp    TUIC       : $TUIC_PORT/udp
  Admin user        : $ADMIN_USER         (password hidden, ${#ADMIN_PASS} chars)
  Layout            : $SNI_MODE_TXT
  fail2ban          : $INSTALL_FAIL2BAN   UFW default deny: $UFW_DEFAULT_DENY
REVIEW
echo ""
if [[ "$NONINTERACTIVE" != "1" ]]; then
    read -rp "Proceed with installation? [y/N]: " CONFIRM
    [[ "${CONFIRM,,}" == "y" ]] || { echo "Aborted."; exit 0; }
fi

# --- 4. System update + tuning ---------------------------------------------------
step "System update + kernel tuning"
apt update -y && apt upgrade -y

info "Applying BBR + network tuning (generic BBR)..."
append_once /etc/sysctl.conf "# vpn-auto-script tuning" "$(cat << 'EOF'
# vpn-auto-script tuning
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_keepalive_time=90
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_fastopen=3
fs.file-max=65535000
EOF
)"
sysctl -p >/dev/null 2>&1 || true

info "Raising file descriptor / process limits..."
append_once /etc/security/limits.conf "# vpn-auto-script limits" "$(cat << 'EOF'
# vpn-auto-script limits
* soft nproc 655350
* hard nproc 655350
* soft nofile 655350
* hard nofile 655350
root soft nproc 655350
root hard nproc 655350
root soft nofile 655350
root hard nofile 655350
EOF
)"

# --- 5. Swapfile (4G) ------------------------------------------------------------
step "Swapfile"
if swapon --show 2>/dev/null | grep -q .; then
    info "Swap already active, skipping."
else
    info "Creating 4G swapfile..."
    if ! fallocate -l 4G /swapfile 2>/dev/null; then
        dd if=/dev/zero of=/swapfile bs=1M count=4096 status=none
    fi
    chmod 600 /swapfile
    mkswap /swapfile >/dev/null
    swapon /swapfile
    grep -q '^/swapfile ' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
    info "Swap active: $(free -h | awk '/Swap:/ {print $2}')"
fi

# --- 6. Base packages --------------------------------------------------------------
step "Installing base packages"
apt install -y nginx certbot sqlite3 ufw curl jq openssl socat cron
if [[ "$INSTALL_FAIL2BAN" == "yes" ]]; then
    apt install -y fail2ban
fi

# unattended security upgrades
apt install -y unattended-upgrades
if [[ ! -f /etc/apt/apt.conf.d/20auto-upgrades ]]; then
    cat > /etc/apt/apt.conf.d/20auto-upgrades << 'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
EOF
fi

# nginx must have the stream module for SNI routing
if [[ "$SNI_ROUTING" == "yes" ]]; then
    if ! nginx -V 2>&1 | grep -qi 'stream'; then
        die "Installed nginx lacks the stream module, required for SNI routing. Re-run with --no-sni-routing."
    fi
    info "nginx stream module present."
fi

systemctl enable --now nginx

# --- 7. Firewall -------------------------------------------------------------------
step "Firewall (UFW)"
ufw allow OpenSSH >/dev/null
ufw allow 22/tcp >/dev/null
ufw allow 80/tcp >/dev/null
ufw allow 443/tcp >/dev/null
ufw allow 443/udp >/dev/null
for p in "$PANEL_PORT" "$SUB_PORT" "$REALITY_PORT" "$WS_PORT" "$GRPC_PORT" "$XHTTP_PORT"; do
    ufw allow "${p}/tcp" >/dev/null
done
ufw allow "${HY2_PORT}/udp" >/dev/null
ufw allow "${SS_PORT}/tcp" >/dev/null
ufw allow "${SS_PORT}/udp" >/dev/null
if [[ "$UFW_DEFAULT_DENY" == "yes" ]]; then
    ufw default deny incoming >/dev/null
    info "UFW default policy: deny incoming."
else
    info "UFW default policy left unchanged."
fi
echo "y" | ufw enable >/dev/null
ufw status numbered | head -30

# --- 8. nginx phase 1: port-80 stubs for ACME webroot -------------------------------
step "nginx phase 1 (ACME challenge stubs)"
mkdir -p /var/www/html
write_phase1() {
    local domain="$1"
    cat > "/etc/nginx/sites-available/${domain}" << EOF
# Phase 1 (ACME) — replaced with the full config after certs are issued.
server {
    listen 80;
    listen [::]:80;
    server_name ${domain};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
    ln -sf "/etc/nginx/sites-available/${domain}" /etc/nginx/sites-enabled/
}
write_phase1 "$PANEL_DOMAIN"
if [[ "$CDN_DOMAIN" != "$PANEL_DOMAIN" ]]; then
    write_phase1 "$CDN_DOMAIN"
fi
rm -f /etc/nginx/sites-enabled/default

if [[ "$SNI_ROUTING" == "yes" ]]; then
    info "Installing nginx stream SNI router (public 443)..."
    cat > /etc/nginx/stream.conf << EOF
# vpn-auto-script: route public TCP/443 by TLS SNI (ssl_preread, no termination).
stream {
    map \$ssl_preread_server_name \$sni_backend {
        ${REALITY_SNI} 127.0.0.1:${REALITY_PORT};
        default        127.0.0.1:4443;
    }
    server {
        listen 443;
        listen [::]:443;
        proxy_pass \$sni_backend;
        ssl_preread on;
        proxy_connect_timeout 10s;
    }
}
EOF
    backup_file /etc/nginx/nginx.conf
    grep -q 'include /etc/nginx/stream.conf;' /etc/nginx/nginx.conf \
        || printf '\ninclude /etc/nginx/stream.conf;\n' >> /etc/nginx/nginx.conf
fi

nginx -t && systemctl reload nginx

# --- 9. TLS certificates (webroot — nginx keeps running) ---------------------------
step "Issuing Let's Encrypt certificates (webroot, zero downtime)"
issue_cert() {
    local domain="$1"
    if [[ -f "/etc/letsencrypt/live/${domain}/fullchain.pem" ]] \
        && openssl x509 -checkend 2592000 -noout \
            -in "/etc/letsencrypt/live/${domain}/fullchain.pem" 2>/dev/null; then
        info "Existing valid cert for $domain (30+ days left), skipping issuance."
        return 0
    fi
    certbot certonly --webroot -w /var/www/html \
        --non-interactive --agree-tos -m "$LE_EMAIL" \
        --deploy-hook "systemctl reload nginx" \
        -d "$domain" || {
        error "Certbot failed for $domain."
        error "Check that its DNS A record points at this server, then run manually:"
        error "  certbot certonly --webroot -w /var/www/html -d $domain"
        return 1
    }
}
CERT_OK=1
issue_cert "$PANEL_DOMAIN" || CERT_OK=0
if [[ "$CDN_DOMAIN" != "$PANEL_DOMAIN" ]]; then
    issue_cert "$CDN_DOMAIN" || CERT_OK=0
fi
if [[ "$CERT_OK" != "1" ]]; then
    die "Certificate issuance failed. Fix DNS and re-run the script (it is safe to re-run)."
fi
systemctl enable --now certbot.timer 2>/dev/null || true

# --- 10. Install 3x-ui ---------------------------------------------------------------
step "Installing 3x-ui panel"
if [[ -d /usr/local/x-ui ]]; then
    warn "x-ui already installed, skipping download."
else
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) <<< $'\n'
fi
X_UI_DB="/etc/x-ui/x-ui.db"
if [[ ! -f "$X_UI_DB" ]]; then
    warn "x-ui database not found yet, initializing..."
    timeout 5 /usr/local/x-ui/x-ui run >/dev/null 2>&1 || true
    sleep 2
    pkill -f "/usr/local/x-ui/x-ui run" >/dev/null 2>&1 || true
fi
[[ -f "$X_UI_DB" ]] || die "x-ui database still missing at $X_UI_DB"

# --- 11. Panel settings ----------------------------------------------------------------
step "Configuring x-ui panel settings"
systemctl stop x-ui || true

/usr/local/x-ui/x-ui setting -username "$ADMIN_USER" -password "$ADMIN_PASS" >/dev/null \
    || die "Failed to set panel admin credentials via 'x-ui setting'."
/usr/local/x-ui/x-ui setting -port "$PANEL_PORT" >/dev/null \
    || die "Failed to set panel port via 'x-ui setting'."
/usr/local/x-ui/x-ui setting -webBasePath "/panel/" >/dev/null \
    || die "Failed to set webBasePath via 'x-ui setting'."

# Remaining keys via SQL with DELETE+INSERT (the settings table has no
# PRIMARY KEY on `key`, so INSERT OR REPLACE would create duplicates).
db_set() {
    sqlite3 "$X_UI_DB" \
        "DELETE FROM settings WHERE key='$1'; INSERT INTO settings (key, value) VALUES ('$1', '$2');"
}
db_set "webCertFile" "/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem"
db_set "webKeyFile"  "/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem"
db_set "subEnable"   "true"
db_set "subPort"     "$SUB_PORT"
db_set "subPath"     "/sub/"
db_set "subURI"      "https://${SUB_DOMAIN}/sub/"
db_set "subDomain"   "$SUB_DOMAIN"

info "Verifying saved settings..."
sqlite3 "$X_UI_DB" "SELECT key, value FROM settings WHERE key IN \
    ('webPort','webBasePath','subEnable','subPort','subPath','subURI','subDomain');"

systemctl enable --now x-ui
sleep 3

# --- 12. Generate per-install secrets --------------------------------------------------
step "Generating fresh keys / credentials"
if [[ -x /usr/local/x-ui/bin/xray-linux-amd64 ]]; then
    REALITY_OUT="$("/usr/local/x-ui/bin/xray-linux-amd64" x25519)"
    REALITY_PRIVKEY="$(echo "$REALITY_OUT" | awk '/PrivateKey/ {print $2}')"
    REALITY_PUBKEY="$(echo "$REALITY_OUT" | awk '/Password/ {print $2}')"
    [[ -n "$REALITY_PRIVKEY" && -n "$REALITY_PUBKEY" ]] \
        || die "Failed to parse xray x25519 output."
else
    die "xray binary not found at /usr/local/x-ui/bin/xray-linux-amd64"
fi
REALITY_SHORTID="$(gen_hex 8)"
UUID_REALITY="$(gen_uuid)"; UUID_WS="$(gen_uuid)"
UUID_GRPC="$(gen_uuid)";    UUID_XHTTP="$(gen_uuid)"
HY2_PASSWORD="$(gen_password 16 | tr -d '/+=' | cut -c1-16)"
TUIC_PASSWORD="$(gen_password 16 | tr -d '/+=' | cut -c1-16)"
SS_PASSWORD="$(openssl rand -base64 16 | tr -d '\n')"  # 16 bytes, 2022-blake3-aes-128-gcm
info "Keys generated (private key never leaves this server)."

# --- 13. Detect whether the panel serves HTTP or HTTPS ----------------------------------
step "Probing panel protocol"
# The panel may serve plain HTTP or HTTPS on webPort depending on version
# and cert settings — probe both and use whatever answers.
probe_panel() {
    local code
    code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 5 \
        "https://127.0.0.1:${PANEL_PORT}/panel/login" 2>/dev/null || echo "000")
    if [[ "$code" != "000" ]]; then echo "https"; return 0; fi
    code=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 \
        "http://127.0.0.1:${PANEL_PORT}/panel/login" 2>/dev/null || echo "000")
    if [[ "$code" != "000" ]]; then echo "http"; return 0; fi
    echo ""
}
PANEL_SCHEME="$(probe_panel)"
[[ -n "$PANEL_SCHEME" ]] || die "Panel is not responding on 127.0.0.1:${PANEL_PORT} (tried http and https)."
info "Panel speaks ${PANEL_SCHEME} on 127.0.0.1:${PANEL_PORT}"
export PANEL_SCHEME

# --- 14. Create all 7 inbounds via the panel REST API -------------------------------------
step "Creating inbounds via panel API"
xui_login || die "Panel API login failed — check admin credentials, then re-run."
create_all_inbounds
verify_tuic_congestion || true

if [[ ${#INBOUND_FAILURES[@]} -gt 0 ]]; then
    warn "These inbounds could NOT be created automatically: ${INBOUND_FAILURES[*]}"
    warn "Create them manually in the panel; the failed payloads are logged above."
else
    info "All 7 inbounds created."
fi

# Restart Xray so every new inbound is live, and confirm it stayed up.
xui_restart_xray \
    || warn "Xray did not report 'running' — check the panel UI and docs/TROUBLESHOOTING.md."

# --- 15. nginx phase 2: final vhosts -------------------------------------------------------
step "nginx phase 2 (final vhosts)"

# In SNI mode nginx only serves HTTPS on 127.0.0.1:4443 (public 443 is
# owned by the stream SNI router). In classic mode it serves 443 directly.
if [[ "$SNI_ROUTING" == "yes" ]]; then
    HTTPS_LISTEN="listen 127.0.0.1:4443 ssl;"
else
    HTTPS_LISTEN="listen 443 ssl;
    listen [::]:443 ssl;"
fi

if [[ "$PANEL_SCHEME" == "https" ]]; then
    PANEL_PROXY="proxy_pass https://127.0.0.1:${PANEL_PORT}/panel/;"
    PANEL_PROXY_SSL="proxy_ssl_verify off;"
else
    PANEL_PROXY="proxy_pass http://127.0.0.1:${PANEL_PORT}/panel/;"
    PANEL_PROXY_SSL=""
fi

cat > "/etc/nginx/sites-available/${PANEL_DOMAIN}" << EOF
# vpn-auto-script v2.0 — panel domain
server {
    ${HTTPS_LISTEN}
    server_name ${PANEL_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # x-ui panel (webBasePath=/panel/)
    location /panel/ {
        ${PANEL_PROXY}
        ${PANEL_PROXY_SSL}
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # 3x-ui subscription service
    location / {
        proxy_pass http://127.0.0.1:${SUB_PORT};
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${PANEL_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF

if [[ "$CDN_DOMAIN" != "$PANEL_DOMAIN" ]]; then
    cat > "/etc/nginx/sites-available/${CDN_DOMAIN}" << EOF
# vpn-auto-script v2.0 — CDN domain (TLS terminated here, plain WS/XHTTP upstream)
server {
    ${HTTPS_LISTEN}
    server_name ${CDN_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${CDN_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CDN_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    # VLESS+WS (inbound security=none — nginx already terminated TLS)
    location /vless {
        proxy_pass http://127.0.0.1:${WS_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    # VLESS+XHTTP
    location /xhttp {
        proxy_pass http://127.0.0.1:${XHTTP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }

    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 404; }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${CDN_DOMAIN};
    location /.well-known/acme-challenge/ { root /var/www/html; }
    location / { return 301 https://\$host\$request_uri; }
}
EOF
fi

nginx -t && systemctl reload nginx

# --- 16. Post-install self-test ------------------------------------------------------------------
step "Post-install self-test"
TEST_FAILS=0
t_ok()   { echo -e "  ${GREEN}PASS${NC} $1"; }
t_fail() { echo -e "  ${RED}FAIL${NC} $1"; TEST_FAILS=$((TEST_FAILS+1)); }

# 1. Panel reachable over public HTTPS
code=$(curl -sk -o /dev/null -w "%{http_code}" --max-time 10 \
    "https://${PANEL_DOMAIN}/panel/login" || echo "000")
[[ "$code" != "000" ]] && t_ok "panel HTTPS reachable (HTTP $code)" \
    || t_fail "panel HTTPS not reachable via https://${PANEL_DOMAIN}/panel/"

# 2. TCP ports listening
for p in 443 "$PANEL_PORT" "$SUB_PORT" "$REALITY_PORT" "$WS_PORT" \
         "$GRPC_PORT" "$XHTTP_PORT" "$SS_PORT"; do
    if ss -tln 2>/dev/null | grep -q ":${p} "; then
        t_ok "TCP port $p listening"
    else
        t_fail "TCP port $p NOT listening"
    fi
done
[[ "$SNI_ROUTING" == "yes" ]] && {
    ss -tln 2>/dev/null | grep -q ":4443 " \
        && t_ok "TCP port 4443 listening (SNI backend)" \
        || t_fail "TCP port 4443 NOT listening"
}

# 3. UDP ports listening
for p in 443 "$HY2_PORT" "$SS_PORT"; do
    if ss -uln 2>/dev/null | grep -q ":${p} "; then
        t_ok "UDP port $p listening"
    else
        t_fail "UDP port $p NOT listening"
    fi
done

# 4. Certificates valid
for d in "$PANEL_DOMAIN" "$CDN_DOMAIN"; do
    if openssl x509 -checkend 0 -noout \
        -in "/etc/letsencrypt/live/${d}/fullchain.pem" 2>/dev/null; then
        t_ok "certificate valid: $d"
    else
        t_fail "certificate problem: $d"
    fi
done

# 5. Xray running + inbound count
xray_state="$(xui_get "/server/status" 2>/dev/null | jq -r '.obj.xray.state // "unknown"' 2>/dev/null || true)"
[[ -z "$xray_state" ]] && xray_state="unknown"
[[ "$xray_state" == "running" ]] && t_ok "xray core running" \
    || t_fail "xray core state: $xray_state"
inbound_count="$(xui_get "/inbounds/list" 2>/dev/null | jq '.obj | length' 2>/dev/null || true)"
if [[ "$inbound_count" == "7" ]]; then
    t_ok "7/7 inbounds present in panel"
else
    t_fail "inbound count = ${inbound_count:-?} (expected 7)"
fi

# 6. BBR active
sysctl -n net.ipv4.tcp_congestion_control 2>/dev/null | grep -q bbr \
    && t_ok "BBR congestion control active" \
    || t_fail "BBR not active"

if [[ "$TEST_FAILS" -gt 0 ]]; then
    warn "$TEST_FAILS self-test check(s) failed — see docs/TROUBLESHOOTING.md."
else
    info "All self-test checks passed."
fi
rm -f "$XUI_COOKIE_JAR"

# --- 17. Save credentials + summary -----------------------------------------------------------------
CRED_FILE="/root/vpn-credentials.env"
{
    echo "# Generated by vpn-auto-script v2.0 on $(date -u +%FT%TZ)"
    echo "# KEEP THIS FILE PRIVATE (chmod 600)."
    echo "PANEL_URL=https://${PANEL_DOMAIN}/panel/"
    echo "ADMIN_USER=${ADMIN_USER}"
    echo "ADMIN_PASS=${ADMIN_PASS}"
    echo "SUB_BASE=https://${SUB_DOMAIN}/sub/"
    echo "REALITY_UUID=${UUID_REALITY}"
    echo "REALITY_PUBKEY=${REALITY_PUBKEY}"
    echo "REALITY_SHORTID=${REALITY_SHORTID}"
    echo "WS_UUID=${UUID_WS}"
    echo "GRPC_UUID=${UUID_GRPC}"
    echo "XHTTP_UUID=${UUID_XHTTP}"
    echo "HY2_PASSWORD=${HY2_PASSWORD}"
    echo "TUIC_PASSWORD=${TUIC_PASSWORD}"
    echo "SS_PASSWORD=${SS_PASSWORD}"
    echo "SS_METHOD=2022-blake3-aes-128-gcm"
} > "$CRED_FILE"
chmod 600 "$CRED_FILE"

SERVER_IP=$(curl -s -4 --max-time 10 ifconfig.me || hostname -I | awk '{print $1}')

cat << SUMMARY

==============================================================
 INSTALLATION COMPLETE  (v2.0)
==============================================================
 Server IP        : ${SERVER_IP}
 Panel URL        : https://${PANEL_DOMAIN}/panel/
 Admin user       : ${ADMIN_USER}
 Admin password   : (the one you entered — also saved in ${CRED_FILE})
 Subscription base: https://${SUB_DOMAIN}/sub/

 Inbounds (all created automatically):
   Reality      ${REALITY_PORT}/tcp   vless  (SNI ${REALITY_SNI}, uTLS chrome)
   CDN-Vless    ${WS_PORT}/tcp        vless+ws   path /vless
   CDN-gRPC     ${GRPC_PORT}/tcp      vless+grpc service vless-grpc (TLS)
   XHTTP        ${XHTTP_PORT}/tcp     vless+xhttp path /xhttp
   Hysteria2    ${HY2_PORT}/udp       hysteria2 (TLS)
   Outline      ${SS_PORT}/tcp+udp    shadowsocks 2022-blake3-aes-128-gcm
   TUIC         ${TUIC_PORT}/udp      tuic (TLS, bbr)

 Reality public key (for client configs):
   ${REALITY_PUBKEY}
 Reality shortId: ${REALITY_SHORTID}

 Credentials for every inbound were saved to:
   ${CRED_FILE}   (root-only, mode 600 — back it up securely)

------------------------------------------------------------
 KNOWN LIMITATION (honest note):
------------------------------------------------------------
 The subscription service currently exposes Reality's DIRECT port
 (${REALITY_PORT}). If you route Reality through public 443 via the
 SNI router, clients should use port 443 for that inbound — rewrite
 the port in the client app, or see the roadmap in README.md for the
 planned server-side sanitization.

------------------------------------------------------------
 CLOUD FIREWALL REMINDER:
------------------------------------------------------------
 ufw is configured, but your provider's network firewall (DigitalOcean
 Cloud Firewall / AWS Security Group / etc.) is SEPARATE — allow the
 same TCP/UDP ports there or connections will silently time out.

 Docs: docs/ARCHITECTURE.md  docs/TROUBLESHOOTING.md
 To remove everything: sudo bash uninstall.sh
==============================================================
SUMMARY
