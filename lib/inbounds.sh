#!/bin/bash
# ============================================================================
# lib/inbounds.sh — 3x-ui inbound definitions + REST API client
# Sourced by install.sh after lib/common.sh. Requires: curl, jq.
#
# API research notes (verified against MHSanaei/3x-ui docs, Oct 2026):
#   - Login:  POST {basePath}/login  (form-encoded username/password,
#             no CSRF token required for form login)
#   - Add:    POST {basePath}/panel/api/inbounds/add   (JSON body)
#   - List:   GET  {basePath}/panel/api/inbounds/list
#   - Restart Xray: POST {basePath}/panel/api/server/restartXrayService
#   - Status: GET  {basePath}/panel/api/server/status
#   - settings / streamSettings / sniffing may be nested JSON objects
#     (preferred on 3x-ui v3.x) or JSON-encoded strings (legacy).
# With webBasePath=/panel/ the API root is therefore:
#   http://127.0.0.1:<port>/panel/panel/api
# ============================================================================

# --- API session -------------------------------------------------------------
# Globals set by install.sh before calling: PANEL_PORT, ADMIN_USER,
# ADMIN_PASS, PANEL_SCHEME (http|https, probed at runtime).
XUI_COOKIE_JAR=""

xui_api_root() {
    # webBasePath is /panel/ -> API lives under /panel/panel/api
    printf '%s://127.0.0.1:%s/panel/panel/api' "${PANEL_SCHEME:-http}" "$PANEL_PORT"
}

xui_login() {
    XUI_COOKIE_JAR="$(mktemp /tmp/xui-cookies.XXXXXX)"
    local form_file
    form_file="$(mktemp /tmp/xui-login.XXXXXX)"
    {
        printf 'username='
        printf '%s' "$ADMIN_USER" | jq -sRr @uri | tr -d '\n'
        printf '&password='
        printf '%s' "$ADMIN_PASS" | jq -sRr @uri | tr -d '\n'
    } > "$form_file"  # credentials stay out of the process table

    local curl_opts=(-s -c "$XUI_COOKIE_JAR" -X POST
        --data-binary "@${form_file}")
    if [[ "${PANEL_SCHEME:-http}" == "https" ]]; then
        curl_opts+=(-k)
    fi

    local resp
    resp=$(curl "${curl_opts[@]}" \
        "${PANEL_SCHEME:-http}://127.0.0.1:${PANEL_PORT}/panel/login")
    rm -f "$form_file"

    if echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
        info "Panel API login OK."
        return 0
    fi
    error "Panel API login failed: $(echo "$resp" | jq -r '.msg // .' 2>/dev/null | head -c 200)"
    return 1
}

# xui_post PATH JSON_PAYLOAD -> prints response body, returns curl status
xui_post() {
    local path="$1" payload="$2"
    local payload_file
    payload_file="$(mktemp /tmp/xui-payload.XXXXXX)"
    printf '%s' "$payload" > "$payload_file"
    local curl_opts=(-s -b "$XUI_COOKIE_JAR" -X POST
        -H 'Content-Type: application/json' -H 'Accept: application/json'
        --data-binary "@${payload_file}")
    if [[ "${PANEL_SCHEME:-http}" == "https" ]]; then
        curl_opts+=(-k)
    fi
    curl "${curl_opts[@]}" "$(xui_api_root)${path}"
    local rc=$?
    rm -f "$payload_file"
    return $rc
}

xui_get() {
    local path="$1"
    local curl_opts=(-s -b "$XUI_COOKIE_JAR" -H 'Accept: application/json')
    if [[ "${PANEL_SCHEME:-http}" == "https" ]]; then
        curl_opts+=(-k)
    fi
    curl "${curl_opts[@]}" "$(xui_api_root)${path}"
}

# --- Inbound payload builders (each prints the JSON for /inbounds/add) -------
# Globals consumed: ports, domains, generated keys/uuids/passwords.

_inbound_skeleton() {
    # $1 remark, $2 port, $3 protocol
    jq -n --arg remark "$1" --argjson port "$2" --arg protocol "$3" '{
        remark: $remark, enable: true, expiryTime: 0,
        listen: "", port: $port, protocol: $protocol,
        up: 0, down: 0, total: 0
    }'
}

