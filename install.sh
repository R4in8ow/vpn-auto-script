#!/bin/bash

# ==============================================================================
# VPN server installation Script Created By R4in8ow
# https://www.facebook.com/R4in8owLay
# ==============================================================================

# Color Codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}  Starting x-ui VPN Server Automated Setup (Stand-alone Mode)   ${NC}"
echo -e "${CYAN}================================================================${NC}"

# Root Check
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Please run this script as root.${NC}"
  exit 1
fi

# 1. User Input (Domain Info)
echo -e "\n${YELLOW}=== Please Enter Your Domain Information ===${NC}"
read -p "Enter Panel Domain (e.g., panel.example.com): " PANEL_DOMAIN
read -p "Enter CDN Domain (e.g., cdn.example.com): " CDN_DOMAIN

if [[ -z "$PANEL_DOMAIN" || -z "$CDN_DOMAIN" ]]; then
    echo -e "${RED}Error: Domains cannot be empty. Exiting...${NC}"
    exit 1
fi

echo -e "\n${GREEN}Panel Domain set to: ${PANEL_DOMAIN}${NC}"
echo -e "${GREEN}CDN Domain set to: ${CDN_DOMAIN}${NC}"
sleep 2

# 2. System Update & Dependencies
echo -e "\n${YELLOW}=== Updating System & Installing Dependencies ===${NC}"
apt update && apt upgrade -y
apt install -y curl wget socat jq qrencode ufw unzip tzdata

# Set Timezone to Asia/Rangoon
timedatectl set-timezone Asia/Rangoon

# 3. Configure Firewall (UFW)
echo -e "\n${YELLOW}=== Configuring Firewall (UFW) ===${NC}"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

# Allow Essential Ports
ufw allow 22/tcp      # SSH
ufw allow 80/tcp      # HTTP (for Certbot Standalone)
ufw allow 443/tcp     # HTTPS
ufw allow 2053/tcp    # x-ui Panel Port
ufw allow 457/udp     # Hysteria 2 UDP
ufw allow 459/tcp     # VLESS CDN Port (or 2083)
ufw allow 7443/tcp    # Reality Port
ufw allow 39301/tcp   # Shadowsocks Port
ufw allow 39301/udp   # Shadowsocks UDP

echo "y" | ufw enable
ufw reload
echo -e "${GREEN}Firewall configured successfully.${NC}"

# 4. Request SSL Certificates (Standalone Mode)
echo -e "\n${YELLOW}=== Generating SSL Certificates (acme.sh) ===${NC}"
curl https://get.acme.sh | sh
source ~/.bashrc

# Set Let's Encrypt as default
~/.acme.sh/acme.sh --set-default-ca --server letsencrypt

# Register Account
~/.acme.sh/acme.sh --register-account -m admin@${PANEL_DOMAIN}

# Create certs directory
mkdir -p /root/cert/${PANEL_DOMAIN}
mkdir -p /root/cert/${CDN_DOMAIN}

# Issue Certificate for Panel Domain
echo -e "${CYAN}Issuing cert for ${PANEL_DOMAIN}...${NC}"
~/.acme.sh/acme.sh --issue -d ${PANEL_DOMAIN} --standalone
~/.acme.sh/acme.sh --installcert -d ${PANEL_DOMAIN} \
    --key-file /root/cert/${PANEL_DOMAIN}/privkey.pem \
    --fullchain-file /root/cert/${PANEL_DOMAIN}/fullchain.pem

# Issue Certificate for CDN Domain
echo -e "${CYAN}Issuing cert for ${CDN_DOMAIN}...${NC}"
~/.acme.sh/acme.sh --issue -d ${CDN_DOMAIN} --standalone
~/.acme.sh/acme.sh --installcert -d ${CDN_DOMAIN} \
    --key-file /root/cert/${CDN_DOMAIN}/privkey.pem \
    --fullchain-file /root/cert/${CDN_DOMAIN}/fullchain.pem

chmod -R 755 /root/cert
echo -e "${GREEN}SSL Certificates generated successfully.${NC}"

# 5. Optimizing System Limits & Enabling BBR
echo -e "\n${YELLOW}=== Optimizing System Limits & Enabling BBR ===${NC}"
cat <<EOF >> /etc/sysctl.conf
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
net.ipv4.tcp_keepalive_time = 90
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_fastopen = 3
fs.file-max = 65535000
EOF

sysctl -p

