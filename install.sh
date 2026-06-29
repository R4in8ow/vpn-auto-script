#!/bin/bash
#
# ============================================================================
#  X-UI VPN Server Auto-Installer
#  Stack: Ubuntu 24.04 + x-ui (3x-ui) + Nginx + Certbot + UFW
#  Protocols: VLESS+Reality, VLESS+WS (CDN-ready), Hysteria2
# ============================================================================
#
#  USAGE:
#    sudo bash install.sh
#
#  WHAT THIS DOES:
#    1. System update + BBR + kernel/file-limit tuning
#    2. Installs Nginx, Certbot, sqlite3, UFW
#    3. Installs 3x-ui panel
#    4. Issues Let's Encrypt SSL certs for panel domain + CDN domain
#    5. Writes Nginx reverse-proxy configs for panel + CDN(WS) domains
#    6. Opens required firewall ports
#    7. Prints a final summary of what to configure manually inside the
#       x-ui panel (inbounds must be created via the panel UI/API, since
#       client lists differ per deployment)
#
#  WHAT THIS DOES NOT DO (must be done manually after):
#    - Create the actual inbounds (Reality / Hysteria2 / CDN) inside x-ui
#      panel UI, because Reality private keys must be generated per-server
#      and CDN domain DNS must point to this server first.
#    - Point your domain's DNS records at this server's IP (do this BEFORE
#      running the certbot steps, or they will fail).
#
# ============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# 0. Helpers
# ---------------------------------------------------------------------------
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[INFO]${NC} $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
   error "This script must be run as root. Try: sudo bash install.sh"
   exit 1
fi

# ---------------------------------------------------------------------------
# 1. Collect configuration from user
# ---------------------------------------------------------------------------
echo "=============================================="
echo " X-UI VPN Server Auto-Installer"
echo "=============================================="
echo ""
echo "Before continuing, make sure these DNS A records already point"
echo "to this server's public IP (DNS-only / grey-cloud for panel domain,"
echo "Proxied / orange-cloud is OK for the CDN domain):"
echo ""
echo "  panel.yourdomain.com   -> THIS_SERVER_IP   (panel + reality + hysteria2)"
echo "  cdn.yourdomain.com     -> THIS_SERVER_IP   (CDN/WS fallback protocol)"
echo ""
read -rp "Panel/VPN domain (e.g. panel.example.com): " PANEL_DOMAIN
read -rp "CDN domain (e.g. cdn.example.com): " CDN_DOMAIN
read -rp "Email for Let's Encrypt notifications: " LE_EMAIL
read -rp "x-ui panel port [2053]: " PANEL_PORT
PANEL_PORT=${PANEL_PORT:-2053}
read -rp "CDN inbound internal port [2083]: " CDN_PORT
CDN_PORT=${CDN_PORT:-2083}
read -rp "Subscription/bot internal port [2096]: " SUB_PORT
SUB_PORT=${SUB_PORT:-2096}

echo ""
info "Configuration:"
echo "  Panel domain : $PANEL_DOMAIN"
echo "  CDN domain   : $CDN_DOMAIN"
echo "  LE email     : $LE_EMAIL"
echo "  Panel port   : $PANEL_PORT"
echo "  CDN port     : $CDN_PORT"
echo "  Sub port     : $SUB_PORT"
echo ""
read -rp "Continue with installation? [y/N]: " CONFIRM
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "Aborted."
    exit 0
fi

# ---------------------------------------------------------------------------
# 2. System update + kernel tuning (BBR, file limits)
# ---------------------------------------------------------------------------
info "Updating system packages..."
apt update -y && apt upgrade -y

info "Applying BBR + network tuning..."
SYSCTL_FILE="/etc/sysctl.conf"
# Avoid duplicate entries on re-run
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
# 3. Install base packages: Nginx, Certbot, sqlite3, UFW, curl
# ---------------------------------------------------------------------------
info "Installing Nginx, Certbot, UFW, sqlite3..."
apt install -y nginx certbot python3-certbot-nginx sqlite3 ufw curl socat cron

systemctl enable nginx
systemctl start nginx

# ---------------------------------------------------------------------------
# 4. Firewall (UFW) baseline rules
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
# Common Reality / Hysteria2 high ports - adjust after creating inbounds
ufw allow 8443/tcp
ufw allow 8443/udp
echo "y" | ufw enable

# ---------------------------------------------------------------------------
# 5. Issue SSL certificates (standalone, before nginx vhosts exist)
# ---------------------------------------------------------------------------
info "Issuing SSL certificate for panel domain: $PANEL_DOMAIN ..."
# Temporarily stop nginx so certbot standalone can bind port 80
systemctl stop nginx
certbot certonly --standalone --non-interactive --agree-tos \
    -m "$LE_EMAIL" -d "$PANEL_DOMAIN" || {
        error "Certbot failed for $PANEL_DOMAIN. Check DNS A record, then re-run certbot manually:"
        error "  certbot certonly --standalone -d $PANEL_DOMAIN"
    }

