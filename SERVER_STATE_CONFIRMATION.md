# Reference Server — Confirmed State
_Generated from a live production VPN server inventory_

This document confirms exactly what was installed and configured on the
**reference** server this installer was built from, so the setup can be
replicated cleanly on a fresh server without dragging along anything
specific to that one deployment.

All domain names below are placeholders (`panel.yourdomain.com`,
`cdn.yourdomain.com`, etc.) — substitute your own.

---

## 1. Base System

- **OS**: Ubuntu 24.04 LTS
- **RAM**: ~2 GiB (fairly tight — recommend 2 GiB+ on the new server, or
  keep services minimal)
- **Swap**: 4 GiB swapfile, configured
- **BBR**: enabled (`net.ipv4.tcp_congestion_control=bbr`)
- **File limits**: raised to 655350 (nofile/nproc) in `/etc/security/limits.conf`

> Note: sysctl tuning lines appeared duplicated in `/etc/sysctl.conf` on
> the reference server (applied twice across separate setup sessions) —
> harmless but messy. This installer checks before appending, so re-runs
> won't duplicate entries.

---

## 2. Web Server (Nginx) — VPN-Relevant Sites Only

| Domain (placeholder) | Purpose | Backend |
|---|---|---|
| `panel.yourdomain.com` | x-ui panel + subscription bot | `127.0.0.1:2053` (panel), `127.0.0.1:2096` (sub bot) |
| `cdn.yourdomain.com` | VLESS+WS CDN fallback protocol | `127.0.0.1:2083` |

All HTTPS sites have HTTP→HTTPS redirects in place.

> The reference server also ran several unrelated services on other
> domains (a portfolio site, an internal automation tool, a file-download
> endpoint). Those are **not part of this installer** and are omitted
> here — see Section 9 for why.

---

## 3. SSL Certificates (Let's Encrypt via Certbot)

Active certs confirmed for the panel and CDN domains, with auto-renewal
via `certbot.timer` (systemd) confirmed active.

---

## 4. VPN Core: x-ui (3x-ui)

- **Install path**: `/usr/local/x-ui/`
- **Panel port**: configurable (default 2053)
- **Panel SSL**: terminated by x-ui itself, pointed at the issued
  Let's Encrypt cert paths
- **Service**: `x-ui.service`, enabled, running

### Inbounds configured on the reference server:

| Remark | Port | Protocol | Notes |
|---|---|---|---|
| Reality | (custom TCP port) | vless | TCP, Reality security, dest `www.microsoft.com:443` |
| CDN | 2083 | vless | WS, security `none` (TLS terminated by Nginx), path `/vless`, host = CDN domain |
| Hysteria | (custom UDP port) | hysteria2 | UDP, TLS via Let's Encrypt cert |

### Known issue fixed on the reference server (already handled by this installer):
- The CDN inbound originally had `security: tls`, causing a double-TLS
  conflict with Nginx (which already terminates TLS for that domain).
  Fixed by setting `security: none` on the inbound itself, since Nginx
  forwards plain WebSocket traffic to it after terminating TLS.
- The CDN Nginx vhost forces `proxy_http_version 1.1` (WebSocket requires
  HTTP/1.1 upgrade semantics; HTTP/2 to the upstream breaks the
  handshake), and does **not** use `http2` on the `listen` directive for
  that reason.

---

## 5. Firewall (UFW)

The reference server had UFW active with a fairly loose default-allow
policy and a long list of ad-hoc port rules accumulated over time.

**This installer instead opens only what's strictly needed**:

```
22/tcp        (SSH)
80/tcp, 443/tcp, 443/udp
<panel port>/tcp
<CDN port>/tcp
<sub port>/tcp
8443/tcp, 8443/udp   (placeholder — adjust to your actual Reality/Hysteria2 ports after creating inbounds)
```

> Recommendation: after creating your Reality and Hysteria2 inbounds in
> the panel, open their specific ports and consider switching UFW's
> default policy to **deny incoming**, only allow-listing what's needed,
> rather than accumulating rules ad-hoc as the reference server did.

---

## 6. Cloud Firewall Reminder

`ufw` only controls the OS-level firewall. Most cloud providers
(DigitalOcean, AWS, Vultr, etc.) also enforce a **separate network-level
firewall**. Any custom port opened for an inbound (Reality TCP port,
Hysteria2 UDP port) must be allowed there too, or connections will
silently time out — this was confirmed as the root cause of a
multi-hour debugging session on the reference server.

---

## 7. Cloudflare Note (if using Cloudflare for your CDN domain)

If your CDN domain's DNS record is "Proxied" (orange cloud) on
Cloudflare, set **SSL/TLS mode to "Full" or "Full (strict)"** — not
"Flexible". Flexible mode causes Cloudflare to talk to your origin over
plain HTTP, which does not match an Nginx vhost that only listens on
443/SSL, and traffic silently fails.

---

## 8. What Caused Each Symptom (debugging log from the reference server)

| Symptom | Root cause | Fix |
|---|---|---|
| Nginx `502 Bad Gateway` on panel domain | Nginx proxy_pass pointed at the wrong internal port | Match `proxy_pass` port to the actual listening service port |
| CDN protocol times out, Reality/panel work fine | CDN inbound had `security: tls`, double-TLS conflict with Nginx | Set inbound `security: none`; Nginx alone terminates TLS |
| CDN still resets after fixing TLS setting | Nginx forwarded to upstream as HTTP/2 | Force `proxy_http_version 1.1` and drop `http2` from the `listen` directive |
| Hysteria2 times out from client | UDP port not open in cloud firewall (even though `ufw` allowed it) | Open the port in the cloud provider's firewall dashboard too |
| High RAM/CPU usage | An old, unused VPN panel was still running alongside the new one, with its own Xray process | Stop and disable the unused service entirely |

---

## 9. Summary: What's VPN-relevant vs. Not

**Directly part of the VPN setup** (replicated by `install.sh`):
- BBR/sysctl tuning, file limits
- Nginx + Certbot
- x-ui panel + the 3 inbound types (Reality, CDN/WS, Hysteria2)
- UFW rules for the VPN ports specifically

**NOT part of the VPN setup** (specific to the reference server's other
roles — intentionally excluded from this installer):
- Any Docker-based automation stack
- Any PHP/portfolio/static sites
- Any internal apps with IP-restricted access
- Any file-download servers
- Any unrelated cron jobs or certificate tooling (e.g. acme.sh)

`install.sh` only replicates the **VPN-relevant** pieces, so it runs
clean on a fresh server without pulling in infrastructure specific to
one particular deployment.
