# VPN Auto-Script

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2022.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![3x-ui](https://img.shields.io/badge/panel-3x--ui-blue)](https://github.com/MHSanaei/3x-ui)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-blueviolet)]()

> 🇲🇲 မြန်မာ ဘာသာဖြင့် ဖတ်ရန်: [README.my.md](README.my.md)

One command turns a fresh Ubuntu VPS into a fully working,
censorship-resistant VPN server. No manual panel steps — all seven
protocol inbounds are created automatically through the 3x-ui REST API.

## What it is

`install.sh` provisions the exact stack this project runs in production:

- **3x-ui** panel + Xray core (latest release via the official installer)
- **Nginx** as an SNI router (public 443 shared between Reality and the
  web panel) plus TLS-terminating reverse proxy
- **Let's Encrypt** certificates with zero-downtime `--webroot` issuance
- **UFW** firewall, **BBR** tuning, 4G swap, raised file limits,
  unattended security upgrades, optional fail2ban

After it finishes, clients can connect immediately — no clicking around
in the panel required.

## Features

- 🚀 **True one-shot install** — `git clone` + `sudo bash install.sh`
- 🔌 **7 inbounds auto-created**: VLESS+Reality, VLESS+WS, VLESS+gRPC,
  VLESS+XHTTP, Hysteria2, Shadowsocks-2022, TUIC
- 🧭 **SNI routing** — public TCP/443 serves Reality (SNI `web.dev`) and
  the panel/CDN websites (everything else) at the same time
- 🔑 **Fresh secrets per install** — Reality x25519 keypair, UUIDs,
  passwords, all generated locally, never hardcoded
- 📦 **`.env` support** — non-interactive installs for automation
- ✅ **Post-install self-test** — panel reachability, listening ports,
  certificate validity, Xray state, inbound count
- 🧹 **`uninstall.sh`** — clean removal of everything the installer did
- 🔒 **No secrets in the repo** — placeholders only, `.env` is gitignored

## Architecture overview

```
public TCP/443 ── nginx stream (ssl_preread, no TLS termination)
    ├─ SNI web.dev ──▶ 127.0.0.1:36878   (Xray Reality)
    └─ SNI other   ──▶ 127.0.0.1:4443    (nginx HTTPS: panel + CDN vhosts)

public UDP/443 ──▶ Xray TUIC          public TCP/36878 ──▶ Xray Reality (fallback)
CDN ──TCP/8443/2087/2089──▶ Xray WS / gRPC / XHTTP (via nginx or direct)
public UDP/40797 ──▶ Hysteria2        public 58023/tcp+udp ──▶ Shadowsocks-2022
```

Full detail: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Requirements

- Fresh **Ubuntu 24.04** (22.04 also works) VPS, root access
- Two DNS **A records** already pointing at the server IP **before** you run it:
  - `panel.example.com` → server IP (DNS-only / grey-cloud recommended)
  - `cdn.example.com` → server IP (proxied / orange-cloud is fine —
    set Cloudflare SSL/TLS mode to **Full**, not Flexible)

## Quick start

```bash
git clone https://github.com/R4in8ow/vpn-auto-script.git
cd vpn-auto-script
sudo bash install.sh
```

Answer the prompts (domains, ports, admin login). For unattended setups:

```bash
cp .env.example .env   # fill in YOUR values
sudo bash install.sh --non-interactive
```

Use `sudo bash install.sh --no-sni-routing` for the classic layout
(nginx HTTPS directly on public 443 instead of the SNI router).

## Configuration reference (`.env` variables)

| Variable | Default | Purpose |
|---|---|---|
| `PANEL_DOMAIN` | — | Panel + subscription domain |
| `CDN_DOMAIN` | — | CDN domain for WS/XHTTP/gRPC |
| `SUB_DOMAIN` | panel domain | Host used in subscription links |
| `LE_EMAIL` | — | Let's Encrypt renewal notices |
| `PANEL_PORT` | `2053` | x-ui panel port |
| `SUB_PORT` | `2096` | Subscription service port |
| `REALITY_PORT` | `36878` | Reality inbound (TCP) |
| `WS_PORT` | `8443` | VLESS+WS inbound (TCP) |
| `GRPC_PORT` | `2087` | VLESS+gRPC inbound (TCP) |
| `XHTTP_PORT` | `2089` | VLESS+XHTTP inbound (TCP) |
| `HY2_PORT` | `40797` | Hysteria2 inbound (UDP) |
| `SS_PORT` | `58023` | Shadowsocks inbound (TCP+UDP) |
| `TUIC_PORT` | `443` | TUIC inbound (UDP) |
| `REALITY_DEST` | `web.dev:443` | Reality camouflage destination |
| `REALITY_SNI` | `web.dev` | Reality SNI / serverName |
| `ADMIN_USER` / `ADMIN_PASS` | — | Panel login (min 8 chars) |
| `SNI_ROUTING` | `yes` | `no` = classic 443 layout |
| `INSTALL_FAIL2BAN` | `no` | SSH brute-force protection |
| `UFW_DEFAULT_DENY` | `no` | UFW default-deny incoming |

## Protocol table

| Inbound | Port | Transport | Client credential |
|---|---|---|---|
| VLESS + Reality | 36878/tcp (or 443 via SNI) | tcp + reality, uTLS chrome | UUID + `xtls-rprx-vision` |
| VLESS + WS (CDN) | 8443/tcp | ws, path `/vless`, TLS at nginx | UUID |
| VLESS + gRPC | 2087/tcp | grpc, service `vless-grpc`, TLS | UUID |
| VLESS + XHTTP | 2089/tcp | xhttp, path `/xhttp` | UUID |
| Hysteria2 | 40797/udp | TLS | password |
| Shadowsocks 2022 | 58023/tcp+udp | `2022-blake3-aes-128-gcm` | password |
| TUIC | 443/udp | TLS, congestion `bbr` | password |

All credentials are generated at install time and saved root-only to
`/root/vpn-credentials.env` (mode 600). Works with Happ, V2rayNG,
V2rayTun, Hiddify, Karing, Outline, Streisand, Nekoray.

## Post-install verification

The installer already runs a self-test (panel HTTPS, listening
TCP/UDP ports, certificate validity, Xray `running`, 7/7 inbounds,
BBR active). Re-check any time with the commands in
[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#useful-commands).

## Troubleshooting (summary)

| Symptom | Most likely cause |
|---|---|
| Panel won't load | DNS not propagated; port blocked in cloud firewall |
| Reality connects then times out | Port closed in provider firewall (not just UFW) |
| CDN works via Reality but WS fails | Cloudflare SSL mode is "Flexible" — use Full |
| Hysteria2/TUIC time out | UDP port not open (UFW + cloud firewall) |
| Xray won't stay running | One malformed inbound — see `journalctl -u x-ui` |

Full guide: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md).

## Security notes

- **No credentials, domains, IPs, emails or keys are stored in this
  repo.** Everything is prompted or read from your own (gitignored)
  `.env`. Generated secrets live only on the server.
- Change the bootstrap client credentials after install for real
  deployments (one bootstrap client per inbound is created; add real
  users with expiries/traffic caps in the panel).
- Consider setting `UFW_DEFAULT_DENY=yes` and installing fail2ban.
- Review `/root/vpn-credentials.env` permissions (600) and back it up
  somewhere safe — then delete it from the server if you prefer.

## Cloud-firewall reminder

UFW is only the OS firewall. DigitalOcean, AWS, Vultr, etc. enforce a
**separate network-level firewall** — open the same TCP/UDP ports
there, or connections will silently time out. This is the single most
common cause of "it works locally but not from my phone".

## Roadmap

- [ ] Server-side subscription sanitization (Reality currently exposes
      its direct port — see known limitation in
      [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md))
- [ ] Multi-user provisioning helper script
- [ ] Optional Cloudflare Tunnel mode (no open ports at all)

## Uninstall

```bash
sudo bash uninstall.sh          # asks before each destructive step
sudo bash uninstall.sh --yes    # no prompts
```

## Contributing

Issues and PRs are welcome. Please keep the no-secrets rule: never
commit domains, IPs, emails, passwords, keys or UUIDs — use the
`example.com` placeholders. Run `bash -n` on every shell file before
pushing.

## Testing note

All scripts pass `bash -n` syntax checks (and shellcheck where
available). A full end-to-end run needs a fresh VPS and has not been
executed in CI — if you run it, please report the result
(Ubuntu version, SNI vs classic mode) in an issue.

## License

MIT — see [LICENSE](LICENSE).
