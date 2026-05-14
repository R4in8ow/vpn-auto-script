# VPN Server Installation Script
> Automated x-ui VPN Server Setup (Stand-alone Mode)

Created By **R4in8ow** | [Contact on Facebook](https://www.facebook.com/R4in8owLay)

This script automates the installation and configuration of the 3x-ui VPN panel on an Ubuntu/Debian server. It automatically generates SSL certificates, configures the firewall, generates Reality keys, and optimizes network settings (BBR).

## Features
- 🚀 **Automated 3x-ui Installation** (Latest Version)
- 🔒 **Auto Let's Encrypt SSL Generation** (Standalone mode, no Nginx required)
- 🔑 **Auto X25519 Reality Keys & Short ID Generation**
- 🛡️ **UFW Firewall Configuration** (Pre-configured ports for SSH, HTTPS, CDN, Hysteria 2)
- ⚡ **System Optimization** (Auto-enables TCP BBR and increases File Descriptor limits)

## Prerequisites
- A fresh Ubuntu 20.04/22.04 or Debian server.
- Two pointing subdomains from Cloudflare:
  - `Panel Domain` (e.g., amigos.yourdomain.com) -> **Proxy OFF (Grey Cloud)**
  - `CDN Domain` (e.g., cdn.yourdomain.com) -> **Proxy OFF** during installation, then turn **ON** later.

## Quick Install Command
Run the following command as `root`:

```bash
bash <(curl -Ls [https://raw.githubusercontent.com/R4in8ow/vpn-auto-script/main/install.sh]
(https://raw.githubusercontent.com/R4in8ow/vpn-auto-script/main/install.sh))


Default Credentials
Username: admin

Password: admin123

Panel URL: https://your-panel-domain:2053/panel

Important Note
After the installation is complete, your newly generated Reality Keys will be saved in the home directory at ~/reality_keys.txt.
