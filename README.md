# VPN Server Auto-Installer (x-ui based)

One-shot installer for a censorship-resistant VPN server on a fresh
Ubuntu 24.04 VPS, using [3x-ui](https://github.com/MHSanaei/3x-ui) as the
panel/core, with three protocols ready to configure:

- **VLESS + Reality** (TCP, no CDN needed, very hard to fingerprint)
- **Hysteria2** (UDP/QUIC, fastest, best for high-latency/lossy networks)
- **VLESS + WS** behind Nginx + a CDN domain (works even when raw IPs are
  blocked, since traffic looks like normal HTTPS to a real-looking domain)

This mirrors a production setup tested against active DPI/firewall
blocking conditions (Myanmar GFW-style filtering).

## What it installs

| Component | Purpose |
|---|---|
| Ubuntu BBR + sysctl tuning | Lower latency, higher throughput |
| Nginx | TLS termination + reverse proxy for panel & CDN domain |
| Certbot | Free Let's Encrypt SSL certs, auto-renewing |
| 3x-ui | Web panel for managing inbounds/users/traffic limits |
| UFW | Firewall, opens only required ports |
| sqlite3 | Used to pre-configure the x-ui panel port/cert |

## What it does NOT do automatically

Inbound creation (Reality / Hysteria2 / CDN-WS) is done **inside the x-ui
panel UI** after install, because:
- Reality requires a fresh keypair per server (generated for you, but you
  paste it into the panel yourself)
- CDN domain must already resolve via DNS before SSL issuance works
- Client lists/traffic limits/expiry are deployment-specific

The script prints exact step-by-step instructions for this at the end.

## Requirements

- Fresh Ubuntu 22.04 or 24.04 VPS (DigitalOcean, Vultr, etc.)
- Root access
- Two DNS A records already pointed at the server's IP **before running**:
  - `panel.yourdomain.com` → server IP (DNS-only/grey-cloud recommended)
  - `cdn.yourdomain.com` → server IP (Proxied/orange-cloud OK if using
    Cloudflare — just set SSL/TLS mode to "Full", not "Flexible")

## Usage

```bash
git clone https://github.com/R4in8ow/vpn-auto-script.git
cd vpn-auto-script
chmod +x install.sh
sudo bash install.sh
```

You'll be prompted for:
- Panel domain
- CDN domain
- Email (for Let's Encrypt)
- Internal ports (sensible defaults provided)

## After install

1. Log into the panel at `https://panel.yourdomain.com/panel/`
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

## License

R4in8ow
