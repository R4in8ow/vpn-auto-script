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
