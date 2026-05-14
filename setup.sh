#!/bin/bash
set -e

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

# API helpers (use API_PREFIX for non-install modes like add-client)
csrf_token() {
    curl -s --max-time 5 -b "$COOKIE_FILE" -c "$COOKIE_FILE" "http://127.0.0.1:2053${API_PREFIX}/csrf-token" \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['obj'])"
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
    echo "$resp" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null
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
        echo -e "${B}Subscription links:${N}"
        if [ "$UUID_MODE" = "2" ]; then
            echo -e "  ${C}XHTTP:${N}  https://${C}$DOMAIN${N}/$SUB_PATH/$SUB_ID"
            echo -e "  ${C}Vision:${N} https://${C}$DOMAIN${N}/$SUB_PATH/$SUB_ID_VISION"
        else
            echo -e "  ${C}Single:${N} https://${C}$DOMAIN${N}/$SUB_PATH/$SUB_ID"
        fi
        echo ""
    fi
    echo -e "${B}Credentials:${N}"
    echo -e "  ${Y}Web Auth:${N} admin / [your password]"
    echo -e "  ${Y}3x-ui:${N}    $XUI_USER / ${G}$XUI_PASS${N}"
    if [ -n "$CLIENT_ID" ]; then
        echo -e "  ${Y}XHTTP UUID:${N} ${C}$CLIENT_ID${N}"
    fi
    if [ -n "$CLIENT_ID_VISION" ]; then
        echo -e "  ${Y}Vision UUID:${N} ${C}$CLIENT_ID_VISION${N}"
    fi
    if [ -n "$SUB_ID_VISION" ]; then
        echo -e "  ${Y}Vision SubID:${N} ${C}$SUB_ID_VISION${N}"
    fi
    if [ -n "$XHTTP_PATH" ]; then
        echo -e "  ${Y}XHTTP path:${N} /$XHTTP_PATH/"
    fi
    if [ -n "$LAMJac_PASSWORD" ]; then
        echo -e "  ${Y}Lampac:${N}   $LAMJac_PASSWORD"
    fi
    echo ""
    echo -e "${Y}Note: Certificates might take a minute to generate.${N}"
    echo -e "${Y}If the 443 port is not working immediately, wait a bit and restart 3x-ui.${N}"
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

    echo ""
    echo "Client Configuration:"
    echo "  1) Single UUID for both inbounds"
    echo "  2) Different UUIDs, separate subscriptions"
    read -p "Choose (default: 1): " UUID_MODE
    UUID_MODE=${UUID_MODE:-1}
    echo ""

    read -p "Enter client email/purpose (or press Enter for auto): " CLIENT_EMAIL
    echo ""

    local csrf

    get_inbound_ids() {
        local csrf; csrf=$(csrf_token)
        local resp; resp=$(curl -s --max-time 5 -b "$COOKIE_FILE" "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/list" \
            -H "X-Requested-With: XMLHttpRequest" -H "X-CSRF-Token: $csrf")
        ID_XHTTP=$(echo "$resp" | python3 -c "import sys,json; [print(i['id']) for i in json.load(sys.stdin)['obj'] if i.get('port')==2023]" 2>/dev/null)
        ID_VISION=$(echo "$resp" | python3 -c "import sys,json; [print(i['id']) for i in json.load(sys.stdin)['obj'] if i.get('port')==443]" 2>/dev/null)
    }

    gen_email() {
        echo "$(tr -dc 'a-z0-9' < /dev/urandom | head -c 8)@$(tr -dc 'a-z0-9' < /dev/urandom | head -c 4).com"
    }

    add_client_to_inbound() {
        local id="$1" cid="$2" sid="$3" email="$4" flow="$5"
        local csv="{\\\"id\\\":\\\"$cid\\\",\\\"email\\\":\\\"$email\\\",\\\"subId\\\":\\\"$sid\\\"}"
        [ -n "$flow" ] && csv="{\\\"id\\\":\\\"$cid\\\",\\\"flow\\\":\\\"$flow\\\",\\\"email\\\":\\\"$email\\\",\\\"subId\\\":\\\"$sid\\\"}"
        local csrf; csrf=$(csrf_token)
        curl -s --max-time 5 -b "$COOKIE_FILE" -X POST "http://127.0.0.1:2053${API_PREFIX}/panel/api/inbounds/addClient" \
            -H "Content-Type: application/json" -H "X-Requested-With: XMLHttpRequest" -H "X-CSRF-Token: $csrf" \
            -d "{\"id\":$id,\"settings\":\"{\\\"clients\\\":[${csv}]}\"}" | \
        python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null
    }

    get_inbound_ids

    if [ "$UUID_MODE" = "2" ]; then
        CID1=$(cat /proc/sys/kernel/random/uuid)
        CID2=$(cat /proc/sys/kernel/random/uuid)
        SID1=$(head -c 16 /dev/urandom | md5sum | head -c 16)
        SID2=$(head -c 16 /dev/urandom | md5sum | head -c 16)
        EMAIL1="${CLIENT_EMAIL:-$(gen_email)}"
        EMAIL2="${CLIENT_EMAIL:-$(gen_email)}"

        if add_client_to_inbound "$ID_XHTTP" "$CID1" "$SID1" "$EMAIL1" ""; then
            echo -e "  ${G}[OK]${N} XHTTP client added"
        else
            echo -e "  ${R}[ERROR]${N} Failed to add XHTTP client"
        fi
        if add_client_to_inbound "$ID_VISION" "$CID2" "$SID2" "$EMAIL2" "xtls-rprx-vision"; then
            echo -e "  ${G}[OK]${N} Vision client added"
        else
            echo -e "  ${R}[ERROR]${N} Failed to add Vision client"
        fi

        echo ""
        echo -e "${G}╔══════════════════════════════════════╗${N}"
        echo -e "${G}║     ${B}Client Added${N}${G}                  ║${N}"
        echo -e "${G}╚══════════════════════════════════════╝${N}"
        echo ""
        SUB_PATH=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='subPath' LIMIT 1;" 2>/dev/null || echo "/sub/")
        echo -e "${B}Subscription links:${N}"
        echo -e "  ${C}XHTTP:${N}  https://${C}${DOMAIN}${N}${SUB_PATH}${SID1}  (${EMAIL1})"
        echo -e "  ${C}Vision:${N} https://${C}${DOMAIN}${N}${SUB_PATH}${SID2}  (${EMAIL2})"
        echo ""
        echo -e "${B}UUIDs:${N}"
        echo -e "  ${Y}XHTTP:${N}  ${C}$CID1${N}"
        echo -e "  ${Y}Vision:${N} ${C}$CID2${N}"

    else
        CID=$(cat /proc/sys/kernel/random/uuid)
        SID=$(head -c 16 /dev/urandom | md5sum | head -c 16)
        EMAIL="${CLIENT_EMAIL:-$(gen_email)}"

        if add_client_to_inbound "$ID_XHTTP" "$CID" "$SID" "$EMAIL" ""; then
            echo -e "  ${G}[OK]${N} Client added to XHTTP backend"
        else
            echo -e "  ${R}[ERROR]${N} Failed to add client to XHTTP backend"
        fi
        if add_client_to_inbound "$ID_VISION" "$CID" "$SID" "$EMAIL" "xtls-rprx-vision"; then
            echo -e "  ${G}[OK]${N} Client added to Vision frontend"
        else
            echo -e "  ${R}[ERROR]${N} Failed to add client to Vision frontend"
        fi

        echo ""
        echo -e "${G}╔══════════════════════════════════════╗${N}"
        echo -e "${G}║     ${B}Client Added${N}${G}                  ║${N}"
        echo -e "${G}╚══════════════════════════════════════╝${N}"
        echo ""
        SUB_PATH=$(sqlite3 /opt/serv/3x-ui/db/x-ui.db "SELECT value FROM settings WHERE key='subPath' LIMIT 1;" 2>/dev/null || echo "/sub/")
        echo -e "${B}Subscription link:${N}"
        echo -e "  ${C}Single:${N} https://${C}${DOMAIN}${N}${SUB_PATH}${SID}  (${EMAIL})"
        echo ""
        echo -e "${B}UUID:${N} ${C}$CID${N}"
    fi

    rm "$COOKIE_FILE"
}

