# VPN Auto-Script

[![Ubuntu 24.04](https://img.shields.io/badge/Ubuntu-24.04%20%7C%2022.04-E95420?logo=ubuntu&logoColor=white)](https://ubuntu.com)
[![3x-ui](https://img.shields.io/badge/panel-3x--ui-blue)](https://github.com/MHSanaei/3x-ui)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Version](https://img.shields.io/badge/version-2.0.0-blueviolet)]()

> Read in English: [README.md](README.md)

Command တစ်ခု တည်း နဲ့ Ubuntu VPS အသစ် ကို censorship ကို ခံနိုင်ရည် ရှိတဲ့
VPN server အဖြစ် ပြောင်းလဲ ပေးပါတယ်။ Panel ထဲ မှာ လူ ကိုယ်တိုင် လိုက်နှိပ်
စရာ မလို ပါ — protocol inbound ၇ ခု လုံး ကို 3x-ui REST API ကနေ အလိုအလျောက်
ဖန်တီး ပေးပါတယ်။

## ဒါက ဘာလဲ

`install.sh` ဟာ production မှာ တကယ် သုံးနေ�ဲ့ stack အတိုင်း ပြင်ဆင် ပေးပါတယ် —

- **3x-ui** panel + Xray core (official installer ကနေ latest release)
- **Nginx** — SNI router အဖြစ် (public 443 ကို Reality နဲ့ web panel အတူ သုံးနိုင်) + TLS reverse proxy
- **Let's Encrypt** certificate — `--webroot` နဲ့ ထုတ် ပေးတာ မို့ nginx ရပ်စရာ မလို (zero downtime)
- **UFW** firewall, **BBR** tuning, 4G swap, file limit မြှင့်တ
င်, unattended security update, fail2ban (optional)

ပြီးသွား ရင် client တွေ ချက် ချင်း ချိတ် သုံး လို့ ရ ပါ ပြီ။

## လုပ်ဆောင် ချက်များ

- 🚀 **One-shot install အစစ်** — `git clone` + `sudo bash install.sh`
- 🔌 **Inbound ၇ ခု အလိုအလျောက်** — VLESS+Reality, VLESS+WS, VLESS+gRPC, VLESS+XHTTP, Hysteria2, Shadowsocks-2022, TUIC
- 🧭 **SNI routing** — public TCP/443 တစ်ခု တည်း ကို Reality (SNI `web.dev`) နဲ့ panel/CDN website တွေ အတူ သုံး နိုင်
- 🔑 **Install တိုင်း secret အသစ်** — Reality keypair, UUID, password တွေ ကို server ပေါ် မှာ ပဲ ထုတ် ပေး၊ hardcode လုံးဝ မရှိ
- 📦 **`.env` support** — prompt မဖြေချင် ရင် အလိုအလျောက် install
- ✅ **Self-test** — ပြီးသွား ရင် panel ရောက်/မရောက်, port တွေ နားထောင်/မထောင်, cert သက် တမ်း, Xray အခြေ အနေ, inbound အရေ အတွက် ကို စစ် ပေး
- 🧹 **`uninstall.sh`** — သွင်းထား သမျှ ပြန် ဖြုတ် နိုင်
- 🔒 **Repo ထဲ secret မရှိ** — placeholder သာ, `.env` ကို gitignore လုပ် ထား

## Architecture အကျဉ်း

```
public TCP/443 ── nginx stream (ssl_preread, TLS မ ဖြည်)
    ├─ SNI web.dev ──▶ 127.0.0.1:36878   (Xray Reality)
    └─ SNI အခြား   ──▶ 127.0.0.1:4443    (nginx HTTPS: panel + CDN vhosts)

public UDP/443 ──▶ Xray TUIC          public TCP/36878 ──▶ Xray Reality (အရန် လမ်း)
CDN ──TCP/8443/2087/2089──▶ Xray WS / gRPC / XHTTP
public UDP/40797 ──▶ Hysteria2        public 58023/tcp+udp ──▶ Shadowsocks-2022
```

အပြည့် အစုံ: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) (English)။

## လို အပ် ချက်များ

- Ubuntu **24.04** (22.04 လည်း ရ) VPS အသစ်, root access ရှိ
- Run မ ခင် DNS **A record** ၂ ခု ကို server IP ဆီ ညွှန် ထား ရ မယ် —
  - `panel.example.com` → server IP (DNS-only / grey-cloud ပို ကောင်း)
  - `cdn.example.com` → server IP (proxied / orange-cloud ရ — Cloudflare SSL/TLS mode ကို **Full** ထား, Flexible မ ထား ရ)

## အသုံး ပြု ပုံ

```bash
git clone https://github.com/R4in8ow/vpn-auto-script.git
cd vpn-auto-script
sudo bash install.sh
```

Prompt တွေ ကို ဖြေ သွား ရုံ ပဲ (domain, port, admin login)။ Prompt မ ဖြေချင် ရင် —

```bash
cp .env.example .env   # ကိုယ့် တန်ဖိုး တွေ ဖြည့်
sudo bash install.sh --non-interactive
```

Classic ပုံစံ လို ချင် ရင် (SNI router မ သုံး, nginx က public 443 ကို တိုက် ရိုက် ကိုင်) —
`sudo bash install.sh --no-sni-routing`။

## Configuration (`.env` variable များ)

| Variable | Default | အသုံး ဝင် ပုံ |
|---|---|---|
| `PANEL_DOMAIN` | — | Panel + subscription domain |
| `CDN_DOMAIN` | — | WS/XHTTP/gRPC အတွက် CDN domain |
| `SUB_DOMAIN` | panel domain | Subscription link ထဲ သုံး မယ့် host |
| `LE_EMAIL` | — | Let's Encrypt သတိ ပေး mail |
| `PANEL_PORT` | `2053` | x-ui panel port |
| `SUB_PORT` | `2096` | Subscription service port |
| `REALITY_PORT` | `36878` | Reality inbound (TCP) |
| `WS_PORT` | `8443` | VLESS+WS inbound (TCP) |
| `GRPC_PORT` | `2087` | VLESS+gRPC inbound (TCP) |
| `XHTTP_PORT` | `2089` | VLESS+XHTTP inbound (TCP) |
| `HY2_PORT` | `40797` | Hysteria2 inbound (UDP) |
| `SS_PORT` | `58023` | Shadowsocks inbound (TCP+UDP) |
| `TUIC_PORT` | `443` | TUIC inbound (UDP) |
| `REALITY_DEST` | `web.dev:443` | Reality အယောင် ဆောင် destination |
| `REALITY_SNI` | `web.dev` | Reality SNI / serverName |
| `ADMIN_USER` / `ADMIN_PASS` | — | Panel login (အနည်း ဆုံး 8 လုံး) |
| `SNI_ROUTING` | `yes` | `no` ဆို classic 443 ပုံစံ |
| `INSTALL_FAIL2BAN` | `no` | SSH brute-force ကာ ကွယ် ရေး |
| `UFW_DEFAULT_DENY` | `no` | UFW default-deny incoming |

## Protocol များ

| Inbound | Port | Transport | Client credential |
|---|---|---|---|
| VLESS + Reality | 36878/tcp (SNI နဲ့ ဆို 443) | tcp + reality, uTLS chrome | UUID + `xtls-rprx-vision` |
| VLESS + WS (CDN) | 8443/tcp | ws, path `/vless`, nginx မှာ TLS ဖြည် | UUID |
| VLESS + gRPC | 2087/tcp | grpc, service `vless-grpc`, TLS | UUID |
| VLESS + XHTTP | 2089/tcp | xhttp, path `/xhttp` | UUID |
| Hysteria2 | 40797/udp | TLS | password |
| Shadowsocks 2022 | 58023/tcp+udp | `2022-blake3-aes-128-gcm` | password |
| TUIC | 443/udp | TLS, congestion `bbr` | password |

Credential အား လုံး ကို install လုပ် တုန်း က ထုတ် ပေး�ြီး `/root/vpn-credentials.env`
(permission 600, root သာ ဖတ် နိုင်) မှာ သိမ်း ထား ပေး ပါ တယ်။
Happ, V2rayNG, V2rayTun, Hiddify, Karing, Outline, Streisand, Nekoray တို့ နဲ့ သုံး နိုင်။

## Manual settings (လက် နဲ့ ပြင် ဆင် ရန် လမ်း ညွှန်)

Installer က အောက် က အား လုံး ကို အလိုအလျောက် လုပ် ပေး ပါ တယ်။
ဒီ အပိုင်း ကတော့ automation က ရေး သွား တဲ့ **တန်ဖိုး အတိ အကျ တွေ နဲ့
ဘယ် နေ ရာ မှာ ရောက် သွား လဲ** ဆို တာ ကို မှတ် တမ်း တင် ထား တာ ဖြစ် လို့
လူ ကိုယ် တိုင် အစ က နေ ပြန် လုပ် ချင် / စစ် ချင် / ပြင် ချင် ရင် ဒါ ကို
ကြည့် ပြီး လုပ် နိုင် ပါ တယ်။ တန်ဖိုး အား လုံး က installer default တွေ —
ကိုယ့် domain/port နဲ့ အ စား ထိုး သုံး ပါ။

### Secret တွေ ကို လက် နဲ့ ထုတ် ရန်

```bash
# Reality x25519 keypair ("Password" ဆို တဲ့ လိုင်း က client တွေ မှာ
# ထည့် ရမယ့် public key, private key က server ပေါ် မှာ သာ ထား)
/usr/local/x-ui/bin/xray-linux-amd64 x25519

# Reality shortId (hex 16 လုံး)
openssl rand -hex 8

# Client UUID များ (VLESS inbound တစ် ခု မှာ တစ် ခု)
cat /proc/sys/kernel/random/uuid

# Hysteria2 / TUIC client password (စာ လုံး 16 လုံး)
openssl rand -base64 16 | tr -d '/+=' | cut -c1-16

# Shadowsocks 2022-blake3-aes-128-gcm password: 16 byte အတိ အကျ ကို
# base64 နဲ့ ပြောင်း ထား တာ (ဖြတ် မ ပစ် ရ — cipher က 16 byte အပြည့် လို)
openssl rand -base64 16
```

### x-ui panel settings

Panel UI ထဲ က **Panel Settings** မှာ ပြင် နိုင်။ Command နဲ့ ဆို —

| Setting | တန် ဖိုး | လက် နဲ့ ပြင် ရန် |
|---|---|---|
| Panel port | `2053` | `x-ui setting -port 2053` |
| Web Base Path | `/panel/` | `x-ui setting -webBasePath /panel/` |
| Public Key Path | `/etc/letsencrypt/live/panel.example.com/fullchain.pem` | Panel Settings → SSL |
| Private Key Path | `/etc/letsencrypt/live/panel.example.com/privkey.pem` | Panel Settings → SSL |
| Admin username / password | ကိုယ့် စိတ် ကြိုက် (အနည်း ဆုံး 8 လုံး) | `x-ui setting -username … -password …` |

Subscription (Panel Settings → Subscription):

| Key | တန် ဖိုး |
|---|---|
| Enable subscription | true |
| Subscription port | `2096` |
| Subscription path | `/sub/` |
| Subscription URI | `https://panel.example.com/sub/` |
| Subscription domain | `panel.example.com` |

Port (သို့) base path ပြောင်း ပြီး ရင် `systemctl restart x-ui` လုပ် ရ
မယ်။ ပြီးရင် panel က `https://panel.example.com/panel/` မှာ ရောက် ပါ
မယ်, subscription link က `https://panel.example.com/sub/<subId>` ပုံစံ
ဖြစ် ပါ မယ်။

### Inbound များ — လက် နဲ့ ဖြည့် ရမယ့် field များ

**Inbounds → Add Inbound** က နေ တစ် ခု ချင်း ဖန် တီး။ စ စ ချင်း inbound
တစ် ခု မှာ bootstrap client တစ် ခု ပါ ရင် လုံ လောက် ပါ တယ်, နောက် မှ
user အစစ် တွေ ကို သက် တမ်း/traffic limit နဲ့ ထည့် ပါ။

**1. Reality** — VLESS, TCP `36878`
- Network `tcp`, Security `reality`
- Dest `web.dev:443`, ServerNames/SNI `web.dev`, xver `0`
- Private Key: `<xray x25519 က ထုတ်>` , Short IDs: `<hex 16 လုံး>`
- uTLS fingerprint `chrome`
- Client: UUID, Flow `xtls-rprx-vision`
- Sniffing: enabled, destOverride `http,tls,quic,fakedns`

**2. CDN-Vless** — VLESS, TCP `8443`
- Network `ws`, Security `none` (nginx က TLS ဖြည် ပြီး သား မို့ `tls`
  ထား ရင် double-TLS ဖြစ် ပြီး ပျက် တတ် တယ် — ဒါ က အဖြစ် များ တဲ့ အ မှား)
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
- TLS serverName `panel.example.com`, အပေါ် က LE cert/key အတူ တူ, ALPN `h3`
- Client: password နဲ့ စစ်

**6. Outline** — shadowsocks, TCP+UDP `58023`
- Method `2022-blake3-aes-128-gcm`
- Password: 16 random byte ကို base64 ပြောင်း ထား တာ (အပေါ် က နည်း)
- Network `tcp,udp`

**7. TUIC** — tuic, UDP `443`
- TLS serverName `panel.example.com`, အပေါ် က LE cert/key, ALPN `h3`
- Congestion control `bbr`
- Client: password နဲ့ စစ်

### nginx — လက် နဲ့ ပြင် ဆင် ရန်

`/etc/nginx/stream.conf` — public TCP/443 SNI router။ nginx မှာ stream
module ပါ ရ မယ် (`nginx -V` မှာ `stream` ပါ ကြောင်း စစ်):

```nginx
stream {
    map $ssl_preread_server_name $sni_backend {
        web.dev 127.0.0.1:36878;   # Reality အယောင် SNI
        default 127.0.0.1:4443;    # ကျန် တာ မှန် သ မျှ -> web vhosts
    }
    server {
        listen 443;
        listen [::]:443;
        proxy_pass $sni_backend;
        ssl_preread on;            # SNI ကို ချောင်း ကြည့် ရုံ, TLS မ ဖြည်
    }
}
```

`/etc/nginx/nginx.conf` ရဲ့ top level (`http {}` အပြင် ဘက်) မှာ
`include /etc/nginx/stream.conf;` ထည့် ရ မယ်။

Panel vhost — HTTPS ကို `127.0.0.1:4443` မှာ သာ နား ထောင် (public 443 က
stream router ပိုင်):

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

CDN vhost — listener `127.0.0.1:4443` အတူ တူ, `server_name cdn.example.com`
(ကိုယ့် LE cert သက် သက်):

```nginx
    location /vless {
        proxy_pass http://127.0.0.1:8443;
        proxy_http_version 1.1;              # WebSocket က HTTP/1.1 လို
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

Domain နှစ် ခု လုံး မှာ port-80 server တစ် ခု စီ လို ပါ တယ် —
`location /.well-known/acme-challenge/ { root /var/www/html; }` ပါ ရ
မယ်, ဒါ မှ certbot `--webroot` က nginx မ ရပ် ပဲ cert ထုတ် နိုင် မှာ။

Classic ပုံစံ (`--no-sni-routing`): vhost တွေ အတူ တူ ပဲ, ဒါ ပေ မယ့်
`listen 443 ssl;` (interface အား လုံး) ထား ပြီး `stream.conf` မ လို။

### UFW — လက် နဲ့ ဖွင့် ရမယ့် rule များ

```bash
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp          # nginx stream (SNI router)
ufw allow 443/udp          # TUIC
ufw allow 2053/tcp         # x-ui panel
ufw allow 2096/tcp         # subscription service
ufw allow 36878/tcp        # Reality (တိုက် ရိုက် အရန် လမ်း)
ufw allow 8443/tcp         # VLESS+WS
ufw allow 2087/tcp         # VLESS+gRPC
ufw allow 2089/tcp         # VLESS+XHTTP
ufw allow 40797/udp        # Hysteria2
ufw allow 58023/tcp        # Shadowsocks
ufw allow 58023/udp        # Shadowsocks
ufw default deny incoming  # optional, ထား သင့်
ufw enable
```

သတိ ရ ရန်: cloud provider ရဲ့ network firewall သက် သက် ရှိ ပါ သေး တယ် —
အဲဒီ မှာ လည်း port တွေ အတူ တူ ဖွင့် ရ မယ်။

### လက် နဲ့ စစ် ဆေး ရန် checklist

- [ ] `nginx -t` အောင်, `systemctl is-active nginx` → `active`
- [ ] `curl -sk -o /dev/null -w "%{http_code}\n" https://panel.example.com/panel/login` → `200`
- [ ] `ss -tln | grep -E ':(443|4443|2053|2096|36878|8443|2087|2089|58023) '` — port တိုင်း နား ထောင် နေ
- [ ] `ss -uln | grep -E ':(443|40797|58023) '` — UDP port တိုင်း နား ထောင် နေ
- [ ] `openssl x509 -checkend 0 -noout -in /etc/letsencrypt/live/panel.example.com/fullchain.pem`
- [ ] `sysctl -n net.ipv4.tcp_congestion_control` → `bbr`
- [ ] Panel UI → Inbounds: 7 ခု လုံး ရှိ, enable ဖြစ်
- [ ] Panel UI → Server status: Xray `running`
- [ ] `sqlite3 /etc/x-ui/x-ui.db "SELECT remark,port,protocol FROM inbounds;"` — 7 ခု လုံး ပေါ်
- [ ] `curl -s https://panel.example.com/sub/<subId>` — client config ရ
- [ ] အဆုံး သတ်: client link တစ် ခု ကို V2rayNG/Happ ထဲ သွင်း ပြီး page ဖွင့် ကြည့်

## Install ပြီး စစ် ဆေး ရန်

Installer က ပြီးသွား ရင် self-test လုပ် ပြီး သား (panel HTTPS ရောက်/မရောက်,
TCP/UDP port တွေ, cert သက် တမ်း, Xray `running`, inbound 7/7, BBR)။
နောက် မှ ပြန် စစ် ချင် ရင် [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)
ထဲ က command တွေ သုံး ပါ။

## ပြဿနာ ဖြေ ရှင်း ရန် (အကျဉ်း)

| လက္ခ ဏာ | ဖြစ် နိုင် ခြေ အများ ဆုံး |
|---|---|
| Panel ဖွင့် မရ | DNS မ ရောက် သေး; cloud firewall မှာ port ပိတ် ထား |
| Reality ချိတ် ပြီး timeout | Provider firewall မှာ port မ ဖွင့် (UFW ဖွင့် ရုံ နဲ့ မ လုံ လောက်) |
| Reality ရ WS မရ | Cloudflare SSL mode "Flexible" ဖြစ် နေ — Full ပြောင်း |
| Hysteria2/TUIC timeout | UDP port မ ဖွင့် (UFW + cloud firewall နှစ် ခု လုံး) |
| Xray ရပ် ရပ် သွား | Inbound တစ် ခု မှား နေ — `journalctl -u x-ui` ကြည့် |

အပြည့် အစုံ: [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) (English)။

## လုံ ခြုံ ရေး မှတ် ချက်

- **Repo ထဲ မှာ credential, domain, IP, email, key လုံးဝ မရှိ ပါ။**
  အား လုံး ကို prompt (သို့) ကိုယ့် `.env` (gitignore) က နေ ပဲ ယူ ပါ တယ်။
  ထုတ် ပေး ထား တဲ့ secret တွေ က server ပေါ် မှာ သာ ရှိ ပါ တယ်။
- တကယ် သုံး တော့ မယ် ဆို bootstrap client တွေ ကို ပြန် ဖျက်/ပြင် ပြီး
  user အစစ် တွေ ကို သက် တမ်း + traffic limit နဲ့ panel ထဲ မှာ ထည့် ပါ
  (inbound တစ် ခု မှာ bootstrap client တစ် ခု စီ ပါ ပါ တယ်)။
- `UFW_DEFAULT_DENY=yes` ထား ပြီး fail2ban သွင်း ဖို့ စဉ်း စား ပါ။
- `/root/vpn-credentials.env` (600) ကို လုံ ခြုံ တဲ့ နေ ရာ မှာ backup ယူ ထား ပါ။

## Cloud firewall သတိ ပေး ချက်

UFW က OS အဆင့် firewall သာ။ DigitalOcean, AWS, Vultr တို့ မှာ
**network အဆင့် firewall သက် သက် ရှိ** ပါ သေး တယ် — အဲဒီ မှာ လည်း
TCP/UDP port တွေ ကို ဖွင့် ပေး ရ မယ်။ မ ဖွင့် ရင် connection တွေ
တိတ် တိတ် လေး timeout ဖြစ် နေ မှာ ပါ။ "ဖုန်း ထဲ က ချိတ် မ ရ" ဆို တာ ရဲ့
အ ကြောင်း ရင်း နံပါတ် တစ် ဒါ ပဲ ဖြစ် ပါ တယ်။

## အပို tools

Installer နဲ့ အတူ ပါ တဲ့ ရွေး ချယ် စရာ tool 2 ခု (secret မ ပါ, ဘာ server
မ ဆို သုံး လို့ ရ):

- [`verify-free-servers/`](verify-free-servers/) — အပတ် တိုင်း third-party
  VLESS/Trojan node တွေ ကို xray-core နဲ့ handshake စစ် ပြီး
  `free-servers.json` ထုတ် ပေး တာ။ `INSTALL.md` ကြည့်။
- [`amigos-user-api/`](amigos-user-api/) — 3x-ui database က နေ user တစ် ဦး
  ချင်း ရဲ့ expiry/traffic ကို ထုတ် ပေး တဲ့ read-only FastAPI service
  (`GET /api/user/{username}`), systemd unit နဲ့ nginx snippet ပါ တယ်။
  `DEPLOY.md` ကြည့်။

## Roadmap

- [ ] Subscription သန့် စင် ရေး (server ဘက် က) — လက် ရှိ Reality ရဲ့
      တိုက် ရိုက် port ပေါ် နေ တယ် (known limitation)
- [ ] User အများ provisioning helper script
- [ ] Cloudflare Tunnel mode (port ဖွင့် စရာ မ လို တဲ့ ပုံစံ)

## ပြန် ဖြုတ် ရန်

```bash
sudo bash uninstall.sh          # ဖျက် ခင် တစ် ခု ချင်း မေး ပါ တယ်
sudo bash uninstall.sh --yes    # မ မေး ပဲ ဖျက်
```

## ပါဝင် ကူ ညီ ရန်

Issue / PR တွေ ကြို ဆို ပါ တယ်။ Secret စည်း ကမ်း ကို လိုက် နာ ပါ —
domain, IP, email, password, key, UUID တွေ ကို ဘယ် တော့ မှ commit မ
တင် ရ, `example.com` placeholder သုံး ပါ။ Push မ လုပ် ခင် shell file
တိုင်း ကို `bash -n` နဲ့ စစ် ပါ။

## စမ်း သပ် မှု မှတ် ချက်

Script တိုင်း `bash -n` syntax check အောင် ပါ တယ် (ရ ရင် shellcheck
ပါ)။ VPS အသစ် ပေါ် မှာ အစ အဆုံး run တော့ CI မှာ မ စမ်း ရ သေး ပါ —
စမ်း ပြီး ရင် Ubuntu version + SNI/classic mode ကို issue မှာ ပြော ပြ ပေး ပါ။

## License

MIT — [LICENSE](LICENSE) ကြည့် ပါ။
