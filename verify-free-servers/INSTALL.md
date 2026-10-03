# verify-free-servers

Weekly prober that finds working third-party VLESS/Trojan backup nodes and
writes them to `/var/www/html/free-servers.json` for VPN apps to consume.

How it works:
1. Fetches public VLESS/Trojan lists (configurable `SOURCES` in the script).
2. For each candidate, runs a **real xray-core handshake** (not just TCP-open).
3. Fetches `http://cp.cloudflare.com/` through the tunnel, expects HTTP 204.
4. Keeps up to 6 working nodes, writes `free-servers.json`.

The script downloads xray-core itself on first run (needs `curl`, `unzip`).

## Install (one block, as root)

```bash
mkdir -p /opt/amigos-free-servers
cp verify_free_servers.py /opt/amigos-free-servers/
chmod 755 /opt/amigos-free-servers/verify_free_servers.py
mkdir -p /var/www/html
touch /var/log/amigos-free-servers.log
# Sundays 03:00
( crontab -l 2>/dev/null | grep -v "verify_free_servers.py" ; \
  echo "0 3 * * 0 /usr/bin/python3 /opt/amigos-free-servers/verify_free_servers.py >> /var/log/amigos-free-servers.log 2>&1" ) | crontab -
# test run now:
/usr/bin/python3 /opt/amigos-free-servers/verify_free_servers.py
```

## Serve the JSON

Point your web server at `/var/www/html/free-servers.json`
(e.g. nginx `location = /free-servers.json { root /var/www/html; expires 5m; }`).
If behind Cloudflare, custom-purge the URL after each refresh.