show_status() {
    print_banner
    echo -e "${B}Docker Containers:${N}"
    local names="caddy lampac 3xui_app"
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
    local XHTTP_PATH=""

    # Read config from Caddyfile
    if [ -f "$SERVER_DIR/Caddyfile" ]; then
        ADMIN_PATH=$(grep -oP 'handle /admin-\w+' "$SERVER_DIR/Caddyfile" | head -1 | sed 's/handle \///')
        SUB_PATH=$(grep -oP 'handle /sub-\w+' "$SERVER_DIR/Caddyfile" | head -1 | sed 's/handle \///')
        DOMAIN=$(sed -n '/redir/p' "$SERVER_DIR/Caddyfile" | grep -oP 'https://\K[^{}]+' | head -1 | sed 's/{uri} permanent//')
    fi

    if [ -n "$DOMAIN" ]; then
        echo -e "${B}Domain:${N} ${C}$DOMAIN${N}"
        echo ""
        echo -e "${B}URLs:${N}"
        [ -n "$ADMIN_PATH" ] && echo -e "  ${C}Panel:${N} https://$DOMAIN/$ADMIN_PATH/"
        [ -n "$SUB_PATH" ]   && echo -e "  ${C}Sub:${N}   https://$DOMAIN/$SUB_PATH/"
    fi

    echo ""
    echo -e "${B}Inbounds & Clients:${N}"
    if docker exec 3xui_app cat bin/config.json 2>/dev/null | python3 -c "
import sys, json
c = json.load(sys.stdin)
found = False
for i in c.get('inbounds', []):
    t = i.get('tag', '')
    if 'api' in t: continue
    port = i.get('port', '')
    net = i.get('streamSettings', {}).get('network', 'tcp')
    sec = i.get('streamSettings', {}).get('security', 'none')
    settings = i.get('settings', {})
    if isinstance(settings, str):
        try: import json; settings = json.loads(settings)
        except: settings = {}
    clients = settings.get('clients', [])
    count = len(clients)
    remark = i.get('remark', t)
    print(f'  {remark} ({port}, {net}, {sec}) - {count} client(s)')
    for cl in clients:
        uid = cl.get('id', '')[:8]
        sub = cl.get('subId', '')
        flow = cl.get('flow', '')
        email = cl.get('email', '')
        fstr = f' flow={flow}' if flow else ''
        estr = f' email={email}' if email else ''
        print(f'    └ {uid}... sub={sub}{fstr}{estr}')
    found = True
if not found:
    print('  (none)')
" 2>/dev/null; then
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
    echo -e "  (no args)    ${C}Full installation${N}  — setup everything from scratch"
    echo -e "  ${C}add-client${N}   ${Y}Add new client${N}      — add client(s) to existing installation"
    echo -e "  ${C}status${N}       ${Y}Show status${N}         — display current configuration"
    echo -e "  ${C}help${N}         ${Y}Show help${N}"
    echo ""
    echo -e "${B}Examples:${N}"
    echo -e "  $0                  # Full install"
    echo -e "  $0 add-client       # Add new client"
    echo -e "  $0 status           # Show status"
    echo ""
}

