#!/bin/bash
#
# ============================================================================
#  X-UI VPN Server Auto-Installer
#  Stack: Ubuntu 22.04/24.04 + x-ui (3x-ui) + Nginx + Certbot + UFW
#  Protocols: VLESS+Reality, VLESS+WS (CDN-ready), Hysteria2
# ============================================================================
#
#  USAGE:
#    sudo bash install.sh
#
#  Everything below is asked interactively — no domain names, passwords,
#  or ports are hardcoded in this script. Just answer the prompts.
#
#  WHAT THIS DOES:
#    1. System update + BBR + kernel/file-limit tuning
#    2. Installs Nginx, Certbot, sqlite3, UFW
#    3. Installs 3x-ui panel
#    4. Issues Let's Encrypt SSL certs for your panel domain + CDN domain
#    5. Sets your chosen admin username/password on the x-ui panel
#    6. Writes Nginx reverse-proxy configs for panel + CDN(WS) domains
#    7. Opens required firewall ports
#    8. Prints a final summary + next manual steps (creating inbounds)
#
#  WHAT THIS DOES NOT DO (must be done manually after, inside the panel):
#    - Create the actual inbounds (Reality / Hysteria2 / CDN), because
#      client lists/limits are deployment-specific and the CDN domain
#      must already resolve via DNS before SSL issuance works.
#
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
ask_header() { echo -e "\n${BOLD}$1${NC}"; }

if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Try: sudo bash install.sh"
   exit 1
fi

# ---------------------------------------------------------------------------
# 1. Welcome + DNS reminder
# ---------------------------------------------------------------------------
clear
cat << 'BANNER'
==============================================================
   X-UI VPN SERVER AUTO-INSTALLER
   VLESS+Reality / Hysteria2 / VLESS+WS (CDN-ready)
==============================================================
BANNER

echo ""
echo "Before continuing, point these DNS A records at this server's"
echo "public IP (you'll be asked for the actual domain names next):"
echo ""
echo "   <panel domain>  -> THIS_SERVER_IP   (DNS-only / grey-cloud recommended)"
echo "   <cdn domain>    -> THIS_SERVER_IP   (Proxied / orange-cloud is fine here)"
echo ""
read -rp "Press Enter once your DNS records are in place, or Ctrl+C to abort... "

# ---------------------------------------------------------------------------
# 2. Interactive configuration — domains
# ---------------------------------------------------------------------------
ask_header "STEP 1 / 4 — Domains"

while true; do
    read -rp "Panel/VPN domain (e.g. panel.yourdomain.com): " PANEL_DOMAIN
    [[ -n "$PANEL_DOMAIN" ]] && break
    warn "Domain cannot be empty."
done

while true; do
    read -rp "CDN domain (e.g. cdn.yourdomain.com): " CDN_DOMAIN
    [[ -n "$CDN_DOMAIN" ]] && break
    warn "Domain cannot be empty."
done

while true; do
    read -rp "Email for Let's Encrypt renewal notices: " LE_EMAIL
    [[ "$LE_EMAIL" =~ ^[^[:space:]]+@[^[:space:]]+\.[^[:space:]]+$ ]] && break
    warn "Please enter a valid email address."
done

# ---------------------------------------------------------------------------
# 3. Interactive configuration — internal ports
# ---------------------------------------------------------------------------
ask_header "STEP 2 / 4 — Internal Ports (press Enter to accept the default)"

read -rp "x-ui panel port [2053]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-2053}

read -rp "CDN inbound internal port [2083]: " CDN_PORT
CDN_PORT=${CDN_PORT:-2083}

read -rp "Subscription/bot internal port [2096]: " SUB_PORT
SUB_PORT=${SUB_PORT:-2096}

# ---------------------------------------------------------------------------
# 4. Interactive configuration — admin credentials
# ---------------------------------------------------------------------------
ask_header "STEP 3 / 4 — Panel Admin Login"

read -rp "Admin username [admin]: " ADMIN_USER
ADMIN_USER=${ADMIN_USER:-admin}