info "Issuing SSL certificate for CDN domain: $CDN_DOMAIN ..."
certbot certonly --standalone --non-interactive --agree-tos \
    -m "$LE_EMAIL" -d "$CDN_DOMAIN" || {
        error "Certbot failed for $CDN_DOMAIN. Check DNS A record, then re-run certbot manually:"
        error "  certbot certonly --standalone -d $CDN_DOMAIN"
    }

systemctl start nginx
systemctl enable certbot.timer
systemctl start certbot.timer

# ---------------------------------------------------------------------------
# 6. Install x-ui (3x-ui)
# ---------------------------------------------------------------------------
info "Installing x-ui (3x-ui)..."
if [ -d /usr/local/x-ui ]; then
    warn "x-ui already installed, skipping installer download."
else
    bash <(curl -Ls https://raw.githubusercontent.com/MHSanaei/3x-ui/master/install.sh) <<< $'\n'
fi

# ---------------------------------------------------------------------------
# 7. Configure x-ui panel settings (port, cert paths, base path)
# ---------------------------------------------------------------------------
info "Configuring x-ui panel to use issued certificate..."
systemctl stop x-ui || true

X_UI_DB="/etc/x-ui/x-ui.db"
if [ -f "$X_UI_DB" ]; then
    sqlite3 "$X_UI_DB" "UPDATE settings SET value='${PANEL_PORT}' WHERE key='webPort';"
    sqlite3 "$X_UI_DB" "UPDATE settings SET value='/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem' WHERE key='webCertFile';"
    sqlite3 "$X_UI_DB" "UPDATE settings SET value='/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem' WHERE key='webKeyFile';"
else
    warn "x-ui database not found yet — open the panel once via 'x-ui' command to initialize it, then re-run the cert step manually."
fi

systemctl start x-ui
systemctl enable x-ui

# ---------------------------------------------------------------------------
# 8. Nginx reverse proxy configs
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
# 9. Generate Reality keypair (for convenience, user pastes into panel)
# ---------------------------------------------------------------------------
info "Generating a Reality x25519 keypair for convenience..."
if [ -x /usr/local/x-ui/bin/xray-linux-amd64 ]; then
    REALITY_KEYS=$(/usr/local/x-ui/bin/xray-linux-amd64 x25519 2>/dev/null || true)
else
    REALITY_KEYS="(xray binary not found yet — generate later via: /usr/local/x-ui/bin/xray-linux-amd64 x25519)"
fi

# ---------------------------------------------------------------------------
# 10. Final summary
# ---------------------------------------------------------------------------
SERVER_IP=$(curl -s -4 ifconfig.me || hostname -I | awk '{print $1}')

cat << SUMMARY

==============================================================
 INSTALLATION COMPLETE
==============================================================

Server IP        : ${SERVER_IP}
Panel URL         : https://${PANEL_DOMAIN}/panel/
CDN domain         : https://${CDN_DOMAIN}/vless  (point this at port ${CDN_PORT})

Reality keypair (for VLESS+Reality inbound):
${REALITY_KEYS}

------------------------------------------------------------
NEXT STEPS (manual, inside x-ui panel UI):
------------------------------------------------------------
1. Open https://${PANEL_DOMAIN}/panel/ and log in
   (default credentials were set during 3x-ui install — check
   the installer output above, or run: x-ui  -> option to show/reset login)

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
   - Port: ${CDN_PORT} (must match nginx config above)
   - Network: ws, Security: none (TLS already terminated by Nginx)
   - Path: /vless (must match nginx location block above)
   - Host: ${CDN_DOMAIN}

5. Add clients to each inbound and copy their connection links into
   Happ / V2rayNG / V2rayTun / Hiddify / Karing.

6. (Optional, for download-site blocking) Add routing rule in each
   inbound's "Advanced" / outbound rules to block domains such as:
   drive.google.com, mega.nz, mediafire.com, play.google.com,
   itunes.apple.com, ota.itunes.apple.com, updates.cdn-apple.com

------------------------------------------------------------
IMPORTANT NOTES:
------------------------------------------------------------
- If CDN domain DNS is "Proxied" (orange cloud) on Cloudflare, set
  Cloudflare SSL/TLS mode to "Full" or "Full (strict)" — NOT "Flexible".
- If Hysteria2 protocol times out, double check the UDP port is
  allowed in BOTH ufw and any upstream cloud firewall (e.g. DigitalOcean
  Cloud Firewall), since ufw alone is not enough on most cloud providers.
- Panel default login must be changed immediately after first login.

==============================================================
SUMMARY