# ─── CLI dispatch ──────────────────────────────────────────────────────────────
case "${1:-install}" in
    help|--help|-h)
        show_help
        exit 0
        ;;
    add-client)
        add_client
        exit 0
        ;;
    status)
        check_installed || {
            echo -e "${R}[ERROR]${N} Installation not found."
            exit 1
        }
        show_status
        exit 0
        ;;
    install)
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
echo "How to handle client IDs for the two inbounds (XHTTP backend + Vision frontend):"
echo ""
echo "  1) Single ID (UUID) for both inbounds"
echo "     One subscription returns both configs. Simpler setup."
echo "  2) Different UUIDs, separate subscriptions"
echo "     Each inbound has its own UUID and subscription link."
echo ""
read -p "Choose (default: 1): " UUID_MODE
UUID_MODE=${UUID_MODE:-1}
echo ""

ADMIN_PATH="admin-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
SUB_PATH="sub-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
XHTTP_PATH="api/v$(shuf -i 1-999 -n 1)"
LAMJac_PASSWORD="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"

if [ "$UUID_MODE" = "2" ]; then
    CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)
    CLIENT_ID_VISION=$(cat /proc/sys/kernel/random/uuid)
    SUB_ID=$(head -c 16 /dev/urandom | md5sum | head -c 16)
    SUB_ID_VISION=$(head -c 16 /dev/urandom | md5sum | head -c 16)
else
    CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)
    SUB_ID=$(head -c 16 /dev/urandom | md5sum | head -c 16)
fi

echo -e "${G}=== Configuration Summary ===${N}"
echo -e "${Y}Domain:${N}      ${C}$DOMAIN${N}"
echo -e "${Y}Admin path:${N}  /$ADMIN_PATH/"
echo -e "${Y}Sub path:${N}    /$SUB_PATH/"
echo -e "${Y}XHTTP path:${N}  /$XHTTP_PATH/"
if [ "$UUID_MODE" = "2" ]; then
    echo -e "${Y}XHTTP UUID:${N}  ${C}$CLIENT_ID${N}"
    echo -e "${Y}Vision UUID:${N} ${C}$CLIENT_ID_VISION${N}"
fi
echo -e "${Y}Client UUID:${N} ${C}$CLIENT_ID${N}"
echo ""

echo -e "${G}[1/8]${N} Preparing directories and Lampac password..."
mkdir -p "$SERVER_DIR/lampac/config"
mkdir -p "$SERVER_DIR/3x-ui/db"
mkdir -p "$SERVER_DIR/caddy/data"
printf '%s' "$LAMJac_PASSWORD" > "$SERVER_DIR/lampac/config/passwd"
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
iptables -P INPUT ACCEPT
iptables -F
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -P INPUT DROP
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

