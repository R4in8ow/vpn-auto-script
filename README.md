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

## Manual settings reference

The installer automates everything below, but this section documents the
**exact resulting configuration** — every value the automation writes and
where it ends up — so you can reproduce, audit, or repair the server
entirely by hand. All values are the installer defaults; substitute your
own domains and ports.

### Generating secrets by hand

```bash
# Reality x25519 keypair (private key stays on the server,
# the "Password" line is the public key for client configs)
/usr/local/x-ui/bin/xray-linux-amd64 x25519

# Reality shortId (16 hex characters)
openssl rand -hex 8

# Client UUIDs (one per VLESS inbound)
cat /proc/sys/kernel/random/uuid

# Hysteria2 / TUIC client passwords (16 printable characters)
openssl rand -base64 16 | tr -d '/+=' | cut -c1-16

# Shadowsocks 2022-blake3-aes-128-gcm password: exactly 16 random
# bytes, base64-encoded (do NOT truncate — the cipher needs all 16)
openssl rand -base64 16
```

### x-ui panel settings

In the panel UI: **Panel Settings**. Equivalents via the CLI:

| Setting | Value | Manual command |
|---|---|---|
| Panel port | `2053` | `x-ui setting -port 2053` |
| Web Base Path | `/panel/` | `x-ui setting -webBasePath /panel/` |
| Public Key Path | `/etc/letsencrypt/live/panel.example.com/fullchain.pem` | Panel Settings → SSL |
| Private Key Path | `/etc/letsencrypt/live/panel.example.com/privkey.pem` | Panel Settings → SSL |
| Admin username / password | your choice (min 8 chars) | `x-ui setting -username … -password …` |

Subscription (Panel Settings → Subscription):

| Key | Value |
|---|---|
| Enable subscription | true |
| Subscription port | `2096` |
| Subscription path | `/sub/` |
| Subscription URI | `https://panel.example.com/sub/` |
| Subscription domain | `panel.example.com` |

After changing the port or base path, `systemctl restart x-ui`.
The panel is then at `https://panel.example.com/panel/` and client
subscription links look like `https://panel.example.com/sub/<subId>`.

### Inbounds — manual field reference

Create each via **Inbounds → Add Inbound**. One bootstrap client per
inbound is enough to start; add real users (with expiry/traffic caps)
afterwards.

**1. Reality** — VLESS, TCP `36878`
- Network `tcp`, Security `reality`
- Dest `web.dev:443`, ServerNames/SNI `web.dev`, xver `0`
- Private Key: `<from xray x25519>`, Short IDs: `<16 hex chars>`
- uTLS fingerprint `chrome`
- Client: UUID, Flow `xtls-rprx-vision`
- Sniffing enabled, destOverride `http,tls,quic,fakedns`

**2. CDN-Vless** — VLESS, TCP `8443`
- Network `ws`, Security `none` (nginx already terminates TLS — setting
  `tls` here is the classic double-TLS trap)
- Path `/vless`, Host header `cdn.example.com`
- Client: UUID

**3. CDN-gRPC** — VLESS, TCP `2087`
- Network `grpc`, Security `tls`
- ServiceName `vless-grpc`
- TLS serverName `panel.example.com`, certificate
  `/etc/letsencrypt/live/panel.example.com/fullchain.pem`, key
  `/etc/letsencrypt/live/panel.example.com/privkey.pem`, ALPN `h2,http/1.1`
- Client: UUID

**4. XHTTP** — VLESS, TCP `2089`
- Network `xhttp`, Security `none`
- Path `/xhttp`, Mode `auto`
- Client: UUID

**5. Hysteria2** — hysteria2, UDP `40797`
- TLS serverName `panel.example.com`, same LE certificate/key as above,
  ALPN `h3`
- Client auth: password

**6. Outline** — shadowsocks, TCP+UDP `58023`
- Method `2022-blake3-aes-128-gcm`
- Password: base64 of exactly 16 random bytes (see above)
- Network `tcp,udp`

