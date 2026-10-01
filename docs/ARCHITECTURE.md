# Architecture

How the vpn-auto-script v2.0 server is put together, and why each piece
exists. All hostnames/ports below are the installer defaults — your
actual values live in your `.env` / install answers.

## Big picture

```
                        ┌──────────────── VPS ────────────────┐
                        │                                     │
Internet ──TCP 443──▶   │  nginx stream (ssl_preread)         │
                        │   SNI=web.dev ──▶ 127.0.0.1:36878   │──▶ Xray: Reality
                        │   SNI=other   ──▶ 127.0.0.1:4443    │
                        │                                     │
Internet ──UDP 443──▶   │──────────────▶ Xray: TUIC (443/udp) │
Internet ──TCP 36878─▶  │──────────────▶ Xray: Reality (direct fallback)
Internet ──TCP 8443──▶  │──(CDN proxy)─▶ Xray: VLESS+WS (8443, security=none)
Internet ──TCP 2087──▶  │──(CDN proxy)─▶ Xray: VLESS+gRPC (2087, TLS)
Internet ──TCP 2089──▶  │──(CDN proxy)─▶ Xray: VLESS+XHTTP (2089, none)
Internet ──UDP 40797─▶  │──────────────▶ Xray: Hysteria2 (40797/udp, TLS)
Internet ──58023/tcp+udp▶│─────────────▶ Xray: Shadowsocks-2022
                        │                                     │
                        │  nginx http (127.0.0.1:4443, TLS)   │
                        │   panel.example.com/panel/ ──▶ 127.0.0.1:2053/panel/
                        │   panel.example.com/       ──▶ 127.0.0.1:2096 (subs)
                        │   cdn.example.com/vless    ──▶ 127.0.0.1:8443 (WS)
                        │   cdn.example.com/xhttp    ──▶ 127.0.0.1:2089 (XHTTP)
                        └─────────────────────────────────────┘
```

## The SNI router (default layout)

Public TCP/443 is owned by an **nginx stream** block, not by any HTTPS
server. It uses `ssl_preread` to peek at the TLS ClientHello's SNI
**without terminating TLS**, then proxies the raw bytes:

| SNI | Backend |
|---|---|
| `web.dev` (the Reality camouflage domain) | `127.0.0.1:36878` — Xray Reality inbound |
| anything else | `127.0.0.1:4443` — nginx HTTPS vhosts |

Why this exists:

- **Reality needs port 443** to look like a normal website, but the
  panel/CDN websites also need 443. SNI routing lets both share it.
- The Reality inbound only completes handshakes for clients presenting
  the right keys; anything else falls through to the real `web.dev:443`
  (the `dest` setting), so probes see an ordinary website.
- Direct TCP/36878 stays open as a fallback that needs no SNI routing.

Run the installer with `--no-sni-routing` for the classic layout
(nginx HTTPS directly on public 443, Reality on its own high port).

## TLS termination map

| Listener | TLS terminated by | Notes |
|---|---|---|
| `stream :443` | nobody (`ssl_preread` only) | byte proxy |
| `127.0.0.1:4443` (panel + CDN vhosts) | nginx, Let's Encrypt certs | |
| Xray `:2087` (gRPC) | Xray itself, panel-domain LE cert | direct, bypasses nginx |
| Xray `:40797/udp` (Hysteria2) | Xray itself, panel-domain LE cert | direct |
| Xray `:443/udp` (TUIC) | Xray itself, panel-domain LE cert | direct |
| Xray `:8443` (WS), `:2089` (XHTTP) | nginx (upstream is plain) | inbound `security=none` |

The classic double-TLS trap: if the WS/XHTTP inbound had `security=tls`
*and* nginx terminated TLS, handshakes would fail. The installer sets
`security=none` on exactly those two inbounds.

## The 7 inbounds

| # | Remark | Port | Protocol | Transport / security | Client auth |
|---|---|---|---|---|---|
| 1 | Reality | 36878/tcp | vless | tcp + reality (`web.dev:443`, uTLS chrome) | UUID, `xtls-rprx-vision` flow |
| 2 | CDN-Vless | 8443/tcp | vless | ws + none, path `/vless` | UUID |
| 3 | CDN-gRPC | 2087/tcp | vless | grpc + tls, service `vless-grpc` | UUID |
| 4 | XHTTP | 2089/tcp | vless | xhttp + none, path `/xhttp` | UUID |
| 5 | Hysteria2 | 40797/udp | hysteria2 | tls (LE cert) | password |
| 6 | Outline | 58023/tcp+udp | shadowsocks | `2022-blake3-aes-128-gcm` | password (16 random bytes, base64) |
| 7 | TUIC | 443/udp | tuic | tls (LE cert), congestion `bbr` | password |

Secrets (Reality keypair, UUIDs, passwords, SS key) are generated fresh
on every install and saved root-only to `/root/vpn-credentials.env`.

## 3x-ui panel wiring

- `webPort` = panel port (default 2053), `webBasePath` = `/panel/`,
  so the UI/API live under `https://<panel-domain>/panel/`.
- `webCertFile`/`webKeyFile` point at the panel domain's LE cert. The
  installer probes whether the panel answers HTTP or HTTPS on
  `127.0.0.1:<port>` and configures nginx's `proxy_pass` (and its own
  API calls) accordingly — no assumption either way.
- Subscription service: `subEnable=true`, `subPort=2096`,
  `subPath=/sub/`, `subURI=https://<sub-domain>/sub/`,
  `subDomain=<sub-domain>`. nginx maps `/` → `127.0.0.1:2096`.
- Inbounds are created through the panel's REST API
  (`POST /login` → `POST /panel/api/inbounds/add`, cookie session),
  verified via `/panel/api/inbounds/list`, then Xray is restarted via
  `/panel/api/server/restartXrayService` and its `running` state is
  asserted. Anything the API rejects is reported with the panel's own
  error message instead of failing silently.

## System hardening bits

- **BBR** (`net.ipv4.tcp_congestion_control=bbr`, fq qdisc) — generic
  BBR as shipped by the Ubuntu kernel. (Not "BBRv3": that name refers
  to newer out-of-tree builds; this installer makes no such claim.)
- **4G swapfile** at `/swapfile` (created only if no swap is active).
- **File limits**: `nofile`/`nproc` 655350 in `/etc/security/limits.conf`.
- **UFW**: opens exactly the ports the installer uses; optionally sets
  default-deny incoming (prompted).
- **unattended-upgrades** enabled for security updates.
- Optional **fail2ban** for SSH.

## What this installer deliberately does NOT do

- It does not manage your **cloud provider's network firewall**
  (DigitalOcean Cloud Firewall, AWS Security Groups, …). You must open
  the same ports there — see the README's cloud-firewall reminder.
- It does not create client accounts beyond one bootstrap client per
  inbound. Real user provisioning (expiry, traffic caps) is done in
  the panel or via its API.
- It does not sanitize the subscription output (Reality's direct port
  is exposed there today) — documented as a known limitation with a
  roadmap entry.