# 1. Add XHTTP Backend (Port 2023)
echo "  Adding XHTTP Backend inbound..."
XHTTP_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/inbounds/add" '{
  "up": 0, "down": 0, "total": 0,
  "remark": "VLESS-XHTTP-Backend", "enable": true, "expiryTime": 0,
  "listen": "127.0.0.1", "port": 2023, "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"'"$CLIENT_ID"'\",\"subId\":\"'"$SUB_ID"'\"}],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"xhttp\",\"security\":\"none\",\"externalProxy\":[{\"dest\":\"'"$DOMAIN"'\",\"port\":443,\"forceTls\":\"tls\",\"remark\":\"\"}],\"xhttpSettings\":{\"path\":\"'"/$XHTTP_PATH"'\",\"mode\":\"auto\"},\"finalmask\":{}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"],\"routeOnly\":true}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}') || true
if ! echo "$XHTTP_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
    echo -e "${Y}Warning:${N} XHTTP Backend creation failed (may already exist)"
fi

# 2. Add XTLS-Vision Frontend (Port 443)
echo "  Adding XTLS-Vision Frontend inbound..."
CERT_DIR="/etc/x-ui/certs/acme-v02.api.letsencrypt.org-directory/$DOMAIN"
FRONTEND_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/inbounds/add" '{
  "up": 0, "down": 0, "total": 0,
  "remark": "VLESS-TCP-Vision-Frontend", "enable": true, "expiryTime": 0,
  "listen": "", "port": 443, "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"'"${CLIENT_ID_VISION:-$CLIENT_ID}"'\",\"flow\":\"xtls-rprx-vision\",\"subId\":\"'"${SUB_ID_VISION:-$SUB_ID}"'\"}],\"decryption\":\"none\",\"fallbacks\":[{\"dest\":\"8080\",\"xver\":2}]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"'"$DOMAIN"'\",\"minVersion\":\"1.3\",\"maxVersion\":\"1.3\",\"cipherSuites\":\"\",\"certificates\":[{\"certificateFile\":\"'"$CERT_DIR/$DOMAIN"'.crt\",\"keyFile\":\"'"$CERT_DIR/$DOMAIN"'.key\"}],\"alpn\":[\"h2\",\"http/1.1\"]}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\"],\"routeOnly\":true}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}') || true
if ! echo "$FRONTEND_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
    echo -e "${Y}Warning:${N} Frontend inbound creation failed (certs may not be ready yet)"
fi

# 3. Update 3x-ui credentials to user-provided values (if different from defaults)
if [ "$XUI_USER" != "admin" ] || [ "$XUI_PASS" != "admin" ]; then
    echo "  Updating 3x-ui credentials..."
    CRED_RESP=$(xui_json "http://127.0.0.1:2053/panel/setting/updateUser" \
        '{"oldUsername":"admin","oldPassword":"admin","newUsername":"'"$XUI_USER"'","newPassword":"'"$XUI_PASS"'"}')
    if echo "$CRED_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
        echo -e "  ${G}Credentials updated${N}"
    else
        echo -e "${Y}Warning:${N} Failed to update credentials"
    fi
fi

# 4. Configure subscription and panel settings
echo "  Configuring panel and subscription settings..."
ALL_SETTINGS_RESP=$(xui_json "http://127.0.0.1:2053/panel/setting/all" "{}")
UPDATED_SETTINGS=$(echo "$ALL_SETTINGS_RESP" | python3 -c "
import sys, json
data = json.load(sys.stdin)
obj = data['obj']
obj['webBasePath'] = '/$ADMIN_PATH/'
obj['subEnable'] = True
obj['subPath'] = '/$SUB_PATH/'
obj['subURI'] = 'https://$DOMAIN/$SUB_PATH/'
print(json.dumps(obj))
")
SETTINGS_RESP=$(xui_json "http://127.0.0.1:2053/panel/setting/update" "$UPDATED_SETTINGS")
if echo "$SETTINGS_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
    echo -e "  ${G}Panel and subscription configured${N}"
else
    echo -e "${Y}Warning:${N} Failed to configure panel settings"
fi

# 5. Restart panel to apply settings
echo "  Restarting panel..."
CSRF=$(csrf_token)
curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" -X POST "http://127.0.0.1:2053/panel/setting/restartPanel" \
    -H "Content-Type: application/json" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "X-CSRF-Token: $CSRF" \
    -d "{}" > /dev/null || true
sleep 3

rm "$COOKIE_FILE"
echo -e "  ${G}Inbounds and subscription configured via API${N}"

echo -e "${G}[8/8] Done.${N}"

print_summary
