#!/bin/bash
set -e

REPO_URL="https://github.com/w3struk/serv.git"
INSTALL_DIR="${SERV_INSTALL_DIR:-/opt/serv}"

# ─── Self-loading bootstrap ──────────────────────────────
LAUNCH_DIR="$(cd "$(dirname "$0")" && pwd -P 2>/dev/null || echo "/dev/null")"
if [ ! -f "$LAUNCH_DIR/docker-compose.yml" ]; then
    [ "$EUID" -ne 0 ] && { echo "[ERROR] Run as root"; exit 1; }

    if ! command -v git &>/dev/null; then
        echo "Installing git..."
        if command -v apt-get &>/dev/null; then
            apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq git
        elif command -v dnf &>/dev/null; then
            dnf install -y git
        elif command -v yum &>/dev/null; then
            yum install -y git
        elif command -v apk &>/dev/null; then
            apk add --no-cache git
        else
            echo "[ERROR] git is required. Install git manually and re-run."
            exit 1
        fi
    fi

    if [ -d "$INSTALL_DIR/.git" ]; then
        cd "$INSTALL_DIR" && git fetch origin main && git reset --hard origin/main
    elif [ -d "$INSTALL_DIR" ]; then
        echo "[ERROR] $INSTALL_DIR exists but is not a git repository. Remove it first."
        exit 1
    else
        mkdir -p "$(dirname "$INSTALL_DIR")"
        git clone --depth 1 --branch main "$REPO_URL" "$INSTALL_DIR"
    fi

    exec "$INSTALL_DIR/setup.sh" "$@"
fi

# ─── Normal startup ──────────────────────────────────────
if [ "$EUID" -ne 0 ]; then
    echo -e "\033[0;31m[ERROR]\033[0m Run as root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SERVER_DIR="$SCRIPT_DIR"

# Colors
R="\033[0;31m"
G="\033[0;32m"
Y="\033[0;33m"
C="\033[0;36m"
B="\033[1m"
N="\033[0m"

API_PREFIX=""
VLESS_FLOW="xtls-rprx-vision"
VLESS_CLIENT_ENCRYPTION=""
VLESS_SERVER_DECRYPTION="none"

ensure_jq() {
    if command -v jq >/dev/null 2>&1; then
        return 0
    fi

    echo -e "${Y}jq not found. Installing jq...${N}"
    local installed=false
    if command -v apt-get >/dev/null 2>&1; then
        if apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y jq; then
            installed=true
        fi
    elif command -v dnf >/dev/null 2>&1; then
        if dnf install -y jq; then
            installed=true
        fi
    elif command -v yum >/dev/null 2>&1; then
        if yum install -y jq; then
            installed=true
        fi
    elif command -v apk >/dev/null 2>&1; then
        if apk add --no-cache jq; then
            installed=true
        fi
    else
        echo -e "${R}[ERROR]${N} jq is required, but no supported package manager was found. Install jq manually and rerun this script."
        exit 1
    fi

    if [ "$installed" != "true" ] || ! command -v jq >/dev/null 2>&1; then
        echo -e "${R}[ERROR]${N} jq installation failed. Install jq manually and rerun this script."
        exit 1
    fi
}

persist_firewall() {
    # Save the just-applied iptables rules so they survive a reboot.
    # Mechanism differs per distro family. Best-effort: failure warns but
    # does not abort (live rules already work until reboot).
    if command -v apt-get >/dev/null 2>&1; then
        # Debian/Ubuntu: iptables-persistent -> netfilter-persistent service.
        # Preseed autosave=false so install is non-interactive and does NOT
        # capture whatever rules happen to be loaded right now.
        printf 'iptables-persistent iptables-persistent/autosave_v4 boolean false\niptables-persistent iptables-persistent/autosave_v6 boolean false\n' \
            | debconf-set-selections 2>/dev/null || true
        if DEBIAN_FRONTEND=noninteractive apt-get install -y -qq iptables-persistent; then
            mkdir -p /etc/iptables
            local v4_saved=false v6_saved=true
            if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
                v4_saved=true
            else
                echo -e "  ${Y}Warning:${N} iptables-persistent installed but IPv4 rules save failed."
            fi
            if [ "${IPV6_FIREWALL_CONFIGURED:-false}" = "true" ]; then
                if ip6tables-save > /etc/iptables/rules.v6 2>/dev/null; then
                    v6_saved=true
                else
                    v6_saved=false
                    echo -e "  ${Y}Warning:${N} IPv6 rules save failed."
                fi
            fi
            if [ "$v4_saved" = "true" ] && [ "$v6_saved" = "true" ]; then
                if command -v systemctl >/dev/null 2>&1 && systemctl enable netfilter-persistent >/dev/null 2>&1; then
                    if [ "${IPV6_FIREWALL_CONFIGURED:-false}" = "true" ]; then
                        echo -e "  ${G}Firewall rules persisted (IPv4 and IPv6, netfilter-persistent)${N}"
                    else
                        echo -e "  ${G}Firewall rules persisted (IPv4, netfilter-persistent)${N}"
                    fi
                else
                    echo -e "  ${Y}Warning:${N} Rules were saved but boot service could not be enabled; rules may not survive reboot."
                fi
            fi
        else
            echo -e "  ${Y}Warning:${N} Could not install iptables-persistent; rules will not survive reboot."
        fi
    elif command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; then
        local pm_install_ok=false
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y iptables-services && pm_install_ok=true
        else
            yum install -y iptables-services && pm_install_ok=true
        fi
        if [ "$pm_install_ok" = "true" ]; then
            if iptables-save > /etc/sysconfig/iptables 2>/dev/null; then
                if command -v systemctl >/dev/null 2>&1 && systemctl enable iptables >/dev/null 2>&1; then
                    echo -e "  ${G}Firewall rules persisted (iptables service)${N}"
                else
                    echo -e "  ${Y}Warning:${N} Rules saved to /etc/sysconfig/iptables but boot service could not be enabled; rules may not survive reboot."
                fi
            else
                echo -e "  ${Y}Warning:${N} iptables-services installed but rules save failed."
            fi
        else
            echo -e "  ${Y}Warning:${N} Could not install iptables-services; rules will not survive reboot."
        fi
    elif command -v apk >/dev/null 2>&1; then
        # Alpine: OpenRC iptables service loads /etc/iptables/rules-save at boot
        apk add --no-cache iptables >/dev/null || true
        if [ -f /etc/conf.d/iptables ]; then
            sed -i 's/SAVE_ON_STOP="yes"/SAVE_ON_STOP="no"/' /etc/conf.d/iptables || true
        fi
        mkdir -p /etc/iptables
        if iptables-save > /etc/iptables/rules-save 2>/dev/null; then
            if rc-update add iptables boot >/dev/null 2>&1; then
                echo -e "  ${G}Firewall rules persisted (OpenRC iptables)${N}"
            else
                echo -e "  ${Y}Warning:${N} Rules saved to /etc/iptables/rules-save but boot service could not be enabled; rules may not survive reboot."
            fi
        else
            echo -e "  ${Y}Warning:${N} Rules save failed; rules will not survive reboot."
        fi
    else
        echo -e "  ${Y}Warning:${N} Unknown distro — cannot persist firewall rules. Run iptables-save manually."
    fi
}

jq_success() {
    jq -e '.success == true' >/dev/null 2>&1
}

jq_all_success() {
    jq -s -e 'length > 0 and all(.[]; .success == true)' >/dev/null 2>&1
}

IPV6_FIREWALL_CONFIGURED=false

# API helpers (use API_PREFIX for non-install modes like add-client)
csrf_token() {
    curl -s --max-time 5 -b "$COOKIE_FILE" -c "$COOKIE_FILE" "http://127.0.0.1:2053${API_PREFIX}/csrf-token" \
        | jq -r '.obj // empty' 2>/dev/null
}

xui_json() {
    local url="$1" json="$2"
    local token
    token=$(csrf_token)
    printf '%s' "$json" | curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "X-CSRF-Token: $token" \
        --data-binary @-
}

xui_get_json() {
    local url="$1"
    local token
    token=$(csrf_token)
    curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X GET "$url" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "X-CSRF-Token: $token"
}

xui_login() {
    local u="$1" p="$2"
    local csrf form
    csrf=$(csrf_token)
    [ -z "$csrf" ] && return 1
    form=$(jq -nr --arg username "$u" --arg password "$p" \
        '{username: $username, password: $password} | to_entries | map("\(.key)=\(.value | @uri)") | join("&")') || return 1
    local resp
    resp=$(printf '%s' "$form" | curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -X POST "http://127.0.0.1:2053${API_PREFIX}/login" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "X-CSRF-Token: $csrf" \
        --data-binary @-)
    echo "$resp" | jq_success
}

