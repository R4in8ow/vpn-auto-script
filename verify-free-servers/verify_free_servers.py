#!/usr/bin/env python3
import base64, json, os, re, socket, subprocess, time, urllib.parse, urllib.request
WORKDIR = "/opt/amigos-free-servers"
XRAY = os.path.join(WORKDIR, "xray")
OUT_JSON = "/var/www/html/free-servers.json"
SOCKS_PORT = 10808
MAX_WINNERS = 6
TEST_URL = "http://cp.cloudflare.com/"
SOURCES = {
    "vless": "https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/vless.txt",
    "trojan": "https://raw.githubusercontent.com/Epodonios/v2ray-configs/main/Splitted-By-Protocol/trojan.txt",
}
def fetch_uris(url):
    req = urllib.request.Request(url, headers={"User-Agent": "amigos-verifier/1.0"})
    raw = urllib.request.urlopen(req, timeout=60).read().decode().strip()
    try: raw = base64.b64decode(raw).decode("utf-8", errors="replace")
    except Exception: pass
    return [l.strip() for l in raw.splitlines() if l.strip()]
def ensure_xray():
    if os.path.exists(XRAY): return
    print("downloading xray...", flush=True)
    subprocess.run(["curl","-sL","--max-time","120","https://github.com/XTLS/Xray-core/releases/latest/download/Xray-linux-64.zip","-o",os.path.join(WORKDIR,"xray.zip")], check=True)
    subprocess.run(["unzip","-o","-q",os.path.join(WORKDIR,"xray.zip"),"xray","-d",WORKDIR], check=True)
    os.chmod(XRAY, 0o755)
def split_uri(uri):
    m = re.match(r"^([a-z0-9]+)://(.*)$", uri)
    if not m: return None
    scheme, body = m.group(1), m.group(2)
    remark = ""
    if "#" in body: body, remark = body.split("#", 1); remark = urllib.parse.unquote(remark)
    if "?" in body: main, qs = body.split("?", 1); params = dict(urllib.parse.parse_qsl(qs, keep_blank_values=True))
    else: main, params = body, {}
    m2 = re.match(r"^(.*)@([^@/:]+):(\d+)$", main)
    if not m2: return None
    return scheme, m2.group(1), m2.group(2), int(m2.group(3)), params, remark
def stream_settings(p, host):
    security = p.get("security", "tls" if "sni" in p or "pbk" in p else "none")
    net = p.get("type", "tcp")
    s = {"network": net, "security": security}
    if security == "tls":
        tls = {"serverName": p.get("sni", host)}
        if p.get("fp"): tls["fingerprint"] = p["fp"]
        if p.get("alpn"): tls["alpn"] = p["alpn"].split(",")
        s["tlsSettings"] = tls
    elif security == "reality":
        rs = {"serverName": p.get("sni", host), "fingerprint": p.get("fp","chrome"), "publicKey": p.get("pbk",""), "shortId": p.get("sid","")}
        if p.get("spx"): rs["spiderX"] = p["spx"]
        s["realitySettings"] = rs
    if net == "ws":
        ws = {"path": p.get("path", "/")}
        if p.get("host"): ws["headers"] = {"Host": p["host"]}
        s["wsSettings"] = ws
    elif net == "grpc":
        s["grpcSettings"] = {"serviceName": p.get("serviceName",""), "authority": p.get("authority","")}
    return s
def build_config(uri):
    parts = split_uri(uri)
    if not parts: return None
    scheme, userinfo, host, port, p, _ = parts
    if scheme == "vless":
        user = {"id": userinfo, "encryption": p.get("encryption","none")}
        if p.get("flow"): user["flow"] = p["flow"]
        outbound = {"protocol":"vless","settings":{"vnext":[{"address":host,"port":port,"users":[user]}]},"streamSettings":stream_settings(p,host)}
    elif scheme == "trojan":
        outbound = {"protocol":"trojan","settings":{"servers":[{"address":host,"port":port,"password":urllib.parse.unquote(userinfo)}]},"streamSettings":stream_settings(p,host)}
    else: return None
    return {"inbounds":[{"port":SOCKS_PORT,"protocol":"socks","settings":{}}],"outbounds":[outbound]}
def test_uri(uri, timeout=15):
    cfg = build_config(uri)
    if cfg is None: return False
    cfg_path = os.path.join(WORKDIR, "test.json")
    with open(cfg_path, "w") as f: json.dump(cfg, f)
    proc = subprocess.Popen([XRAY,"-c",cfg_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        time.sleep(1.5)
        if proc.poll() is not None: return False
        r = subprocess.run(["curl","-s","-o","/dev/null","-w","%{http_code}","--socks5-hostname",f"127.0.0.1:{SOCKS_PORT}","--max-time",str(timeout),TEST_URL], capture_output=True, text=True, timeout=timeout+5)
        return r.stdout.strip() == "204"
    except Exception: return False
    finally:
        proc.terminate()
        try: proc.wait(timeout=3)
        except Exception: proc.kill()
def geo(ip_or_host):
    try:
        req = urllib.request.Request(f"http://ip-api.com/json/{ip_or_host}?fields=status,country,countryCode,query", headers={"User-Agent":"amigos-verifier/1.0"})
        d = json.loads(urllib.request.urlopen(req, timeout=10).read())
        if d.get("status") == "success": return d.get("country","Unknown"), d.get("countryCode","")
    except Exception: pass
    return "Unknown", ""
def main():
    os.makedirs(WORKDIR, exist_ok=True)
    ensure_xray()
    all_uris = []
    for proto, url in SOURCES.items():
        try:
            uris = fetch_uris(url); print(f"{proto}: {len(uris)} links", flush=True)
            all_uris += [(proto,u) for u in uris if u.startswith(proto+"://")]
        except Exception as e: print(f"{proto} fetch failed: {e}", flush=True)
    step = max(1, len(all_uris)//150); cands = all_uris[::step][:150]
    print(f"testing {len(cands)} candidates...", flush=True)
    winners = []
    for i,(proto,uri) in enumerate(cands):
        parts = split_uri(uri)
        if not parts: continue
        _,_,host,port,_,_ = parts
        try: s=socket.create_connection((host,port),timeout=6); s.close()
        except Exception: continue
        if test_uri(uri):
            country,cc = geo(host)
            winners.append({"region":country,"country_code":cc,"name":f"{cc or proto.upper()} Free #{len(winners)+1}","type":proto,"link":uri})
            print(f"WINNER #{len(winners)}: {host}:{port} ({country})", flush=True)
            if len(winners) >= MAX_WINNERS: break
        time.sleep(0.2)
    out = {"updated_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()), "verifier":"handshake-verified via xray (real VLESS/Trojan handshake + HTTP fetch)", "servers": winners}
    tmp = OUT_JSON+".tmp"
    with open(tmp,"w") as f: json.dump(out,f,indent=2)
    os.replace(tmp, OUT_JSON); os.chmod(OUT_JSON, 0o644)
    print(f"wrote {OUT_JSON} with {len(winners)} working servers", flush=True)
if __name__ == "__main__": main()
