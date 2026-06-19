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
            if iptables-save > /etc/iptables/rules.v4 2>/dev/null; then
                if command -v systemctl >/dev/null 2>&1 && systemctl enable netfilter-persistent >/dev/null 2>&1; then
                    echo -e "  ${G}Firewall rules persisted (netfilter-persistent)${N}"
                else
                    echo -e "  ${Y}Warning:${N} Rules saved to /etc/iptables/rules.v4 but boot service could not be enabled; rules may not survive reboot."
                fi
            else
                echo -e "  ${Y}Warning:${N} iptables-persistent installed but rules save failed."
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

# API helpers (use API_PREFIX for non-install modes like add-client)
csrf_token() {
    curl -s --max-time 5 -b "$COOKIE_FILE" -c "$COOKIE_FILE" "http://127.0.0.1:2053${API_PREFIX}/csrf-token" \
        | jq -r '.obj // empty' 2>/dev/null
}

xui_json() {
    local url="$1" json="$2"
    local token
    token=$(csrf_token)
    curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "$url" \
        -H "Content-Type: application/json" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "X-CSRF-Token: $token" \
        -d "$json"
}

xui_login() {
    local u="$1" p="$2"
    local csrf
    csrf=$(csrf_token)
    [ -z "$csrf" ] && return 1
    local resp
    resp=$(curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
        -X POST "http://127.0.0.1:2053${API_PREFIX}/login" \
        -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
        -H "X-Requested-With: XMLHttpRequest" \
        -H "X-CSRF-Token: $csrf" \
        -d "username=$u&password=$p")
    echo "$resp" | jq_success
}

build_xhttp_payload() {
    jq -nc \
        --arg domain "$1" \
        --arg path "/$2" \
        --arg advanced_obfs "$3" '
        def xhttp_settings:
            {
                path: $path,
                mode: "stream-up",
                headers: {"User-Agent": "chrome"},
                xPaddingBytes: "100-1000",
                xmux: {
                    maxConcurrency: "16-32",
                    hMaxRequestTimes: "600-900",
                    hMaxReusableSecs: "1800-3000"
                }
            } + if $advanced_obfs == "true" then {
                xPaddingObfsMode: true,
                xPaddingKey: "trace",
                xPaddingHeader: "X-Trace-ID",
                xPaddingPlacement: "queryInHeader",
                xPaddingMethod: "tokenish"
            } else {} end;
        {
            up: 0,
            down: 0,
            total: 0,
            remark: "VLESS-XHTTP-Backend",
            enable: true,
            expiryTime: 0,
            listen: "@uds_xhttp",
            port: 0,
            protocol: "vless",
            settings: ({
                clients: [],
                decryption: "none",
                fallbacks: []
            } | tojson),
            streamSettings: ({
                network: "xhttp",
                security: "none",
                sockopt: {acceptProxyProtocol: true, trustedXForwardedFor: ["127.0.0.1/32"]},
                externalProxy: [{
                    dest: $domain,
                    port: 443,
                    forceTls: "tls",
                    remark: "",
                    sni: $domain,
                    fingerprint: "chrome",
                    alpn: ["h2", "http/1.1"]
                }],
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
            } + if $flow != "" then {flow: $flow} else {} end),
            inboundIds: ($inbound_ids | split(",") | map(tonumber))
        }'
}