**7. TUIC** — tuic, UDP `443`
- TLS serverName `panel.example.com`, same LE certificate/key, ALPN `h3`
- Congestion control `bbr`
- Client auth: password

### nginx — manual layout

`/etc/nginx/stream.conf` — the public TCP/443 SNI router. Requires the
nginx stream module (`nginx -V` must mention `stream`):

```nginx
stream {
    map $ssl_preread_server_name $sni_backend {
        web.dev 127.0.0.1:36878;   # Reality camouflage SNI
        default 127.0.0.1:4443;    # everything else -> web vhosts
    }
    server {
        listen 443;
        listen [::]:443;
        proxy_pass $sni_backend;
        ssl_preread on;            # peek at SNI, do NOT terminate TLS
    }
}
```

Add `include /etc/nginx/stream.conf;` at the top level of
`/etc/nginx/nginx.conf` (outside the `http {}` block).

Panel vhost — HTTPS served on `127.0.0.1:4443` only (public 443 belongs
to the stream router above):

```nginx
server {
    listen 127.0.0.1:4443 ssl;
    server_name panel.example.com;
    ssl_certificate /etc/letsencrypt/live/panel.example.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/panel.example.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;

    location /panel/ {
        proxy_pass http://127.0.0.1:2053/panel/;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    location / {
        proxy_pass http://127.0.0.1:2096;  # 3x-ui subscription service
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
}
```

CDN vhost — same `127.0.0.1:4443` listener, `server_name cdn.example.com`
with its own LE certificate:

```nginx
    location /vless {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;              # WebSocket needs HTTP/1.1
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_read_timeout 300s;
        proxy_send_timeout 300s;
    }
    location /xhttp {
        proxy_pass http://127.0.0.1:2089;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
    }
```

Both domains also need a port-80 server with
`location /.well-known/acme-challenge/ { root /var/www/html; }` so
certbot's `--webroot` issuance works without stopping nginx.

Classic layout (`--no-sni-routing`): identical vhosts, but
`listen 443 ssl;` on all interfaces and no `stream.conf`.

### UFW — manual rules

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp          # nginx stream (SNI router)
ufw allow 443/udp          # TUIC
ufw allow 2053/tcp         # x-ui panel
ufw allow 2096/tcp         # subscription service
ufw allow 36878/tcp        # Reality (direct fallback)
ufw allow 8443/tcp         # VLESS+WS
ufw allow 2087/tcp         # VLESS+gRPC
ufw allow 2089/tcp         # VLESS+XHTTP
ufw allow 40797/udp        # Hysteria2
ufw allow 58023/tcp        # Shadowsocks
ufw allow 58023/udp        # Shadowsocks
ufw default deny incoming  # optional, recommended
ufw enable
```

Remember: your cloud provider's network firewall is separate — open the
same ports there.

### Manual verification checklist

- [ ] `nginx -t` passes and `systemctl is-active nginx` → `active`
- [ ] `curl -sk -o /dev/null -w "%{http_code}\n" https://panel.example.com/panel/login` → `200`
- [ ] `ss -tln | grep -E ':(443|4443|2053|2096|36878|8443|2087|2089|58023) '` — every port listening
- [ ] `ss -uln | grep -E ':(443|40797|58023) '` — every UDP port listening
- [ ] `openssl x509 -checkend 0 -noout -in /etc/letsencrypt/live/panel.example.com/fullchain.pem`
- [ ] `sysctl -n net.ipv4.tcp_congestion_control` → `bbr`
- [ ] Panel UI → Inbounds: 7 inbounds present and enabled
- [ ] Panel UI → Server status: Xray `running`
- [ ] `sqlite3 /etc/x-ui/x-ui.db "SELECT remark,port,protocol FROM inbounds;"` lists all 7
- [ ] `curl -s https://panel.example.com/sub/<subId>` returns a client config
- [ ] End-to-end: import one client link into V2rayNG/Happ and load a page

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