build_inbound_reality() {
    _inbound_skeleton "Reality" "$REALITY_PORT" "vless" | jq \
        --arg uuid "$UUID_REALITY" \
        --arg priv "$REALITY_PRIVKEY" \
        --arg sid "$REALITY_SHORTID" \
        --arg dest "$REALITY_DEST" \
        --arg sni "$REALITY_SNI" \
        '. + {
            settings: {
                clients: [{id: $uuid, flow: "xtls-rprx-vision",
                           email: "reality-user", limitIp: 0, totalGB: 0,
                           expiryTime: 0, enable: true, tgId: "", subId: ""}],
                decryption: "none", fallbacks: []
            },
            streamSettings: {
                network: "tcp", security: "reality",
                realitySettings: {
                    show: false, dest: $dest, xver: 0,
                    serverNames: [$sni], privateKey: $priv,
                    minClient: "", maxClient: "", maxTimediff: 0,
                    shortIds: [$sid]
                },
                tcpSettings: {acceptProxyProtocol: false,
                              header: {type: "none"}}
            },
            sniffing: {enabled: true,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

build_inbound_ws() {
    _inbound_skeleton "CDN-Vless" "$WS_PORT" "vless" | jq \
        --arg uuid "$UUID_WS" \
        --arg host "$CDN_DOMAIN" \
        '. + {
            settings: {
                clients: [{id: $uuid, email: "cdn-user", limitIp: 0,
                           totalGB: 0, expiryTime: 0, enable: true,
                           tgId: "", subId: ""}],
                decryption: "none", fallbacks: []
            },
            streamSettings: {
                network: "ws", security: "none",
                wsSettings: {acceptProxyProtocol: false,
                             path: "/vless", headers: {Host: $host}}
            },
            sniffing: {enabled: true,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

build_inbound_grpc() {
    _inbound_skeleton "CDN-gRPC" "$GRPC_PORT" "vless" | jq \
        --arg uuid "$UUID_GRPC" \
        --arg sni "$PANEL_DOMAIN" \
        --arg cert "/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem" \
        --arg key "/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem" \
        '. + {
            settings: {
                clients: [{id: $uuid, email: "grpc-user", limitIp: 0,
                           totalGB: 0, expiryTime: 0, enable: true,
                           tgId: "", subId: ""}],
                decryption: "none", fallbacks: []
            },
            streamSettings: {
                network: "grpc", security: "tls",
                tlsSettings: {
                    serverName: $sni, minVersion: "1.2", maxVersion: "1.3",
                    certificates: [{certificateFile: $cert, keyFile: $key,
                                    ocspStapling: 3600}],
                    alpn: ["h2","http/1.1"]
                },
                grpcSettings: {serviceName: "vless-grpc", multiMode: false}
            },
            sniffing: {enabled: true,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

build_inbound_xhttp() {
    _inbound_skeleton "XHTTP" "$XHTTP_PORT" "vless" | jq \
        --arg uuid "$UUID_XHTTP" \
        '. + {
            settings: {
                clients: [{id: $uuid, email: "xhttp-user", limitIp: 0,
                           totalGB: 0, expiryTime: 0, enable: true,
                           tgId: "", subId: ""}],
                decryption: "none", fallbacks: []
            },
            streamSettings: {
                network: "xhttp", security: "none",
                xhttpSettings: {path: "/xhttp", host: "", mode: "auto",
                                extra: {noSSEHeader: false, noGRPCHeader: false,
                                        xmux: {maxConcurrency: "16-32",
                                               maxConnections: 0,
                                               cMaxReuseTimes: 0,
                                               hMaxRequestTime: "0s",
                                               hMaxReusableSecs: "0",
                                               hKeepAlivePeriod: "0"}}}
            },
            sniffing: {enabled: true,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

build_inbound_hysteria2() {
    _inbound_skeleton "Hysteria2" "$HY2_PORT" "hysteria2" | jq \
        --arg pass "$HY2_PASSWORD" \
        --arg sni "$PANEL_DOMAIN" \
        --arg cert "/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem" \
        --arg key "/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem" \
        '. + {
            settings: {
                clients: [{password: $pass, email: "hy2-user"}]
            },
            streamSettings: {
                network: "udp", security: "tls",
                tlsSettings: {
                    serverName: $sni, minVersion: "1.2", maxVersion: "1.3",
                    certificates: [{certificateFile: $cert, keyFile: $key,
                                    ocspStapling: 3600}],
                    alpn: ["h3"]
                }
            },
            sniffing: {enabled: false,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

build_inbound_shadowsocks() {
    _inbound_skeleton "Outline" "$SS_PORT" "shadowsocks" | jq \
        --arg pass "$SS_PASSWORD" \
        '. + {
            settings: {
                clients: [{method: "2022-blake3-aes-128-gcm", password: $pass,
                           email: "ss-user", limitIp: 0, totalGB: 0,
                           expiryTime: 0, enable: true, tgId: "", subId: ""}],
                network: "tcp,udp"
            },
            streamSettings: {network: "tcp,udp", security: "none"},
            sniffing: {enabled: false,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

build_inbound_tuic() {
    _inbound_skeleton "TUIC" "$TUIC_PORT" "tuic" | jq \
        --arg pass "$TUIC_PASSWORD" \
        --arg sni "$PANEL_DOMAIN" \
        --arg cert "/etc/letsencrypt/live/${PANEL_DOMAIN}/fullchain.pem" \
        --arg key "/etc/letsencrypt/live/${PANEL_DOMAIN}/privkey.pem" \
        '. + {
            settings: {
                clients: [{password: $pass, email: "tuic-user"}],
                congestion_control: "bbr"
            },
            streamSettings: {
                network: "udp", security: "tls",
                tlsSettings: {
                    serverName: $sni, minVersion: "1.2", maxVersion: "1.3",
                    certificates: [{certificateFile: $cert, keyFile: $key,
                                    ocspStapling: 3600}],
                    alpn: ["h3"]
                }
            },
            sniffing: {enabled: false,
                       destOverride: ["http","tls","quic","fakedns"]}
        }'
}

# --- Bulk creation -----------------------------------------------------------
# Creates every missing inbound (matched by remark, so re-runs are safe).
# Sets INBOUND_FAILURES (array) with remarks that could not be created.
INBOUND_FAILURES=()

create_all_inbounds() {
    local builders=(
        "Reality:build_inbound_reality"
        "CDN-Vless:build_inbound_ws"
        "CDN-gRPC:build_inbound_grpc"
        "XHTTP:build_inbound_xhttp"
        "Hysteria2:build_inbound_hysteria2"
        "Outline:build_inbound_shadowsocks"
        "TUIC:build_inbound_tuic"
    )

    local existing
    existing="$(xui_get "/inbounds/list" | jq -r '.obj[]?.remark // empty' 2>/dev/null)"

    local entry remark builder payload resp ok
    for entry in "${builders[@]}"; do
        remark="${entry%%:*}"
        builder="${entry#*:}"
        if echo "$existing" | grep -qx "$remark"; then
            info "Inbound '$remark' already exists, skipping."
            continue
        fi
        info "Creating inbound '$remark'..."
        payload="$($builder)"
        resp="$(xui_post "/inbounds/add" "$payload" || true)"
        ok="$(echo "$resp" | jq -r '.success // false' 2>/dev/null)"
        if [[ "$ok" == "true" ]]; then
            local new_id
            new_id="$(echo "$resp" | jq -r '.obj.id // "?"' 2>/dev/null)"
            info "Inbound '$remark' created (id $new_id)."
        else
            error "Failed to create inbound '$remark': $(echo "$resp" | jq -r '.msg // .' 2>/dev/null | head -c 300)"
            INBOUND_FAILURES+=("$remark")
        fi
    done
}

# Verify the TUIC inbound kept our congestion_control setting (the panel may
# strip unknown fields when it re-serializes settings).
verify_tuic_congestion() {
    local settings
    settings="$(xui_get "/inbounds/list" | jq -r '.obj[] | select(.remark=="TUIC") | .settings' 2>/dev/null)"
    if [[ -z "$settings" || "$settings" == "null" ]]; then
        warn "TUIC inbound not found, cannot verify congestion control."
        return 1
    fi
    if echo "$settings" | grep -q 'bbr'; then
        info "TUIC congestion control 'bbr' confirmed in stored settings."
        return 0
    fi
    warn "Panel stripped the TUIC congestion_control field; Xray will use its default."
    return 1
}

xui_restart_xray() {
    info "Restarting Xray core via panel API..."
    local resp
    resp="$(xui_post "/server/restartXrayService" '{}')"
    if ! echo "$resp" | jq -e '.success == true' >/dev/null 2>&1; then
        warn "Xray restart request failed: $(echo "$resp" | jq -r '.msg // .' 2>/dev/null | head -c 200)"
        return 1
    fi
    sleep 5
    local state
    state="$(xui_get "/server/status" | jq -r '.obj.xray.state // .obj.xrayState // "unknown"' 2>/dev/null)"
    info "Xray state after restart: $state"
    [[ "$state" == "running" ]]
}
