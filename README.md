# VPN Server Auto-Installer (x-ui based)

One-shot, fully interactive installer for a censorship-resistant VPN
server on a fresh Ubuntu 22.04/24.04 VPS, using
[3x-ui](https://github.com/MHSanaei/3x-ui) as the panel/core, with three
protocols ready to configure:

- **VLESS + Reality** (TCP, no CDN needed, very hard to fingerprint)
- **Hysteria2** (UDP/QUIC, fastest, best for high-latency/lossy networks)
- **VLESS + WS** behind Nginx + a CDN domain (works even when raw IPs are
  blocked, since traffic looks like normal HTTPS to a real-looking domain)

This mirrors a production setup tested against active DPI/firewall
blocking conditions.

**Nothing is hardcoded.** The script asks you for every domain, port, and
credential it needs — just answer the prompts.

## What it asks you for

| Prompt | Example | Notes |
|---|---|---|
| Panel/VPN domain | `panel.yourdomain.com` | Must already point at this server's IP |
| CDN domain | `cdn.yourdomain.com` | Must already point at this server's IP |
| Let's Encrypt email | `you@example.com` | For renewal notices only |
| Panel port | `2053` (default) | Press Enter to accept default |
| CDN inbound port | `2083` (default) | Press Enter to accept default |
| Subscription/bot port | `2096` (default) | Press Enter to accept default |
| Admin username | `admin` (default) | Used to log into the x-ui panel |
| Admin password | (you choose) | Min. 8 characters, asked twice to confirm |

After collecting everything, it shows a summary and asks for final
confirmation (`y/N`) before making any changes to the system.

## What it installs

| Component | Purpose |
|---|---|
| Ubuntu BBR + sysctl tuning | Lower latency, higher throughput |
| Nginx | TLS termination + reverse proxy for panel & CDN domain |
| Certbot | Free Let's Encrypt SSL certs, auto-renewing |
| 3x-ui | Web panel for managing inbounds/users/traffic limits |
| UFW | Firewall, opens only the ports you configured |
| sqlite3 | Used to pre-configure the x-ui panel port/cert/admin login |

## What it does NOT do automatically

Inbound creation (Reality / Hysteria2 / CDN-WS) is done **inside the x-ui
panel UI** after install, because:
- Reality requires a fresh keypair per server (generated for you, but you
  paste it into the panel yourself)
- Client lists, traffic limits, and expiry dates are deployment-specific

The script prints exact step-by-step instructions for this at the end,
using the domains/ports you provided during setup.

## Requirements

- Fresh Ubuntu 22.04 or 24.04 VPS (DigitalOcean, Vultr, etc.)
- Root access
- Two DNS A records already pointed at the server's IP **before running
  the script**:
  - your panel domain → server IP (DNS-only/grey-cloud recommended)
  - your CDN domain → server IP (Proxied/orange-cloud OK if using
    Cloudflare — just set SSL/TLS mode to "Full", not "Flexible")

## Usage

```bash
git clone https://github.com/R4in8ow/vpn-auto-script.git
cd vpn-auto-script
chmod +x install.sh
sudo bash install.sh
```

Then just answer each prompt as it appears.

## After install

1. Log into the panel at the URL printed at the end (your panel domain +
   `/panel/`), using the admin username/password you chose during setup
2. Create the three inbounds following the printed instructions
3. Add clients, copy subscription/connection links into your client app
   (Happ, V2rayNG, V2rayTun, Hiddify, Karing all supported)

## Cloud firewall reminder

`ufw` only controls the OS firewall. Most cloud providers (DigitalOcean,
AWS, etc.) also have a **separate network-level firewall** — make sure
any custom ports you open for inbounds (Reality TCP port, Hysteria2 UDP
port) are allowed there too, or connections will silently time out.

## Troubleshooting

| Symptom | Likely cause |
|---|---|
| Panel won't load | Cert paths wrong in x-ui settings, or wrong port in Nginx config |
| Reality/CDN connects then times out | Port not open in BOTH ufw and cloud firewall |
| CDN protocol times out, Reality works | Cloudflare SSL/TLS mode set to "Flexible" instead of "Full" |
| Hysteria2 times out | UDP port not open, or wrong cert path in inbound TLS settings |
| Nginx 502 on panel/CDN domain | Wrong upstream port in Nginx config vs actual inbound port in x-ui |
| Certbot fails during install | DNS A record not yet pointing at this server — wait for propagation, then re-run that certbot command manually |

## Re-running the script

The script is mostly safe to re-run (it checks before duplicating sysctl
entries and skips the x-ui installer if already present), but SSL
issuance and admin credential steps will run again. If you only need to
change one thing, it's usually simpler to edit the relevant config file
directly (Nginx vhost, or `x-ui` CLI for admin credentials) rather than
re-running the whole script.

## License

MIT