generate_vlessenc_pair() {
    local resp pair dec enc

    if ! resp=$(xui_get_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/server/getNewVlessEnc"); then
        echo -e "${R}[ERROR]${N} Failed to request VLESS Encryption pair from 3x-ui" >&2
        return 1
    fi

    pair=$(echo "$resp" | jq -r '
        if .success != true then empty
        else
            (.obj.auths // []) as $auths
            | (($auths | map(select((.id // "") == "mlkem768"))[0]) // $auths[0])
            | select(.decryption and .encryption)
            | [.decryption, .encryption]
            | @tsv
        end
    ' 2>/dev/null || true)
    dec=${pair%%$'\t'*}
    enc=${pair#*$'\t'}

    if [ -z "$pair" ] || [ "$dec" = "$enc" ] || [ -z "$dec" ] || [ -z "$enc" ]; then
        echo -e "${R}[ERROR]${N} Could not parse VLESS Encryption pair from 3x-ui response" >&2
        return 1
    fi

    VLESS_SERVER_DECRYPTION="$dec"
    VLESS_CLIENT_ENCRYPTION="$enc"
}

# Convert an uppercase ISO alpha-2 code to regional-indicator symbols.
country_code_to_flag() {
    local code="$1" first second
    [[ "$code" =~ ^[A-Z]{2}$ ]] || return 1
    printf -v first '\\U%08x' "$((0x1F1E6 + $(printf '%d' "'${code:0:1}") - 65))"
    printf -v second '\\U%08x' "$((0x1F1E6 + $(printf '%d' "'${code:1:1}") - 65))"
    printf -v first '%b' "$first"
    printf -v second '%b' "$second"
    [ -n "$first" ] && [ -n "$second" ] || return 1
    printf '%s%s\n' "$first" "$second"
}

get_xhttp_remark() {
    local country_code flag
    # Keep only the validated code; the public IP response is never retained.
    country_code=$(curl -4fsS --connect-timeout 3 --max-time 8 --retry 2 --retry-delay 1 --retry-max-time 20 \
        'https://ipwho.is/' 2>/dev/null \
        | jq -r 'select(.success == true and (.country_code | type) == "string" and (.country_code | test("^[A-Z]{2}$"))) | .country_code' \
        2>/dev/null || true)
    if flag=$(country_code_to_flag "$country_code") && [ -n "$flag" ]; then
        printf '%s %s · VLESS-XHTTP\n' "$flag" "$country_code"
    else
        printf '%s\n' 'VLESS-XHTTP'
    fi
}

build_xhttp_payload() {
    jq -nc \
        --arg path "/$1" \
        --arg advanced_obfs "$2" \
        --arg server_decryption "$3" \
        --arg client_encryption "$4" \
        --arg remark "$5" \
        --arg listener "${6:-@uds_xhttp}" '
        def xhttp_settings:
            {
                path: $path,
                mode: "stream-up",
                headers: {"User-Agent": "chrome"},
                xPaddingBytes: "100-1000",
                sessionIDTable: "Base62",
                sessionIDLength: "16-32",
                scStreamUpServerSecs: "20-80",
                scMaxBufferedPosts: 30,
                xmux: {
                    maxConcurrency: 0,
                    maxConnections: "6",
                    cMaxReuseTimes: 0,
                    hMaxRequestTimes: "600-900",
                    hMaxReusableSecs: "1800-3000",
                    hKeepAlivePeriod: 0
                }
            } + if $advanced_obfs == "true" then {
                xPaddingObfsMode: true,
                xPaddingKey: "trace",
                xPaddingHeader: "X-Trace-ID",
                xPaddingPlacement: "queryInHeader",
                xPaddingMethod: "tokenish",
                serverMaxHeaderBytes: 16384
            } else {} end;
        {
            up: 0,
            down: 0,
            total: 0,
            remark: $remark,
            enable: true,
            expiryTime: 0,
            listen: $listener,
            port: 0,
            protocol: "vless",
            settings: ({
                clients: [],
                decryption: $server_decryption,
                encryption: $client_encryption
            } | tojson),
            streamSettings: ({
                network: "xhttp",
                security: "none",
                sockopt: {acceptProxyProtocol: true, trustedXForwardedFor: ["127.0.0.1/32"]},
                xhttpSettings: xhttp_settings,
                finalmask: {}
            } | tojson),
            sniffing: ({
                enabled: true,
                destOverride: ["http", "tls"],
                routeOnly: true
            } | tojson),
            allocate: ({
                strategy: "always",
                refresh: 5,
                concurrency: 3
            } | tojson)
        }'
}

build_host_payload() {
    jq -nc \
        --argjson inbound_id "$1" \
        --arg domain "$2" \
        '{
            inboundIds: [$inbound_id],
            hosts: [$domain],
            remark: "public",
            isDisabled: false,
            port: 443,
            security: "tls",
            sni: $domain,
            path: "",
            alpn: ["h2", "http/1.1"],
            fingerprint: "chrome"
        }'
}

build_client_payload() {
    jq -nc \
        --arg email "$1" \
        --arg client_id "$2" \
        --arg sub_id "$3" \
        --arg flow "$4" \
        --arg inbound_ids "$5" '
        {
            client: ({
                email: $email,
                id: $client_id,
                subId: $sub_id,
                enable: true,
                limitIp: 0,
                totalGB: 0,
                expiryTime: 0,
                tgId: 0
            }
            + if $flow != "" then {flow: $flow} else {} end),
            inboundIds: ($inbound_ids | split(",") | map(tonumber))
        }'
}

select_xhttp_inbound() {
    jq -c '
        def object_or_empty:
            if type == "object" then .
            elif type == "string" then (fromjson? // {})
            else {} end;

        [.obj[]?
            | . as $inbound
            | ($inbound.streamSettings | object_or_empty) as $stream
            | select(
                (($inbound.protocol // "") == "vless")
                and (($inbound.listen // "") == "@uds_xhttp")
                and ((($inbound.port // 0) | tostring) == "0")
                and (($stream.network // "") == "xhttp")
            )
        ] as $candidates
        | [$candidates[] | select((.remark // "") | contains("VLESS-XHTTP"))] as $named
        | {
            candidateCount: ($candidates | length),
            namedCount: ($named | length),
            inbound: (
                if ($named | length) == 1 then $named[0]
                elif (($named | length) == 0 and ($candidates | length) == 1) then $candidates[0]
                else null end
            )
        }
    '
}

xhttp_inbound_has_vlessenc() {
    jq -r '
        def object_or_empty:
            if type == "object" then .
            elif type == "string" then (fromjson? // {})
            else {} end;

        (.inbound.settings | object_or_empty) as $settings
        | if (((($settings.decryption // "") != "") and (($settings.decryption // "") != "none"))
              and ((($settings.encryption // "") != "") and (($settings.encryption // "") != "none")))
          then "true" else "false" end
    '
}

# Check if docker services are running
check_installed() {
    docker compose ls --filter "name=serv" 2>/dev/null | grep -q "serv" && return 0
    return 1
}

caddy_redir_domain() {
    sed -n '/redir/p' "$SERVER_DIR/Caddyfile" 2>/dev/null | grep -oP 'https://\K[^{}]+' | head -1 | sed 's/{uri} permanent//' || true
}

caddy_handle_path() {
    local pattern="$1"
    grep -oP "$pattern" "$SERVER_DIR/Caddyfile" 2>/dev/null | head -1 | sed 's/handle \///' || true
}

caddy_admin_prefix_segment() {
    grep -oP 'handle /\K[^/]+' "$SERVER_DIR/Caddyfile" 2>/dev/null | grep '^admin-' | head -1 || true
}

print_banner() {
    echo ""
    echo -e "${C}╔══════════════════════════════════════╗${N}"
    echo -e "${C}║   ${B}steal-oneself Server Setup${N}${C}        ║${N}"
    echo -e "${C}╚══════════════════════════════════════╝${N}"
    echo ""
}

print_summary() {
    echo ""
    echo -e "${G}╔══════════════════════════════════════╗${N}"
    echo -e "${G}║     ${B}Setup Complete${N}${G}                 ║${N}"
    echo -e "${G}╚══════════════════════════════════════╝${N}"
    echo ""
    echo -e "${B}URLs:${N}"
    echo -e "  ${C}Panel:${N}  https://${C}$DOMAIN${N}/$ADMIN_PATH/"
    echo ""
    if [ -n "${SUB_ID:+x}" ]; then
        echo -e "${B}XHTTP Subscription:${N}"
        echo -e "  ${C}VLESS:${N} https://${C}$DOMAIN${N}/$SUB_PATH/$SUB_ID"
        echo -e "  ${C}JSON:${N}  https://${C}$DOMAIN${N}/$JSON_PATH/$SUB_ID"
        echo -e "  ${C}Clash:${N} https://${C}$DOMAIN${N}/$CLASH_PATH/$SUB_ID"
        echo ""
    fi
    echo -e "${B}Credentials:${N}"
    echo -e "  ${Y}Web Auth:${N} admin / [your password]"
    echo -e "  ${Y}3x-ui:${N}    $XUI_USER / ${G}$XUI_PASS${N}"
    if [ -n "$CLIENT_ID" ]; then
        echo -e "  ${Y}XHTTP UUID:${N} ${C}$CLIENT_ID${N}"
    fi
    if [ -n "$XHTTP_PATH" ]; then
        echo -e "  ${Y}XHTTP path:${N} /$XHTTP_PATH/"
    fi
    if [ -n "$VLESS_CLIENT_ENCRYPTION" ] && [ "$VLESS_CLIENT_ENCRYPTION" != "none" ]; then
        echo -e "  ${Y}VLESS Encryption:${N} ${G}enabled${N}"
        echo -e "  ${Y}XTLS flow:${N} ${C}$VLESS_FLOW${N}"
        echo -e "  ${Y}Client encryption:${N} ${C}$VLESS_CLIENT_ENCRYPTION${N}"
        echo -e "  ${Y}Note:${N} client encryption is stored in inbound settings for subscription rendering."
    fi
    echo ""
    echo -e "${Y}Note: Certificates might take a minute to generate.${N}"
    echo ""
}

add_client() {
    print_banner
    echo -e "${G}Adding new client to existing installation...${N}"
    echo ""

    check_installed || {
        echo -e "${R}[ERROR]${N} Installation not found. Run without arguments to install."
        exit 1
    }

    read -p "3x-ui Username: " XUI_USER
    read -s -p "3x-ui Password: " XUI_PASS
    echo ""

    DOMAIN=$(caddy_redir_domain)

    local ADM=$(caddy_admin_prefix_segment)
    API_PREFIX="/$ADM"

    COOKIE_FILE=$(mktemp)
    if ! xui_login "$XUI_USER" "$XUI_PASS"; then
        echo -e "${R}[ERROR]${N} Login failed"
        rm "$COOKIE_FILE"
        exit 1
    fi
    echo -e "${G}Logged in${N}"

    read -p "Enter client email/purpose (or press Enter for auto): " CLIENT_EMAIL
    echo ""

    local csrf

    get_inbound_ids() {
        local csrf; csrf=$(csrf_token)
        local resp
        resp=$(curl -s --max-time 5 -b "$COOKIE_FILE" "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/list" \
            -H "X-Requested-With: XMLHttpRequest" -H "X-CSRF-Token: $csrf") || resp=''
        local selection
        selection=$(printf '%s\n' "$resp" | select_xhttp_inbound 2>/dev/null) || selection=''
        ID_XHTTP=$(printf '%s\n' "$selection" | jq -r '.inbound.id // empty' 2>/dev/null)
        XHTTP_CANDIDATE_COUNT=$(printf '%s\n' "$selection" | jq -r '.candidateCount // 0' 2>/dev/null)
        XHTTP_NAMED_COUNT=$(printf '%s\n' "$selection" | jq -r '.namedCount // 0' 2>/dev/null)
        XHTTP_HAS_VLESSENC=$(printf '%s\n' "$selection" | xhttp_inbound_has_vlessenc 2>/dev/null)
    }

    gen_email() {
        echo "$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)@$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4).com"
    }

    get_inbound_ids
    if ! [[ "$ID_XHTTP" =~ ^[0-9]+$ ]]; then
        echo -e "${R}[ERROR]${N} Could not uniquely identify the XHTTP inbound (compatible: ${XHTTP_CANDIDATE_COUNT:-0}, preferred-name matches: ${XHTTP_NAMED_COUNT:-0})."
        rm "$COOKIE_FILE"
        exit 1
    fi

    CID=$(cat /proc/sys/kernel/random/uuid)
    SID=$(head -c 16 /dev/urandom | md5sum | head -c 16)
    EMAIL="${CLIENT_EMAIL:-$(gen_email)}"
    CLIENT_FLOW=""
    if [ "$XHTTP_HAS_VLESSENC" = "true" ]; then
        CLIENT_FLOW="$VLESS_FLOW"
    fi

    PAYLOAD=$(build_client_payload "$EMAIL" "$CID" "$SID" "$CLIENT_FLOW" "$ID_XHTTP")
    RESPONSE=$(xui_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/clients/add" "$PAYLOAD")

    if echo "$RESPONSE" | jq_success; then
        echo -e "  ${G}[OK]${N} Client record created and attached"
    else
        echo -e "  ${R}[ERROR]${N} Failed to create client record"
        rm "$COOKIE_FILE"
        exit 1
    fi

    echo ""
    echo -e "${G}╔══════════════════════════════════════╗${N}"
    echo -e "${G}║     ${B}Client Added${N}${G}                  ║${N}"
    echo -e "${G}╚══════════════════════════════════════╝${N}"
    echo ""
    SUB_PATH=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='subPath' LIMIT 1;" 2>/dev/null || echo "/sub/")
    CLASH_PATH=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='subClashPath' LIMIT 1;" 2>/dev/null || echo "/clash/")
    echo -e "${B}XHTTP Subscription links:${N}"
    echo -e "  ${C}VLESS:${N} https://${C}${DOMAIN}${N}${SUB_PATH}${SID}  (${EMAIL})"
    echo -e "  ${C}Clash:${N} https://${C}${DOMAIN}${N}${CLASH_PATH}${SID}  (${EMAIL})"
    echo ""
    echo -e "${B}XHTTP UUID:${N} ${C}$CID${N}"
    if [ -n "$CLIENT_FLOW" ]; then
        echo -e "${B}XTLS flow:${N} ${C}$CLIENT_FLOW${N}"
        echo -e "${B}VLESS Encryption:${N} ${G}enabled via inbound settings${N}"
    fi

    rm "$COOKIE_FILE"
}

validate_modern_host_response() {
    local response="$1" inbound_id="$2" group_id="$3"
    echo "$response" | jq -e \
        --argjson inbound_id "$inbound_id" \
        --arg group_id "$group_id" \
        --arg domain "$DOMAIN" '
        .success == true
        and ((.obj | type) == "array")
        and ((.obj | length) == 1)
        and ((.obj[0].id // 0) != 0)
        and ((.obj[0].groupId // "") | length > 0)
        and (.obj[0].inboundId == $inbound_id)
        and (.obj[0].address == $domain)
        and (.obj[0].port == 443)
        and (.obj[0].security == "tls")
        and (.obj[0].sni == $domain)
        and (.obj[0].fingerprint == "chrome")
        and (((.obj[0].alpn // []) | index("h2")) != null)
        and (((.obj[0].alpn // []) | index("http/1.1")) != null)
        and (.obj[0].path == "")
        and ((.obj[0].groupId == $group_id) or ($group_id == ""))
    ' >/dev/null 2>&1
}

modern_host_readback_valid() {
    local response="$1" inbound_id="$2"
    echo "$response" | jq -e \
        --argjson inbound_id "$inbound_id" \
        --arg domain "$DOMAIN" \
        --arg host "$DOMAIN:443" '
        .success == true
        and ((.obj | type) == "array")
        and ([.obj[]? | select(
            ((.groupId // "") | length > 0)
            and
            (((.inboundIds // []) | index($inbound_id)) != null)
            and (((.hosts // []) | index($host)) != null)
            and (.isDisabled == false)
            and (.port == 443)
            and (.security == "tls")
            and (.sni == $domain)
            and (.fingerprint == "chrome")
            and (((.alpn // []) | index("h2")) != null)
            and (((.alpn // []) | index("http/1.1")) != null)
            and (.path == "")
        )] | length > 0)
    ' >/dev/null 2>&1
}

modern_caddy_route_present() {
    local path="$1"
    awk -v domain="$DOMAIN" -v route_path="/${path}/*" '
        function braces(s, n) { n=gsub(/\{/, "", s); n-=gsub(/\}/, "", s); return n }
        !site && $1 == domain && $2 == "{" { site=1; sites++; depth=braces($0); next }
        site {
            if (!in_route && depth == 1 && $1 == "handle" && $2 == route_path && $3 == "{") in_route=1
            if (in_route && $0 ~ /reverse_proxy[[:space:]]+unix\/@uds_xhttp_modern[[:space:]]*\{/) found=1
            depth+=braces($0)
            if (in_route && depth < 2) in_route=0
            if (depth <= 0) site=0
        }
        END { exit !(sites == 1 && found) }
    ' "$SERVER_DIR/Caddyfile"
}

caddy_target_is_unique() {
    awk -v domain="$DOMAIN" '
        function braces(s, n) { n=gsub(/\{/, "", s); n-=gsub(/\}/, "", s); return n }
        !site && $1 == domain && $2 == "{" { site=1; sites++; depth=braces($0); next }
        site {
            if (depth == 1 && $0 ~ /^[[:space:]]*handle[[:space:]]*\{[[:space:]]*$/) catches++
            depth+=braces($0)
            if (depth <= 0) site=0
        }
        END { exit !(sites == 1 && catches == 1) }
    ' "$SERVER_DIR/Caddyfile"
}

add_modern_caddy_route() {
    local path="$1" backup="${2:-}" temp immediate_backup modern_route
    modern_route=$(cat <<EOF
    handle /${path}/* {
        reverse_proxy unix/@uds_xhttp_modern {
            header_up -X-Forwarded-For
            flush_interval -1
            transport http {
                versions h2c 2
                proxy_protocol v2
            }
        }
    }
EOF
)
    temp=$(mktemp "$SERVER_DIR/.Caddyfile.modern.XXXXXX") || return 1
    if [ -z "$backup" ]; then
        backup="$SERVER_DIR/Caddyfile.modern-backup.$(date +%Y%m%d%H%M%S).$$"
        cp -p "$SERVER_DIR/Caddyfile" "$backup" || {
            rm -f "$temp"
            echo -e "${R}[ERROR]${N} Could not create Caddyfile backup"
            return 1
        }
    elif [ ! -f "$backup" ]; then
        rm -f "$temp"
        echo -e "${R}[ERROR]${N} Caddyfile snapshot is missing: $backup"
        return 1
    fi
    immediate_backup=$(mktemp "$SERVER_DIR/.Caddyfile.prewrite.XXXXXX") || {
        rm -f "$temp"
        echo -e "${R}[ERROR]${N} Could not create immediate Caddyfile backup"
        return 1
    }
    if ! cp -p "$SERVER_DIR/Caddyfile" "$immediate_backup"; then
        rm -f "$temp" "$immediate_backup"
        echo -e "${R}[ERROR]${N} Could not capture immediate Caddyfile backup"
        return 1
    fi
    if ! awk -v domain="$DOMAIN" -v route="$modern_route" '
        function braces(s, n) { n=gsub(/\{/, "", s); n-=gsub(/\}/, "", s); return n }
        !site && $1 == domain && $2 == "{" { site=1; sites++; depth=braces($0); print; next }
        site && depth == 1 && $0 ~ /^[[:space:]]*handle[[:space:]]*\{[[:space:]]*$/ {
            catches++
            if (catches == 1) { printf "%s\n", route; inserted=1 }
        }
        { print }
        site {
            depth+=braces($0)
            if (depth <= 0) site=0
        }
        END { if (sites != 1 || catches != 1 || !inserted) exit 1 }
    ' "$SERVER_DIR/Caddyfile" > "$temp"; then
        rm -f "$temp" "$immediate_backup"
        echo -e "${R}[ERROR]${N} Could not prepare Caddyfile backup or route insertion"
        return 1
    fi
    if ! cat "$temp" > "$SERVER_DIR/Caddyfile"; then
        if cat "$immediate_backup" > "$SERVER_DIR/Caddyfile"; then
            echo -e "${R}[ERROR]${N} Could not write mounted Caddyfile in place; immediate content restored (manual snapshot: $backup)"
            rm -f "$temp" "$immediate_backup"
        else
            echo -e "${R}[ERROR]${N} Could not write mounted Caddyfile or restore it (immediate backup: $immediate_backup; manual snapshot: $backup)"
            rm -f "$temp"
        fi
        return 1
    fi
    rm -f "$temp"
    if ! docker exec caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1 \
        || ! docker exec caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        local restore_temp restored=false
        restore_temp=$(mktemp "$SERVER_DIR/.Caddyfile.restore.XXXXXX") || true
        if [ -n "$restore_temp" ] && cp -p "$immediate_backup" "$restore_temp"; then
            if cat "$restore_temp" > "$SERVER_DIR/Caddyfile" \
                && docker exec caddy caddy reload --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
                restored=true
            fi
            rm -f "$restore_temp"
        fi
        if [ "$restored" = "true" ]; then
            rm -f "$immediate_backup"
            echo -e "${R}[ERROR]${N} Caddy validation/reload failed; restored the immediate pre-write Caddyfile (manual snapshot: $backup)"
        else
            echo -e "${R}[ERROR]${N} Caddy validation/reload failed; automatic restoration failed (immediate backup: $immediate_backup; manual snapshot: $backup)"
        fi
        return 1
    fi
    rm -f "$immediate_backup"
    echo -e "  ${G}Caddy route added and loaded${N} (manual snapshot: $backup)"
}

create_modern_snapshot() {
    local stamp backup_dir db_path
    db_path="$SERVER_DIR/3x-ui/db/x-ui.db"
    stamp=$(date -u +%Y%m%dT%H%M%SZ)
    install -d -m 700 -o root -g root /root/serv-backups || return 1
    umask 077
    backup_dir=$(mktemp -d "/root/serv-backups/add-modern-inbound-${stamp}.XXXXXX") || {
        echo -e "${R}[ERROR]${N} Could not create collision-resistant backup directory"
        return 1
    }
    if ! chown root:root "$backup_dir" || ! chmod 700 "$backup_dir"; then
        echo -e "${R}[ERROR]${N} Could not secure root-owned backup directory"
        return 1
    fi
    if ! sqlite3 "$db_path" ".backup '$backup_dir/x-ui.db'" >/dev/null 2>&1; then
        echo -e "${R}[ERROR]${N} SQLite backup failed; no server changes were made"
        return 1
    fi
    if ! cp -p "$SERVER_DIR/Caddyfile" "$backup_dir/Caddyfile"; then
        echo -e "${R}[ERROR]${N} Caddyfile snapshot failed; no server changes were made"
        return 1
    fi
    chmod 600 "$backup_dir/x-ui.db" "$backup_dir/Caddyfile" 2>/dev/null || true
    MODERN_BACKUP_DIR="$backup_dir"
    echo -e "  ${G}Backup snapshot:${N} $MODERN_BACKUP_DIR"
}

modern_valid_inbounds() {
    jq -c '
        [.obj[]? | . as $i
         | ($i.streamSettings | if type == "string" then (fromjson? // {}) else . end) as $s
         | ($i.settings | if type == "string" then (fromjson? // {}) else . end) as $v
         | ($s.xhttpSettings // {}) as $x
         | select(
             ($i.protocol // "") == "vless"
             and ($i.enable == true)
             and ($i.listen // "") == "@uds_xhttp_modern"
             and (($i.port // 0) | tostring) == "0"
             and (($i.remark // "") | contains("VLESS-XHTTP-Modern"))
             and ($s.network // "") == "xhttp"
             and ($s.security // "") == "none"
             and (($x.path // "") | test("^/?api/v[0-9]+$"))
             and ($x.mode // "") == "stream-up"
             and (($v.decryption // "") != "" and ($v.decryption // "") != "none")
             and (($v.encryption // "") != "" and ($v.encryption // "") != "none")
             and (($s.sockopt.acceptProxyProtocol // false) == true)
             and (($s.sockopt.trustedXForwardedFor // []) == ["127.0.0.1/32"])
         )]
    '
}

add_modern_inbound() {
    local lock_fd modern_list modern_count modern_id modern_path modern_remark
    local stream_obj host_readback host_group_id host_add_response
    local selected_path route_path path_candidate i host_ok route_ok
    local modern_fully_verified=false modern_backup_created=false
    local modern_listener_count valid_modern_list modern_id_readback

    [ "$EUID" -eq 0 ] || { echo -e "${R}[ERROR]${N} Run as root"; return 1; }
    command -v docker >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} docker is required"; return 1; }
    command -v jq >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} jq is required"; return 1; }
    command -v sqlite3 >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} sqlite3 is required"; return 1; }
    command -v flock >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} flock is required"; return 1; }
    command -v ss >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} ss is required"; return 1; }
    command -v shuf >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} shuf is required"; return 1; }
    command -v curl >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} curl is required"; return 1; }
    command -v mktemp >/dev/null 2>&1 || { echo -e "${R}[ERROR]${N} mktemp is required"; return 1; }
    [ -f "$SERVER_DIR/Caddyfile" ] || { echo -e "${R}[ERROR]${N} Caddyfile not found"; return 1; }
    [ -f "$SERVER_DIR/3x-ui/db/x-ui.db" ] || { echo -e "${R}[ERROR]${N} Expected 3x-ui database not found: $SERVER_DIR/3x-ui/db/x-ui.db"; return 1; }
    check_installed || { echo -e "${R}[ERROR]${N} Installation not found"; return 1; }
    docker ps --format '{{.Names}}' | grep -qx caddy || { echo -e "${R}[ERROR]${N} caddy container is not running"; return 1; }
    docker ps --format '{{.Names}}' | grep -qx 3xui_app || { echo -e "${R}[ERROR]${N} 3xui_app container is not running"; return 1; }
    exec {lock_fd}>/var/lock/serv-add-modern-inbound.lock || { echo -e "${R}[ERROR]${N} Cannot open operation lock"; return 1; }
    if ! flock -n "$lock_fd"; then
        echo -e "${R}[ERROR]${N} Another add-modern-inbound operation is running"
        return 1
    fi

    DOMAIN=$(caddy_redir_domain)
    local ADM
    ADM=$(caddy_admin_prefix_segment)
    [ -n "$DOMAIN" ] && [ -n "$ADM" ] || { echo -e "${R}[ERROR]${N} Could not derive domain/admin path from Caddyfile"; return 1; }
    if ! docker exec caddy caddy validate --config /etc/caddy/Caddyfile >/dev/null 2>&1; then
        echo -e "${R}[ERROR]${N} Current Caddy configuration failed validation; no changes made"
        return 1
    fi
    if ! caddy_target_is_unique; then
        echo -e "${R}[ERROR]${N} Caddyfile must contain exactly one $DOMAIN site and one target catch-all; no changes made"
        return 1
    fi
    API_PREFIX="/$ADM"
    read -p "3x-ui Username: " XUI_USER
    read -s -p "3x-ui Password: " XUI_PASS
    echo ""
    COOKIE_FILE=$(mktemp)
    trap 'rm -f "${COOKIE_FILE:-}"' EXIT INT TERM
    if ! xui_login "$XUI_USER" "$XUI_PASS"; then
        echo -e "${R}[ERROR]${N} Login failed"
        rm -f "$COOKIE_FILE"
        return 1
    fi
    echo -e "${G}Logged in${N}"

    HOSTS_PREFLIGHT_RESP=$(xui_get_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/hosts/list" || true)
    if ! echo "$HOSTS_PREFLIGHT_RESP" | jq_success; then
        echo -e "${R}[ERROR]${N} Grouped Hosts API preflight failed; no changes made"
        rm -f "$COOKIE_FILE"
        return 1
    fi
    modern_list=$(xui_get_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/list" || true)
    if ! echo "$modern_list" | jq -e '.success == true and (.obj | type) == "array"' >/dev/null 2>&1; then
        echo -e "${R}[ERROR]${N} Could not read the inbound list; no changes made"
        rm -f "$COOKIE_FILE"
        return 1
    fi
    modern_listener_count=$(printf '%s\n' "$modern_list" | jq -r '[.obj[]? | select((.listen // "") == "@uds_xhttp_modern")] | length' 2>/dev/null || echo 0)
    valid_modern_list=$(printf '%s\n' "$modern_list" | modern_valid_inbounds 2>/dev/null || echo '[]')
    modern_count=$(printf '%s\n' "$valid_modern_list" | jq -r 'length' 2>/dev/null || echo 0)
    if [ "$modern_count" -eq 0 ] && ss -xlp 2>/dev/null | grep -Fq '@uds_xhttp_modern'; then
        echo -e "${R}[ERROR]${N} Active @uds_xhttp_modern socket exists without a valid modern inbound; no changes made"
        rm -f "$COOKIE_FILE"
        return 1
    fi
    if [ "$modern_listener_count" -ne "$modern_count" ]; then
        echo -e "${R}[ERROR]${N} @uds_xhttp_modern listener collision or invalid inbound; no changes made"
        rm -f "$COOKIE_FILE"
        return 1
    fi
    if [ "$modern_count" -gt 1 ]; then
        echo -e "${R}[ERROR]${N} Ambiguous modern inbound: $modern_count matches; no changes made"
        rm -f "$COOKIE_FILE"
        return 1
    fi
    if [ "$modern_count" -eq 1 ]; then
        modern_id=$(printf '%s\n' "$valid_modern_list" | jq -r '.[0].id // empty' 2>/dev/null)
        stream_obj=$(printf '%s\n' "$valid_modern_list" | jq -c '.[0].streamSettings
            | if type == "string" then (fromjson? // {}) else . end
        ' 2>/dev/null)
        modern_path=$(printf '%s' "$stream_obj" | jq -r '.xhttpSettings.path // empty' 2>/dev/null)
        modern_path=${modern_path#/}
        if ! [[ "$modern_id" =~ ^[0-9]+$ && "$modern_path" =~ ^api/v[0-9]+$ ]]; then
            echo -e "${R}[ERROR]${N} Existing modern inbound has invalid id or path"
            rm -f "$COOKIE_FILE"
            return 1
        fi
        if ! ss -xlp 2>/dev/null | grep -Fq '@uds_xhttp_modern'; then
            echo -e "${R}[ERROR]${N} Existing modern inbound $modern_id is valid but @uds_xhttp_modern is not listening"
            rm -f "$COOKIE_FILE"
            return 1
        fi
        echo -e "  ${G}Existing modern inbound found${N} (ID $modern_id, path /$modern_path/)"
    else
        if ! create_modern_snapshot; then
            rm -f "$COOKIE_FILE"
            return 1
        fi
        modern_backup_created=true
        modern_path=""
        for i in {1..100}; do
            path_candidate="api/v$(shuf -i 1-999999 -n 1)"
            if ! grep -Eq "^[[:space:]]*handle[[:space:]]+/${path_candidate}(/|[[:space:]]|\*)" "$SERVER_DIR/Caddyfile"; then
                modern_path="$path_candidate"
                break
            fi
        done
        [ -n "$modern_path" ] || { echo -e "${R}[ERROR]${N} Could not find an unused modern path"; rm -f "$COOKIE_FILE"; return 1; }
        if ! generate_vlessenc_pair; then
            rm -f "$COOKIE_FILE"
            return 1
        fi
        modern_remark="$(get_xhttp_remark)"
        modern_remark="${modern_remark%VLESS-XHTTP}VLESS-XHTTP-Modern"
        modern_payload=$(build_xhttp_payload "$modern_path" false "$VLESS_SERVER_DECRYPTION" "$VLESS_CLIENT_ENCRYPTION" "$modern_remark" "@uds_xhttp_modern")
        modern_response=$(xui_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/add" "$modern_payload" || true)
        if ! echo "$modern_response" | jq_success; then
            echo -e "${R}[ERROR]${N} Modern inbound creation failed (path /$modern_path/)"
            rm -f "$COOKIE_FILE"
            return 1
        fi
        modern_id=$(echo "$modern_response" | jq -r '.obj.id // empty')
        if ! [[ "$modern_id" =~ ^[0-9]+$ ]]; then
            echo -e "${R}[ERROR]${N} Modern inbound returned invalid ID (path /$modern_path/)"
            rm -f "$COOKIE_FILE"
            return 1
        fi
        echo -e "  ${G}Modern inbound created${N} (ID $modern_id, path /$modern_path/)"
        modern_list=$(xui_get_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/list" || true)
        valid_modern_list=$(printf '%s\n' "$modern_list" | modern_valid_inbounds 2>/dev/null || echo '[]')
        modern_count=$(printf '%s\n' "$valid_modern_list" | jq -r 'length' 2>/dev/null || echo 0)
        modern_id_readback=$(printf '%s\n' "$valid_modern_list" | jq -r '.[0].id // empty' 2>/dev/null)
        modern_listener_count=$(printf '%s\n' "$modern_list" | jq -r '[.obj[]? | select((.listen // "") == "@uds_xhttp_modern")] | length' 2>/dev/null || echo 0)
        if [ "$modern_count" -ne 1 ] || [ "$modern_listener_count" -ne 1 ] || [ "$modern_id_readback" != "$modern_id" ]; then
            echo -e "${R}[ERROR]${N} Created inbound failed full validation (ID $modern_id; snapshot retained at $MODERN_BACKUP_DIR)"
            rm -f "$COOKIE_FILE"
            return 1
        fi
        for i in {1..20}; do
            if ss -xlp 2>/dev/null | grep -Fq '@uds_xhttp_modern'; then break; fi
            sleep 1
        done
        if ! ss -xlp 2>/dev/null | grep -Fq '@uds_xhttp_modern'; then
            echo -e "${R}[ERROR]${N} Modern UDS socket not found (inbound ID $modern_id, path /$modern_path/)"
            rm -f "$COOKIE_FILE"
            return 1
        fi
    fi

    if [ "$modern_fully_verified" != "true" ]; then
        host_readback=$(xui_get_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/hosts/byInbound/$modern_id" || true)
        host_ok=false
        modern_host_readback_valid "$host_readback" "$modern_id" && host_ok=true
        route_ok=false
        modern_caddy_route_present "$modern_path" && route_ok=true

        if [ "$modern_count" -eq 1 ] && [ "$host_ok" = "true" ] && [ "$route_ok" = "true" ]; then
            modern_fully_verified=true
            echo -e "  ${G}Existing Host group and Caddy route verified${N}"
        else
            if [ "$modern_backup_created" != "true" ]; then
                if ! create_modern_snapshot; then
                    rm -f "$COOKIE_FILE"
                    return 1
                fi
                modern_backup_created=true
            fi
            if [ "$host_ok" = "true" ]; then
                echo -e "  ${G}Existing Host group verified${N}"
            else
                host_add_response=$(xui_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/hosts/add" "$(build_host_payload "$modern_id" "$DOMAIN")" || true)
                host_group_id=$(echo "$host_add_response" | jq -r '.obj[0].groupId // empty' 2>/dev/null)
                host_readback=$(xui_get_json "http://127.0.0.1:2053${API_PREFIX}/panel/api/hosts/byInbound/$modern_id" || true)
                if ! validate_modern_host_response "$host_add_response" "$modern_id" "$host_group_id"; then
                    echo -e "${R}[ERROR]${N} Host group creation failed (inbound ID $modern_id; backup retained at $MODERN_BACKUP_DIR)"
                    rm -f "$COOKIE_FILE"
                    return 1
                fi
                if ! modern_host_readback_valid "$host_readback" "$modern_id"; then
                    echo -e "${R}[ERROR]${N} Host readback invalid after creation (inbound ID $modern_id; backup retained at $MODERN_BACKUP_DIR)"
                    rm -f "$COOKIE_FILE"
                    return 1
                fi
                echo -e "  ${G}Host group created and verified${N}"
            fi
            if [ "$route_ok" = "false" ]; then
                if grep -Eq "^[[:space:]]*handle[[:space:]]+/${modern_path}(/|[[:space:]]|\*)" "$SERVER_DIR/Caddyfile"; then
                    echo -e "${R}[ERROR]${N} Caddy path collision for /$modern_path/ (inbound ID $modern_id; backup retained at $MODERN_BACKUP_DIR)"
                    rm -f "$COOKIE_FILE"
                    return 1
                fi
                add_modern_caddy_route "$modern_path" "$MODERN_BACKUP_DIR/Caddyfile" || { rm -f "$COOKIE_FILE"; return 1; }
            else
                echo -e "  ${G}Existing Caddy route verified${N}"
            fi
        fi
    fi
    echo ""
    echo -e "${G}Modern inbound ready${N}"
    echo -e "  Inbound ID: ${C}$modern_id${N}"
    echo -e "  Path:       ${C}/$modern_path/${N}"
    echo -e "  UDS:        ${C}@uds_xhttp_modern${N}"
    echo -e "  VLESS Encryption: ${G}enabled${N}"
    echo -e "  ${Y}Clients must be manually created/attached in the UI with the new subscription/profile.${N}"
    rm -f "$COOKIE_FILE"
}

show_status() {
    print_banner
    echo -e "${B}Docker Containers:${N}"
    local names="caddy 3xui_app"
    for n in $names; do
        if docker ps --format "{{.Names}}" 2>/dev/null | grep -q "^$n$"; then
            echo -e "  ${G}✅${N} $n  $(docker ps --filter name=$n --format '{{.Status}}')"
        else
            echo -e "  ${R}❌${N} $n  not running"
        fi
    done
    echo ""

    local DOMAIN=""
    local ADMIN_PATH=""
    local SUB_PATH=""
    local JSON_PATH=""
    local CLASH_PATH=""
    local XHTTP_PATH=""

    # Read config from Caddyfile
    if [ -f "$SERVER_DIR/Caddyfile" ]; then
        ADMIN_PATH=$(caddy_handle_path 'handle /admin-\w+')
        SUB_PATH=$(caddy_handle_path 'handle /sub-\w+')
        JSON_PATH=$(caddy_handle_path 'handle /json[^/]*')
        CLASH_PATH=$(caddy_handle_path 'handle /clash[^/]*')
        DOMAIN=$(caddy_redir_domain)
    fi

    if [ -n "$DOMAIN" ]; then
        echo -e "${B}Domain:${N} ${C}$DOMAIN${N}"
        echo ""
        echo -e "${B}URLs:${N}"
        [ -n "$ADMIN_PATH" ] && echo -e "  ${C}Panel:${N} https://$DOMAIN/$ADMIN_PATH/"
        [ -n "$SUB_PATH" ]   && echo -e "  ${C}Sub:${N}   https://$DOMAIN/$SUB_PATH/"
        [ -n "$JSON_PATH" ]  && echo -e "  ${C}JSON:${N}  https://$DOMAIN/$JSON_PATH/"
        [ -n "$CLASH_PATH" ] && echo -e "  ${C}Clash:${N} https://$DOMAIN/$CLASH_PATH/"
    fi

    echo ""
    echo -e "${B}Inbounds & Clients:${N}"
    local xui_config
    if xui_config=$(docker exec 3xui_app cat bin/config.json 2>/dev/null) && [ -n "$xui_config" ] && echo "$xui_config" | jq -r '
def settings_obj:
    if (.settings | type) == "string" then (.settings | fromjson? // {})
    elif (.settings | type) == "object" then .settings
    else {} end;

[.inbounds[]? | select(((.tag // "") | contains("api")) | not)] as $inbounds
| if ($inbounds | length) == 0 then
    "  (none)"
  else
    $inbounds[]
    | . as $inbound
    | ($inbound | settings_obj) as $settings
    | ($settings | (.clients // [])) as $clients
    | (((($settings.decryption // "") != "" and ($settings.decryption // "") != "none")
        and (($settings.encryption // "") != "" and ($settings.encryption // "") != "none"))) as $vlessenc
    | [
        "  \($inbound.remark // $inbound.tag // "") (\($inbound.port // ""), \($inbound.streamSettings.network // "tcp"), \($inbound.streamSettings.security // "none")) - \($clients | length) client(s)\(if $vlessenc then " vlessenc=on" else "" end)",
        ($clients[]? | "    └ \((.id // "")[0:8])... sub=\(.subId // "")\(if (.flow // "") != "" then " flow=\(.flow)" else "" end)\(if (.email // "") != "" then " email=\(.email)" else "" end)")
      ][]
  end
' 2>/dev/null; then
        :  # success
    else
        echo -e "  ${R}cannot read config${N}"
    fi

    echo ""
    sqlite3 /opt/serv/3x-ui/db/x-ui.db 2>/dev/null <<<".exit" && {
        echo -e "${B}Settings:${N}"
        local subPath subURI webBase
        subPath=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='subPath' LIMIT 1;" 2>/dev/null || echo "—")
        subURI=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='subURI' LIMIT 1;" 2>/dev/null || echo "—")
        webBase=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='webBasePath' LIMIT 1;" 2>/dev/null || echo "—")
        echo -e "  ${Y}Sub Path:${N}     $subPath"
        echo -e "  ${Y}Sub URI:${N}      $subURI"
        echo -e "  ${Y}Web Base Path:${N} $webBase"
    } 2>/dev/null || true
    echo ""
}

show_help() {
    echo -e "${B}Usage:${N} $0 [command]"
    echo ""
    echo "Commands:"
    echo -e "  (no args)      ${C}Full installation${N}  — setup everything from scratch"
    echo -e "  ${C}add-client${N}     ${Y}Add new client${N}      — add a client to existing installation"
    echo -e "  ${C}add-modern-inbound${N} ${Y}Add modern inbound${N} — add a second VLESS/XHTTP inbound"
    echo -e "  ${C}status${N}         ${Y}Show status${N}         — display current configuration"
    echo -e "  ${C}help${N}           ${Y}Show help${N}"
    echo ""
    echo -e "${B}Examples:${N}"
    echo -e "  $0                    # Full install"
    echo -e "  $0 add-client         # Add new client"
    echo -e "  $0 status             # Show status"
    echo ""
}

# ─── CLI dispatch ──────────────────────────────────────────────────────────────
case "${1:-install}" in
    help|--help|-h)
        show_help
        exit 0
        ;;
    add-client)
        ensure_jq
        add_client
        exit 0
        ;;
    add-modern-inbound)
        ensure_jq
        add_modern_inbound
        exit $?
        ;;
    status)
        check_installed || {
            echo -e "${R}[ERROR]${N} Installation not found."
            exit 1
        }
        ensure_jq
        show_status
        exit 0
        ;;
    install)
        ensure_jq
        ;;  # continue below
    *)
        echo -e "${R}[ERROR]${N} Unknown command: $1"
        show_help
        exit 1
        ;;
esac

# ═══════════════════════════════════════════════════════════════════════════════
# FULL INSTALLATION
# ═══════════════════════════════════════════════════════════════════════════════

print_banner

read -p "Domain (e.g. mydomain.com): " DOMAIN
if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$'; then
    echo -e "${R}[ERROR]${N} Invalid domain format"
    exit 1
fi

echo ""
echo -e "${Y}--- 3x-ui Panel Credentials ---${N}"
read -p "3x-ui Username (default: admin): " XUI_USER
XUI_USER=${XUI_USER:-admin}
read -s -p "3x-ui Password (default: admin): " XUI_PASS
echo ""
XUI_PASS=${XUI_PASS:-admin}
echo -e "${Y}-------------------------------${N}"
echo ""

echo -e "${Y}--- Client Configuration ---${N}"

read -p "Enable advanced XHTTP padding obfuscation (requires Xray-core v26.6.1 clients)? [y/N]: " XHTTP_OBFS_CHOICE
case "${XHTTP_OBFS_CHOICE:-n}" in
    y|Y|yes|YES|Yes) XHTTP_ADVANCED_OBFS=true ;;
    *) XHTTP_ADVANCED_OBFS=false ;;
esac
echo ""

ADMIN_PATH="admin-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
SUB_PATH="sub-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
JSON_PATH="json-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
CLASH_PATH="clash-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
XHTTP_PATH="api/v$(shuf -i 1-999 -n 1)"

CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)
SUB_ID=$(head -c 16 /dev/urandom | md5sum | head -c 16)
CLIENT_SUFFIX=$(tr -dc 'a-z0-9' < /dev/urandom | head -c 10)
CLIENT_EMAIL="client-$CLIENT_SUFFIX"
XHTTP_REMARK=$(get_xhttp_remark)

echo -e "${G}=== Configuration Summary ===${N}"
echo -e "${Y}Domain:${N}      ${C}$DOMAIN${N}"
echo -e "${Y}Admin path:${N}  /$ADMIN_PATH/"
echo -e "${Y}Sub path:${N}    /$SUB_PATH/"
echo -e "${Y}JSON path:${N}   /$JSON_PATH/"
echo -e "${Y}Clash path:${N}  /$CLASH_PATH/"
echo -e "${Y}XHTTP path:${N}  /$XHTTP_PATH/"
echo -e "${Y}XHTTP remark:${N} $XHTTP_REMARK"
echo -e "${Y}XHTTP UUID:${N}  ${C}$CLIENT_ID${N}"
echo -e "${Y}Advanced XHTTP padding:${N} $XHTTP_ADVANCED_OBFS"
echo -e "${Y}VLESS Encryption:${N} enabled by default"
echo -e "${Y}XTLS flow:${N}   $VLESS_FLOW"
echo ""

echo -e "${G}[1/8]${N} Preparing directories..."
mkdir -p "$SERVER_DIR/3x-ui/db"
mkdir -p "$SERVER_DIR/caddy/data"
echo -e "  ${G}Done${N}"

echo -e "${G}[2/8]${N} Enabling BBR..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi
echo -e "  ${G}BBR enabled${N}"

echo -e "${G}[3/8]${N} Generating Caddyfile from template..."
if [ ! -f "$SERVER_DIR/Caddyfile.template" ]; then
    echo -e "${R}[ERROR]${N} Caddyfile.template not found"
    exit 1
fi
cp "$SERVER_DIR/Caddyfile.template" "$SERVER_DIR/Caddyfile"
sed -i "s|\$DOMAIN|$DOMAIN|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$ADMIN_PATH|$ADMIN_PATH|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$SUB_PATH|$SUB_PATH|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$JSON_PATH|$JSON_PATH|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$CLASH_PATH|$CLASH_PATH|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$XHTTP_PATH|$XHTTP_PATH|g" "$SERVER_DIR/Caddyfile"
echo -e "  ${G}Domain and paths updated${N}"

echo -e "${G}[4/8]${N} Generating Caddy bcrypt hash..."
read -s -p "Enter password for web basic_auth: " WEB_PASSWORD
echo ""
if ! command -v docker &> /dev/null; then
    echo -e "${R}[ERROR]${N} Docker not found. Install Docker first."
    exit 1
fi
BCRYPT_HASH=$(docker run --rm -i caddy caddy hash-password <<< "$WEB_PASSWORD" 2>/dev/null) || {
    echo -e "${R}[ERROR]${N} Failed to generate bcrypt hash"
    exit 1
}
sed -i "s|\$WEB_PASSWORD_HASH|$BCRYPT_HASH|g" "$SERVER_DIR/Caddyfile"
echo -e "  ${G}Caddy bcrypt hash updated${N}"

echo -e "${G}[5/8]${N} Configuring firewall..."
# On RHEL-family, firewalld and iptables-services conflict at runtime and
# stopping firewalld wipes live rules — so disable it BEFORE applying ours.
if { command -v dnf >/dev/null 2>&1 || command -v yum >/dev/null 2>&1; } && command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet firewalld 2>/dev/null; then
        systemctl stop firewalld 2>/dev/null || true
        echo -e "  ${Y}firewalld stopped${N}"
    fi
    if systemctl is-enabled --quiet firewalld 2>/dev/null; then
        systemctl disable firewalld 2>/dev/null || true
        echo -e "  ${Y}firewalld disabled (conflicts with iptables)${N}"
    fi
fi
iptables -P INPUT ACCEPT
iptables -F
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -P INPUT DROP

# Configure IPv6 only when the host has a global IPv6 address.  Missing IPv6
# tooling or an address must leave the existing IPv6 firewall untouched.
if command -v ip >/dev/null 2>&1 && command -v ip6tables >/dev/null 2>&1 \
    && ip -6 addr show scope global 2>/dev/null | grep -qE 'inet6 [^[:space:]]+ scope global'; then
    ip6tables -P INPUT ACCEPT
    ip6tables -F INPUT
    ip6tables -A INPUT -i lo -j ACCEPT
    ip6tables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
    ip6tables -A INPUT -p ipv6-icmp -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 22 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 80 -j ACCEPT
    ip6tables -A INPUT -p tcp --dport 443 -j ACCEPT
    ip6tables -A INPUT -p udp --dport 443 -j ACCEPT
    ip6tables -P INPUT DROP
    IPV6_FIREWALL_CONFIGURED=true
    echo -e "  ${G}IPv6 firewall configured${N}"
else
    echo -e "  ${Y}IPv6 firewall skipped (no global IPv6 address or IPv6 tooling unavailable)${N}"
fi
persist_firewall
echo -e "  ${G}Firewall configured${N}"

echo -e "${G}[6/8]${N} Starting services..."
cd "$SERVER_DIR" && docker compose down && docker compose up -d
echo -e "  ${G}Services started${N}"

echo -e "${G}[7/8]${N} Configuring 3x-ui inbound, Host, and client via API..."
echo "  Waiting for 3x-ui to be ready (max 60s)..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:2053/csrf-token | grep -q "200"; do
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo -e "${R}[ERROR]${N} 3x-ui failed to start in time"
        exit 1
    fi
done

COOKIE_FILE=$(mktemp)

echo "  Getting CSRF token..."
CSRF_TOKEN=$(csrf_token)
if [ -z "$CSRF_TOKEN" ]; then
    echo -e "${R}[ERROR]${N} Failed to get CSRF token"
    rm "$COOKIE_FILE"
    exit 1
fi

echo "  Logging in with default credentials (admin/admin)..."
if ! xui_login "admin" "admin"; then
    echo -e "${R}[ERROR]${N} 3x-ui login failed. Check if the panel is running with default credentials (admin/admin)."
    rm "$COOKIE_FILE"
    exit 1
fi

echo "  Checking Hosts API compatibility..."
HOSTS_PREFLIGHT_RESP=$(xui_get_json "http://127.0.0.1:2053/panel/api/hosts/list") || true
if ! echo "$HOSTS_PREFLIGHT_RESP" | jq_success; then
    MSG=$(echo "$HOSTS_PREFLIGHT_RESP" | jq -r '.msg // empty' 2>/dev/null || true)
    MSG=${MSG:-"Hosts API unavailable or unsupported"}
    echo -e "${R}[ERROR]${N} Hosts API preflight failed: $MSG"
    echo -e "${R}[ERROR]${N} This installer requires 3x-ui v3.5.0+ with grouped /panel/api/hosts support."
    rm "$COOKIE_FILE"
    exit 1
fi
echo -e "  ${G}Hosts API available${N}"

# 1. Generate VLESS Encryption pair for inbound settings.
# 3x-ui stores both the server decryption and the client encryption strings at
# inbound settings level; subscriptions read settings.encryption from there.
echo "  Generating VLESS Encryption pair..."
if ! generate_vlessenc_pair; then
    rm "$COOKIE_FILE"
    exit 1
fi
echo -e "  ${G}VLESS Encryption enabled${N} (${VLESS_FLOW})"

# 1. Add XHTTP Backend (UDS @uds_xhttp, port 0)
echo "  Adding XHTTP Backend inbound..."
XHTTP_PAYLOAD=$(build_xhttp_payload "$XHTTP_PATH" "$XHTTP_ADVANCED_OBFS" "$VLESS_SERVER_DECRYPTION" "$VLESS_CLIENT_ENCRYPTION" "$XHTTP_REMARK")
XHTTP_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/inbounds/add" "$XHTTP_PAYLOAD") || true
if ! echo "$XHTTP_RESP" | jq_success; then
    echo -e "${R}[ERROR]${N} XHTTP Backend creation failed"
    rm "$COOKIE_FILE"
    exit 1
fi
XHTTP_ID=$(echo "$XHTTP_RESP" | jq -r '.obj.id // empty')
if ! [[ "$XHTTP_ID" =~ ^[0-9]+$ ]]; then
    echo -e "${R}[ERROR]${N} XHTTP Backend creation returned invalid inbound id: ${XHTTP_ID:-empty}"
    rm "$COOKIE_FILE"
    exit 1
fi

# 2. Create public Host group for subscription rendering
echo "  Creating public Host group..."
HOST_PAYLOAD=$(build_host_payload "$XHTTP_ID" "$DOMAIN")
HOST_ADD_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/hosts/add" "$HOST_PAYLOAD") || true
if ! echo "$HOST_ADD_RESP" | jq -e \
    --argjson inbound_id "$XHTTP_ID" \
    --arg domain "$DOMAIN" '
    .success == true
    and ((.obj | type) == "array")
    and ((.obj | length) == 1)
    and ((.obj[0].id // 0) != 0)
    and (((.obj[0].groupId // "") | length) > 0)
    and (.obj[0].inboundId == $inbound_id)
    and (.obj[0].address == $domain)
    and (.obj[0].port == 443)
    and (.obj[0].security == "tls")
    and (.obj[0].sni == $domain)
    and (.obj[0].fingerprint == "chrome")
    and (((.obj[0].alpn // []) | index("h2")) != null)
    and (((.obj[0].alpn // []) | index("http/1.1")) != null)
    and (.obj[0].path == "")
' >/dev/null 2>&1; then
    MSG=$(echo "$HOST_ADD_RESP" | jq -r '.msg // empty' 2>/dev/null || true)
    MSG=${MSG:-"invalid Hosts API add response"}
    echo -e "${R}[ERROR]${N} Host group creation failed: $MSG"
    rm "$COOKIE_FILE"
    exit 1
fi
HOST_GROUP_ID=$(echo "$HOST_ADD_RESP" | jq -r '.obj[0].groupId')

HOST_READBACK_RESP=$(xui_get_json "http://127.0.0.1:2053/panel/api/hosts/byInbound/$XHTTP_ID") || true
if ! echo "$HOST_READBACK_RESP" | jq -e \
    --argjson inbound_id "$XHTTP_ID" \
    --arg group_id "$HOST_GROUP_ID" \
    --arg domain "$DOMAIN" \
    --arg host "$DOMAIN:443" '
    .success == true
    and ((.obj | type) == "array")
    and (
        [.obj[]? | select(
            (.groupId == $group_id)
            and (((.inboundIds // []) | index($inbound_id)) != null)
            and (((.hosts // []) | index($host)) != null)
            and (.isDisabled == false)
            and (.port == 443)
            and (.security == "tls")
            and (.sni == $domain)
            and (.fingerprint == "chrome")
            and ((.alpn // []) | index("h2") != null)
            and ((.alpn // []) | index("http/1.1") != null)
            and (.path == "")
        )] | length > 0
    )
' >/dev/null 2>&1; then
    echo -e "${R}[ERROR]${N} Host readback validation failed for inbound $XHTTP_ID and domain $DOMAIN"
    rm "$COOKIE_FILE"
    exit 1
fi
echo -e "  ${G}Public Host group created${N}"

# 3. Create subscription client and attach to XHTTP inbound
echo "  Creating subscription client..."
CLIENT_PAYLOAD=$(build_client_payload "$CLIENT_EMAIL" "$CLIENT_ID" "$SUB_ID" "$VLESS_FLOW" "$XHTTP_ID")
CLIENT_RESPONSE=$(xui_json "http://127.0.0.1:2053/panel/api/clients/add" "$CLIENT_PAYLOAD")
if ! echo "$CLIENT_RESPONSE" | jq_success; then
    echo -e "${R}[ERROR]${N} Subscription client creation failed"
    rm "$COOKIE_FILE"
    exit 1
fi
echo -e "  ${G}Subscription client created${N}"

# 4. Configure subscription and panel settings (before credential change, session still valid)
echo "  Configuring panel and subscription settings..."
ALL_SETTINGS_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/setting/all" "{}")
if ! echo "$ALL_SETTINGS_RESP" | jq_success; then
    MSG=$(echo "$ALL_SETTINGS_RESP" | jq -r '.msg // "unknown error"' 2>/dev/null)
    echo -e "${R}[ERROR]${N} Failed to fetch current settings: $MSG"
    rm "$COOKIE_FILE"
    exit 1
fi
XHTTP_XMUX=''

UPDATED_SETTINGS=$(echo "$ALL_SETTINGS_RESP" | jq -c \
    --arg web_base_path "/$ADMIN_PATH/" \
    --arg sub_path "/$SUB_PATH/" \
    --arg json_path "/$JSON_PATH/" \
    --arg clash_path "/$CLASH_PATH/" \
    --arg sub_uri "https://$DOMAIN/$SUB_PATH/" \
    --arg sub_json_uri "https://$DOMAIN/$JSON_PATH/" \
    --arg sub_clash_uri "https://$DOMAIN/$CLASH_PATH/" \
    --arg sub_json_mux "$XHTTP_XMUX" \
    '.obj
     | .webBasePath = $web_base_path
     | .subEnable = true
     | .subPath = $sub_path
     | .subURI = $sub_uri
     | .subJsonEnable = true
     | .subJsonPath = $json_path
     | .subJsonURI = $sub_json_uri
     | .subJsonMux = $sub_json_mux
     | .subClashEnable = true
     | .subClashPath = $clash_path
     | .subClashURI = $sub_clash_uri')
SETTINGS_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/setting/update" "$UPDATED_SETTINGS")
if echo "$SETTINGS_RESP" | jq_success; then
    echo -e "  ${G}Panel and subscription configured${N}"
else
    MSG=$(echo "$SETTINGS_RESP" | jq -r '.msg // "unknown error"' 2>/dev/null)
    echo -e "${Y}Warning:${N} Failed to configure panel settings ($MSG)"
fi

# 5. Update 3x-ui credentials to user-provided values (if different from defaults)
if [ "$XUI_USER" != "admin" ] || [ "$XUI_PASS" != "admin" ]; then
    echo "  Updating 3x-ui credentials..."
    CRED_PAYLOAD=$(jq -nc \
        --arg new_username "$XUI_USER" \
        --arg new_password "$XUI_PASS" \
        '{oldUsername:"admin",oldPassword:"admin",newUsername:$new_username,newPassword:$new_password}')
    CRED_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/setting/updateUser" "$CRED_PAYLOAD")
    if echo "$CRED_RESP" | jq_success; then
        echo -e "  ${G}Credentials updated${N}"
        # Re-login with new credentials so restart call below uses a valid session
        if ! xui_login "$XUI_USER" "$XUI_PASS"; then
            echo -e "${Y}Warning:${N} Re-login after credential change failed"
        fi
    else
        MSG=$(echo "$CRED_RESP" | jq -r '.msg // "unknown error"' 2>/dev/null)
        echo -e "${Y}Warning:${N} Failed to update credentials ($MSG)"
    fi
fi

# 6. Restart panel to apply settings
echo "  Checkpointing DB WAL..."
sqlite3 /opt/serv/3x-ui/db/x-ui.db "PRAGMA wal_checkpoint;" 2>/dev/null || true
echo "  Restarting panel..."
CSRF=$(csrf_token)
curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "http://127.0.0.1:2053/panel/api/setting/restartPanel" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "X-CSRF-Token: $CSRF" \
    -d "{}" > /dev/null || true
sleep 3

rm "$COOKIE_FILE"
echo -e "  ${G}Inbound, Host, and subscription configured via API${N}"

echo -e "${G}[8/8] Done.${N}"

print_summary
