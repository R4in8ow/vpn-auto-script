# Troubleshooting

Symptom-first guide for servers built by `install.sh`. Start with the
built-in self-test — the installer already ran it once:

```bash
# re-run the checks any time (panel must be up):
curl -sk -o /dev/null -w "%{http_code}\n" https://<panel-domain>/panel/login
ss -tln | grep -E ':(443|4443|2053|2096|36878|8443|2087|2089|58023) '
ss -uln | grep -E ':(443|40797|58023) '
systemctl status x-ui --no-pager
```

## Symptoms

### Panel won't load (`https://<panel-domain>/panel/`)

| Check | Command |
|---|---|
| nginx config valid | `nginx -t` |
| nginx listening on 4443 (SNI mode) | `ss -tln \| grep 4443` |
| stream router on 443 (SNI mode) | `ss -tln \| grep ':443 '` |
| panel answering locally | `curl -sk -o /dev/null -w "%{http_code}" https://127.0.0.1:2053/panel/login` (try `http://` too) |
| cert files exist | `ls -l /etc/letsencrypt/live/<panel-domain>/` |

Common causes: DNS not pointing at the server yet; `proxy_pass` scheme
mismatch (the installer auto-detects http vs https — if you changed
`webCertFile` afterwards, re-check); another service already bound to
443 (the stream block needs it exclusively in SNI mode).

### Reality connects then times out

- Port not open in **both** UFW and the cloud provider's firewall.
  `ufw` is only the OS layer — DigitalOcean/AWS/Vultr have a separate
  network firewall, and a missing rule there is the #1 cause.
- If you use the SNI-routed 443 path, the client SNI must be exactly
  the configured Reality SNI (`web.dev` by default).

### CDN (WS/XHTTP) times out but Reality works

- Cloudflare SSL/TLS mode on the CDN domain must be **Full** or
  **Full (strict)** — "Flexible" makes Cloudflare speak plain HTTP to
  an nginx that only listens for HTTPS, and traffic dies silently.
- The inbound must have `security: none` (nginx already terminated
  TLS). If you recreated the inbound by hand with `security: tls`,
  that is the double-TLS trap — set it back to `none`.
- nginx must force `proxy_http_version 1.1` with the `Upgrade` headers
  for `/vless` (HTTP/2 to the upstream breaks the WS handshake).

### Hysteria2 / TUIC time out

- UDP ports must be open in UFW **and** the cloud firewall
  (`40797/udp`, `443/udp`).
- The inbound's TLS `serverName` must match the domain clients use,
  and the LE cert paths must exist.

### gRPC fails

- The inbound terminates TLS itself with the panel-domain cert; the
  client SNI must be the panel domain, and port 2087 must be reachable
  (it bypasses nginx entirely).

### Xray won't stay running after install

One malformed inbound stops the whole core. Find it:

```bash
journalctl -u x-ui --no-pager -n 100 | grep -i -A3 error
```

Then fix or delete the inbound in the panel and restart Xray
(panel UI → Server → Restart Xray, or
`POST /panel/api/server/restartXrayService`).

### Certbot failed during install

DNS A record not yet pointing at this server (or still propagating).
The installer uses `--webroot`, so nginx keeps running — just fix DNS
and re-run that one command:

```bash
certbot certonly --webroot -w /var/www/html -d <domain>
```

then `systemctl reload nginx`. The script is safe to re-run end to
end: sysctl/limits entries are appended once, existing inbounds are
matched by remark and skipped, valid certs are not reissued.

### `nginx -t` fails: "stream" directive unknown

Your nginx build lacks the stream module. Either install a full nginx
build (`apt install nginx-full`) or re-run with `--no-sni-routing`.

### Subscription shows the wrong Reality port (known limitation)

The subscription service currently renders Reality with its direct
port (36878). If clients connect via the SNI-routed public 443, change
the port to 443 in the client app after importing. Server-side
sanitization is on the roadmap (see README).

## Useful commands

```bash
x-ui                        # panel management menu (users, reset traffic…)
sqlite3 /etc/x-ui/x-ui.db "SELECT remark,port,protocol FROM inbounds;"
tail -f /usr/local/x-ui/logs/access.log
ufw status numbered
certbot certificates        # expiry overview
```

## Getting help

Open an issue at `https://github.com/R4in8ow/vpn-auto-script/issues`
with: Ubuntu version (`lsb_release -a`), installer mode (SNI or
classic), the failing symptom, and the relevant output above.
**Never paste `/root/vpn-credentials.env` or private keys.**