# Check if docker services are running
check_installed() {
    docker compose ls --filter "name=serv" 2>/dev/null | grep -q "serv" && return 0
    return 1
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

    DOMAIN=$(sed -n '/redir/p' "$SERVER_DIR/Caddyfile" 2>/dev/null | grep -oP 'https://\K[^{}]+' | head -1 | sed 's/{uri} permanent//')

    local ADM=$(grep -oP 'handle /\K[^/]+' "$SERVER_DIR/Caddyfile" 2>/dev/null | grep '^admin-' | head -1)
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
        local resp; resp=$(curl -s --max-time 5 -b "$COOKIE_FILE" "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/list" \
            -H "X-Requested-With: XMLHttpRequest" -H "X-CSRF-Token: $csrf")
        ID_XHTTP=$(echo "$resp" | jq -r '.obj[]? | select(.remark == "VLESS-XHTTP-Backend") | .id' 2>/dev/null | head -1)
    }

    gen_email() {
        echo "$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)@$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4).com"
    }

    get_inbound_ids
    if [ -z "$ID_XHTTP" ]; then
        echo -e "${R}[ERROR]${N} XHTTP inbound (remark VLESS-XHTTP-Backend) was not found"
        rm "$COOKIE_FILE"
        exit 1
    fi

    CID=$(cat /proc/sys/kernel/random/uuid)
    SID=$(head -c 16 /dev/urandom | md5sum | head -c 16)
    EMAIL="${CLIENT_EMAIL:-$(gen_email)}"

    PAYLOAD=$(build_client_payload "$EMAIL" "$CID" "$SID" "" "$ID_XHTTP")
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

    rm "$COOKIE_FILE"
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
        ADMIN_PATH=$(grep -oP 'handle /admin-\w+' "$SERVER_DIR/Caddyfile" | head -1 | sed 's/handle \///')
        SUB_PATH=$(grep -oP 'handle /sub-\w+' "$SERVER_DIR/Caddyfile" | head -1 | sed 's/handle \///')
        JSON_PATH=$(grep -oP 'handle /json[^/]*' "$SERVER_DIR/Caddyfile" | head -1 | sed 's/handle \///')
        CLASH_PATH=$(grep -oP 'handle /clash[^/]*' "$SERVER_DIR/Caddyfile" | head -1 | sed 's/handle \///')
        DOMAIN=$(sed -n '/redir/p' "$SERVER_DIR/Caddyfile" | grep -oP 'https://\K[^{}]+' | head -1 | sed 's/{uri} permanent//')
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
    | ($inbound | settings_obj | (.clients // [])) as $clients
    | [
        "  \($inbound.remark // $inbound.tag // "") (\($inbound.port // ""), \($inbound.streamSettings.network // "tcp"), \($inbound.streamSettings.security // "none")) - \($clients | length) client(s)",
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

echo -e "${G}=== Configuration Summary ===${N}"
echo -e "${Y}Domain:${N}      ${C}$DOMAIN${N}"
echo -e "${Y}Admin path:${N}  /$ADMIN_PATH/"
echo -e "${Y}Sub path:${N}    /$SUB_PATH/"
echo -e "${Y}JSON path:${N}   /$JSON_PATH/"
echo -e "${Y}Clash path:${N}  /$CLASH_PATH/"
echo -e "${Y}XHTTP path:${N}  /$XHTTP_PATH/"
echo -e "${Y}XHTTP UUID:${N}  ${C}$CLIENT_ID${N}"
echo -e "${Y}Advanced XHTTP padding:${N} $XHTTP_ADVANCED_OBFS"
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
persist_firewall
echo -e "  ${G}Firewall configured${N}"

echo -e "${G}[6/8]${N} Starting services..."
cd "$SERVER_DIR" && docker compose down && docker compose up -d
echo -e "  ${G}Services started${N}"

echo -e "${G}[7/8]${N} Configuring 3x-ui Inbounds via API..."
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

# 1. Add XHTTP Backend (UDS @uds_xhttp, port 0)
echo "  Adding XHTTP Backend inbound..."
XHTTP_PAYLOAD=$(build_xhttp_payload "$DOMAIN" "$XHTTP_PATH" "$XHTTP_ADVANCED_OBFS")
XHTTP_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/inbounds/add" "$XHTTP_PAYLOAD") || true
if ! echo "$XHTTP_RESP" | jq_success; then
    echo -e "${R}[ERROR]${N} XHTTP Backend creation failed"
    exit 1
fi
XHTTP_ID=$(echo "$XHTTP_RESP" | jq -r '.obj.id // empty')

# 2. Create subscription client and attach to XHTTP inbound
echo "  Creating subscription client..."
CLIENT_PAYLOAD=$(build_client_payload "$CLIENT_EMAIL" "$CLIENT_ID" "$SUB_ID" "" "$XHTTP_ID")
CLIENT_RESPONSE=$(xui_json "http://127.0.0.1:2053/panel/api/clients/add" "$CLIENT_PAYLOAD")
if ! echo "$CLIENT_RESPONSE" | jq_success; then
    echo -e "${R}[ERROR]${N} Subscription client creation failed"
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
echo -e "  ${G}Inbounds and subscription configured via API${N}"

echo -e "${G}[8/8] Done.${N}"

print_summary