while true; do
    read -rsp "Admin password (min 8 characters): " ADMIN_PASS
    echo ""
    if [[ ${#ADMIN_PASS} -lt 8 ]]; then
        warn "Password too short, please use at least 8 characters."
        continue
    fi
    read -rsp "Confirm admin password: " ADMIN_PASS_CONFIRM
    echo ""
    if [[ "$ADMIN_PASS" != "$ADMIN_PASS_CONFIRM" ]]; then
        warn "Passwords did not match, try again."
        continue
    fi
    break
done

# ---------------------------------------------------------------------------
# 5. Final confirmation before making any changes
# ---------------------------------------------------------------------------
ask_header "STEP 4 / 4 — Review"

echo "  Panel domain     : $PANEL_DOMAIN"
echo "  CDN domain       : $CDN_DOMAIN"
echo "  Let's Encrypt email : $LE_EMAIL"
echo "  Panel port       : $PANEL_PORT"
echo "  CDN port         : $CDN_PORT"
echo "  Sub/bot port     : $SUB_PORT"
echo "  Admin username   : $ADMIN_USER"
echo "  Admin password   : (hidden, ${#ADMIN_PASS} characters)"
echo ""
read -rp "Proceed with installation using the above? [y/N]: " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "Aborted. Re-run the script to start again."
    exit 0
fi

# ---------------------------------------------------------------------------
# 6. System update + kernel tuning (BBR, file limits)
# ---------------------------------------------------------------------------
info "Updating system packages..."
apt update -y && apt upgrade -y

info "Applying BBR + network tuning..."
SYSCTL_FILE="/etc/sysctl.conf"
grep -q "net.core.default_qdisc=fq" "$SYSCTL_FILE" || cat >> "$SYSCTL_FILE" << 'EOF'

# --- VPN server tuning (added by auto-installer) ---
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_keepalive_time=90
net.ipv4.ip_local_port_range=1024 65535
net.ipv4.tcp_fastopen=3
fs.file-max=65535000
EOF
sysctl -p >/dev/null 2>&1 || true

info "Applying file descriptor / process limits..."
LIMITS_FILE="/etc/security/limits.conf"
grep -q "soft nofile 655350" "$LIMITS_FILE" || cat >> "$LIMITS_FILE" << 'EOF'
* soft nproc 655350
* hard nproc 655350
* soft nofile 655350
* hard nofile 655350
root soft nproc 655350
root hard nproc 655350
root soft nofile 655350
root hard nofile 655350
EOF

# ---------------------------------------------------------------------------
# 7. Install base packages: Nginx, Certbot, sqlite3, UFW, curl
# ---------------------------------------------------------------------------
info "Installing Nginx, Certbot, UFW, sqlite3..."
apt install -y nginx certbot python3-certbot-nginx sqlite3 ufw curl socat cron

systemctl enable nginx
systemctl start nginx

# ---------------------------------------------------------------------------
# 8. Firewall (UFW) baseline rules
# ---------------------------------------------------------------------------
info "Configuring firewall (UFW)..."
ufw allow OpenSSH
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw allow 443/udp
ufw allow "${PANEL_PORT}/tcp"
ufw allow "${CDN_PORT}/tcp"
ufw allow "${SUB_PORT}/tcp"
echo "y" | ufw enable

# ---------------------------------------------------------------------------
# 9. Issue SSL certificates (standalone, before nginx vhosts exist)
# ---------------------------------------------------------------------------
info "Issuing SSL certificate for panel domain: $PANEL_DOMAIN ..."
systemctl stop nginx
certbot certonly --standalone --non-interactive --agree-tos \
    -m "$LE_EMAIL" -d "$PANEL_DOMAIN" || {
        error "Certbot failed for $PANEL_DOMAIN."
        error "Check that its DNS A record points to this server, then re-run:"
        error "  certbot certonly --standalone -d $PANEL_DOMAIN"
    }

info "Issuing SSL certificate for CDN domain: $CDN_DOMAIN ..."
certbot certonly --standalone --non-interactive --agree-tos \
    -m "$LE_EMAIL" -d "$CDN_DOMAIN" || {
        error "Certbot failed for $CDN_DOMAIN."
        error "Check that its DNS A record points to this server, then re-run:"
        error "  certbot certonly --standalone -d $CDN_DOMAIN"
    }

systemctl start nginx
systemctl enable certbot.timer
systemctl start certbot.timer

# ---------------------------------------------------------------------------
# 10. Install x-ui (3x-ui)
# ---------------------------------------------------------------------------
info "Installing x-ui (3x-ui)..."
if [ -d /usr/local/x-ui ]; then
    warn "x-ui already installed, skipping installer download."
else
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) <<< $'\n'
fi

# ---------------------------------------------------------------------------
# 11. Configure x-ui panel settings (port, cert paths, admin credentials)
# ---------------------------------------------------------------------------
info "Configuring x-ui panel (port, cert paths, admin login)..."
systemctl stop x-ui || true

X_UI_DB="/etc/x-ui/x-ui.db"
if [ ! -f "$X_UI_DB" ]; then
    # First run sometimes needs the binary to be launched once to create the DB
    warn "x-ui database not found yet, initializing it..."
    timeout 5 /usr/local/x-ui/x-ui run >/dev/null 2>&1 || true
    sleep 2
    pkill -f "/usr/local/x-ui/x-ui run" >/dev/null 2>&1 || true
fi

if [ -f "$X_UI_DB" ]; then
    sqlite3 "$X_UI_DB" "UPDATE settings SET value='${PANEL_PORT}' WHERE key='webPort';"
    sqlite3 "$X_UI_DB" "UPDATE settings SET value='/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem' WHERE key='webCertFile';"
    sqlite3 "$X_UI_DB" "UPDATE settings SET value='/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem' WHERE key='webKeyFile';"

    # Set admin credentials using x-ui's own CLI (preferred — handles password hashing correctly)
    /usr/local/x-ui/x-ui setting -username "$ADMIN_USER" -password "$ADMIN_PASS" >/dev/null 2>&1 || \
        warn "Could not set admin credentials via CLI — set them manually after first login via: x-ui"
else
    warn "x-ui database still not found. After install finishes, run 'x-ui' once manually,"
    warn "then re-run the cert/port/admin configuration steps from this script if needed."
fi

systemctl start x-ui
systemctl enable x-ui

# ---------------------------------------------------------------------------
# 12. Nginx reverse proxy configs
# ---------------------------------------------------------------------------
info "Writing Nginx config for panel domain..."
cat > "/etc/nginx/sites-available/${PANEL_DOMAIN}" << EOF
server {
    listen 443 ssl;
    listen [::]:443 ssl;
    server_name ${PANEL_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /panel/ {
        proxy_pass http://127.0.0.1:${PANEL_PORT}/panel/;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

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
    server_name ${PANEL_DOMAIN};
    return 301 https://\$host\$request_uri;
}
EOF

info "Writing Nginx config for CDN domain (WS protocol, HTTP/1.1 forced)..."
cat > "/etc/nginx/sites-available/${CDN_DOMAIN}" << EOF
server {
    listen 80;
    server_name ${CDN_DOMAIN};
    return 301 https://\$host\$request_uri;
}

server {
    listen 443 ssl;
    server_name ${CDN_DOMAIN};

    ssl_certificate /etc/letsencrypt/live/${CDN_DOMAIN}/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/${CDN_DOMAIN}/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /vless {
        proxy_pass http://127.0.0.1:${CDN_PORT};
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
}
EOF

ln -sf "/etc/nginx/sites-available/${PANEL_DOMAIN}" /etc/nginx/sites-enabled/
ln -sf "/etc/nginx/sites-available/${CDN_DOMAIN}" /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default

nginx -t && systemctl reload nginx

# ---------------------------------------------------------------------------
# 13. Generate Reality keypair (for convenience, user pastes into panel)
# ---------------------------------------------------------------------------
info "Generating a Reality x25519 keypair for convenience..."
if [ -x /usr/local/x-ui/bin/xray-linux-amd64 ]; then
    REALITY_KEYS=$(/usr/local/x-ui/bin/xray-linux-amd64 x25519 2>/dev/null || true)
else
    REALITY_KEYS="(xray binary not found yet — generate later via: /usr/local/x-ui/bin/xray-linux-amd64 x25519)"
fi

# ---------------------------------------------------------------------------
# 14. Final summary
# ---------------------------------------------------------------------------
SERVER_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')

cat << SUMMARY

==============================================================
 INSTALLATION COMPLETE
==============================================================

Server IP          : ${SERVER_IP}
Panel URL          : https://${PANEL_DOMAIN}/panel/
Admin username     : ${ADMIN_USER}
Admin password     : (the one you entered above)
CDN domain         : https://${CDN_DOMAIN}/vless  (routes to port ${CDN_PORT})

Reality keypair (for VLESS+Reality inbound):
${REALITY_KEYS}

------------------------------------------------------------
NEXT STEPS (manual, inside x-ui panel UI):
------------------------------------------------------------
1. Open https://${PANEL_DOMAIN}/panel/ and log in with the
   admin username/password you set above.

2. Create inbound: VLESS + Reality
   - Port: any free port (e.g. 36878)
   - Network: tcp, Security: reality
   - Dest: www.microsoft.com:443 (or any large CDN-fronted site)
   - Private key: use the Reality key generated above
   - Open that port in firewall: ufw allow <port>/tcp

3. Create inbound: Hysteria2
   - Port: any free UDP port (e.g. 52605)
   - TLS cert: /etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem
   - TLS key:  /etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem
   - Open that port in firewall: ufw allow <port>/udp

4. Create inbound: VLESS + WS (CDN)
   - Port: ${CDN_PORT} (must match the Nginx config written above)
   - Network: ws, Security: none (TLS is already terminated by Nginx)
   - Path: /vless (must match the Nginx location block above)
   - Host: ${CDN_DOMAIN}

5. Add clients to each inbound and copy their connection links into
   Happ / V2rayNG / V2rayTun / Hiddify / Karing.

6. (Optional, for download-site blocking) Add a routing rule in each
   inbound's outbound rules to block domains such as:
   drive.google.com, mega.nz, mediafire.com, play.google.com,
   itunes.apple.com, ota.itunes.apple.com, updates.cdn-apple.com

------------------------------------------------------------
IMPORTANT NOTES:
------------------------------------------------------------
- If your CDN domain's DNS is "Proxied" (orange cloud) on Cloudflare,
  set Cloudflare's SSL/TLS mode to "Full" or "Full (strict)" — NOT
  "Flexible" — or the CDN protocol will silently fail.
- Whatever port you choose for Reality/Hysteria2 inbounds, remember to
  open it in BOTH ufw (this script only opened the panel/CDN/sub ports)
  AND your cloud provider's network firewall (DigitalOcean Cloud
  Firewall, AWS Security Group, etc.) — missing the cloud-level rule is
  the most common cause of "connects then times out".

==============================================================
SUMMARY