cat <<EOF >> /etc/security/limits.conf
* soft nproc 655350
* hard nproc 655350
* soft nofile 655350
* hard nofile 655350
root soft nproc 655350
root hard nproc 655350
root soft nofile 655350
root hard nofile 655350
EOF
echo -e "${GREEN}BBR and System Limits Applied Successfully!${NC}"

# 6. Install 3x-ui Panel
echo -e "\n${YELLOW}=== Installing 3x-ui Panel ===${NC}"
bash <(curl -Ls https://raw.githubusercontent.com/mhsanaei/3x-ui/master/install.sh) <<EOF
y
admin
admin123
2053
EOF
echo -e "${GREEN}3x-ui Panel installed.${NC}"

# 7. Generate Reality Keys
echo -e "\n${YELLOW}=== Generating Reality Keys ===${NC}"
XRAY_BIN="/usr/local/x-ui/bin/xray-linux-amd64"

if [ -f "$XRAY_BIN" ]; then
    # Generate X25519 Keys
    KEYS=$($XRAY_BIN x25519)
    PRIVATE_KEY=$(echo "$KEYS" | grep "Private key:" | awk '{print $3}')
    PUBLIC_KEY=$(echo "$KEYS" | grep "Public key:" | awk '{print $3}')
    
    # Generate Short ID
    SHORT_ID=$(openssl rand -hex 8)

    echo -e "Reality Private Key: ${CYAN}${PRIVATE_KEY}${NC}"
    echo -e "Reality Public Key:  ${CYAN}${PUBLIC_KEY}${NC}"
    echo -e "Reality Short ID:    ${CYAN}${SHORT_ID}${NC}"
    
    # Save to file for reference
    cat <<EOF > ~/reality_keys.txt
=========================================
Reality Keys for ${PANEL_DOMAIN}
=========================================
Private Key : ${PRIVATE_KEY}
Public Key  : ${PUBLIC_KEY}
Short ID    : ${SHORT_ID}
=========================================
EOF
else
    echo -e "${RED}Xray binary not found. Could not generate Reality keys.${NC}"
fi

# 8. Final Summary & Instructions
echo -e "\n${CYAN}================================================================${NC}"
echo -e "${GREEN}                   INSTALLATION COMPLETE!                       ${NC}"
echo -e "${CYAN}================================================================${NC}"

echo -e "\n${YELLOW}--- 1. Panel Access ---${NC}"
echo -e "URL:       https://${PANEL_DOMAIN}:2053/panel"
echo -e "Username:  admin"
echo -e "Password:  admin123"

echo -e "\n${YELLOW}--- 2. Important SSL Paths for x-ui Inbounds ---${NC}"
echo -e "Use these paths in 'Stream Settings -> Certificate' when creating CDN/Hysteria nodes:"
echo -e "Public Key Path (Panel):  ${CYAN}/root/cert/${PANEL_DOMAIN}/fullchain.pem${NC}"
echo -e "Private Key Path (Panel): ${CYAN}/root/cert/${PANEL_DOMAIN}/privkey.pem${NC}"
echo -e "Public Key Path (CDN):    ${CYAN}/root/cert/${CDN_DOMAIN}/fullchain.pem${NC}"
echo -e "Private Key Path (CDN):   ${CYAN}/root/cert/${CDN_DOMAIN}/privkey.pem${NC}"

echo -e "\n${YELLOW}--- 3. Reality Node Configuration ---${NC}"
echo -e "Your newly generated Reality Keys are saved in ${CYAN}~/reality_keys.txt${NC}"
cat ~/reality_keys.txt

echo -e "\n${YELLOW}--- 4. Next Steps ---${NC}"
echo -e "1. Go to Cloudflare and ensure ${PANEL_DOMAIN} is ${RED}Proxy OFF (Grey Cloud)${NC}."
echo -e "2. Ensure ${CDN_DOMAIN} is ${GREEN}Proxy ON (Orange Cloud)${NC} and SSL is Full (Strict)."
echo -e "3. Login to x-ui panel, go to Panel Settings -> Telegram Bot, and enter your Token & Admin ID."
echo -e "${CYAN}================================================================${NC}"
echo -e "${GREEN}Thanks for using the script, and if you have any errors, contact me on Facebook!${NC}"
echo -e "${CYAN}https://www.facebook.com/R4in8owLay${NC}"
echo -e "${CYAN}================================================================${NC}\n"
