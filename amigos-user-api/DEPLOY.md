# Deploy: user-info API (VPS)

Read-only FastAPI service exposing per-user subscription data from the
3x-ui panel database: `GET /api/user/{username}` ->
`{"username","expiry","up","down","total"}`.
`expiry: 0` = lifetime, `total: 0` = unlimited.

On the VPS (as root), run:

## 1. Install files

```bash
mkdir -p /opt/amigos-user-api
cp app.py /opt/amigos-user-api/
# venv: avoids conflicts with Debian system packages
python3 -m venv /opt/amigos-user-api/venv
/opt/amigos-user-api/venv/bin/pip install fastapi uvicorn
cp amigos-user-api.service /etc/systemd/system/
setfacl -m u:www-data:r /etc/x-ui/x-ui.db
systemctl daemon-reload
systemctl enable --now amigos-user-api
systemctl status amigos-user-api --no-pager | head -12
```

## 2. Verify the API locally

```bash
# health
curl -s http://127.0.0.1:8899/api/health
# real user (replace USERNAME with a panel username, case as in panel)
curl -s "http://127.0.0.1:8899/api/user/USERNAME" | python3 -m json.tool
```

Expected: `{"username": "...", "expiry": 1798..., "up": ..., "down": ..., "total": ...}`.
Unknown user -> HTTP 404.

If `{"detail":"database unavailable"}`: the DB path is wrong —
find it: `find / -name "x-ui.db" 2>/dev/null` and edit `XUI_DB` in app.py.

## 3. Nginx

Insert `nginx-snippet.conf` into your panel domain's server block
(the `listen 443 ssl;` / `listen 4443 ssl;` one), before `location / {`:

```bash
python3 - <<'EOF'
p = '/etc/nginx/sites-enabled/panel.example.com'
s = open(p).read()
snippet = open('/opt/amigos-user-api/nginx-snippet.conf').read()
assert 'location /api/user/' not in s, "already present"
s = s.replace('    location / {', snippet + '\n    location / {', 1)
open(p, 'w').write(s)
print("inserted")
EOF
nginx -t && systemctl reload nginx
```

## 4. Verify externally

```bash
curl -s "https://panel.example.com/api/user/USERNAME" | python3 -m json.tool
```

If you get a cached response, purge that URL in Cloudflare (Custom Purge).

## Notes

- Read-only: the service never writes to the x-ui DB and never needs
  panel credentials.
- The endpoint is public (usernames are not secrets; the /sub/ links
  already work the same way). It only reveals expiry + traffic counters.
- x-ui panel upgrades that move the DB: update `XUI_DB` and restart.
