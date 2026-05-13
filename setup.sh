#!/bin/bash
set -e

if [ "$EUID" -ne 0 ]; then
    echo "Error: Run as root"
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SERVER_DIR="$SCRIPT_DIR"

usage() {
    echo "Usage: $0"
    echo ""
    echo "Domain and credentials will be prompted interactively."
    exit 1
}

[ $# -gt 0 ] && usage

echo "=== steal-oneself Server Setup ==="
echo ""

read -p "Domain (e.g. mydomain.com): " DOMAIN
if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$'; then
    echo "Error: Invalid domain format"
    exit 1
fi

echo ""
echo "--- 3x-ui Panel Credentials ---"
read -p "3x-ui Username (default: admin): " XUI_USER
XUI_USER=${XUI_USER:-admin}
read -s -p "3x-ui Password (default: admin): " XUI_PASS
echo ""
XUI_PASS=${XUI_PASS:-admin}
echo "-------------------------------"
echo ""

ADMIN_PATH="admin-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
SUB_PATH="sub-$(head -c 8 /dev/urandom | base64 | tr -dc 'a-z0-9' | head -c 8)"
XHTTP_PATH="api/v$(shuf -i 1-999 -n 1)"
LAMJac_PASSWORD="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)

echo "=== Configuration Summary ==="
echo "Domain:      $DOMAIN"
echo "Admin path:  /$ADMIN_PATH/"
echo "Sub path:    /$SUB_PATH/"
echo "XHTTP path:  /$XHTTP_PATH/"
echo "Client UUID: $CLIENT_ID"
echo ""

echo "[1/8] Preparing directories and Lampac password..."
mkdir -p "$SERVER_DIR/lampac/config"
mkdir -p "$SERVER_DIR/3x-ui/db"
mkdir -p "$SERVER_DIR/caddy/data"
printf '%s' "$LAMJac_PASSWORD" > "$SERVER_DIR/lampac/config/passwd"
echo "  Done"

echo "[2/8] Enabling BBR..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi
echo "  BBR enabled"

echo "[3/8] Generating Caddyfile from template..."
if [ ! -f "$SERVER_DIR/Caddyfile.template" ]; then
    echo "Error: Caddyfile.template not found"
    exit 1
fi
cp "$SERVER_DIR/Caddyfile.template" "$SERVER_DIR/Caddyfile"
sed -i "s|\$DOMAIN|$DOMAIN|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$ADMIN_PATH|$ADMIN_PATH|g" "$SERVER_DIR/Caddyfile"
sed -i "s|\$SUB_PATH|$SUB_PATH|g" "$SERVER_DIR/Caddyfile"
echo "  Domain and paths updated"

echo "[4/8] Generating Caddy bcrypt hash..."
read -s -p "Enter password for web basic_auth: " WEB_PASSWORD
echo ""
if ! command -v docker &> /dev/null; then
    echo "Error: Docker not found. Install Docker first."
    exit 1
fi
BCRYPT_HASH=$(docker run --rm -i caddy caddy hash-password <<< "$WEB_PASSWORD" 2>/dev/null) || {
    echo "Error: Failed to generate bcrypt hash"
    exit 1
}
sed -i "s|\$WEB_PASSWORD_HASH|$BCRYPT_HASH|g" "$SERVER_DIR/Caddyfile"
echo "  Caddy bcrypt hash updated"

echo "[5/8] Configuring firewall..."
iptables -P INPUT ACCEPT
iptables -F
iptables -A INPUT -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A INPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --dport 80 -j ACCEPT
iptables -A INPUT -p tcp --dport 443 -j ACCEPT
iptables -A INPUT -p udp --dport 443 -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -P INPUT DROP
echo "  Firewall configured (basic rules)"

echo "[6/8] Starting services..."
cd "$SERVER_DIR" && docker compose down && docker compose up -d
echo "  Services started"

echo "[7/8] Configuring 3x-ui Inbounds via API..."
echo "  Waiting for 3x-ui to be ready (max 60s)..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:2053/csrf-token | grep -q "200"; do
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "Error: 3x-ui failed to start in time"
        exit 1
    fi
done

COOKIE_FILE=$(mktemp)

# Helper: extract CSRF token from GET /csrf-token (also updates session cookie)
csrf_token() {
    curl -s --max-time 5 -b "$COOKIE_FILE" -c "$COOKIE_FILE" http://127.0.0.1:2053/csrf-token \
        | python3 -c "import sys,json; print(json.load(sys.stdin)['obj'])"
}

# Helper: POST JSON to 3x-ui API with CSRF + session cookie
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

echo "  Getting CSRF token..."
CSRF_TOKEN=$(csrf_token)
if [ -z "$CSRF_TOKEN" ]; then
    echo "Error: Failed to get CSRF token"
    rm "$COOKIE_FILE"
    exit 1
fi

echo "  Logging in with default credentials (admin/admin)..."
LOGIN_RESP=$(curl -s --max-time 10 -b "$COOKIE_FILE" -c "$COOKIE_FILE" \
    -X POST "http://127.0.0.1:2053/login" \
    -H "Content-Type: application/x-www-form-urlencoded; charset=UTF-8" \
    -H "X-Requested-With: XMLHttpRequest" \
    -H "X-CSRF-Token: $CSRF_TOKEN" \
    -d "username=admin&password=admin")

if ! echo "$LOGIN_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
    echo "Error: 3x-ui login failed. Check if the panel is running with default credentials (admin/admin)."
    rm "$COOKIE_FILE"
    exit 1
fi

# 1. Add XHTTP Backend (Port 2023)
echo "  Adding XHTTP Backend inbound..."
XHTTP_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/inbounds/add" '{
  "up": 0, "down": 0, "total": 0,
  "remark": "VLESS-XHTTP-Backend", "enable": true, "expiryTime": 0,
  "listen": "127.0.0.1", "port": 2023, "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"'"$CLIENT_ID"'\"}],\"decryption\":\"none\",\"fallbacks\":[]}",
  "streamSettings": "{\"network\":\"xhttp\",\"security\":\"none\",\"externalProxy\":[{\"dest\":\"'"$DOMAIN"'\",\"port\":443,\"forceTls\":\"same\"}],\"xhttpSettings\":{\"path\":\"'"/$XHTTP_PATH"'\",\"mode\":\"auto\"}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"]}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}') || true
if ! echo "$XHTTP_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
    echo "Warning: XHTTP Backend creation failed (may already exist)"
fi

# 2. Add XTLS-Vision Frontend (Port 443)
echo "  Adding XTLS-Vision Frontend inbound..."
CERT_DIR="/etc/x-ui/certs/acme-v02.api.letsencrypt.org-directory/$DOMAIN"
FRONTEND_RESP=$(xui_json "http://127.0.0.1:2053/panel/api/inbounds/add" '{
  "up": 0, "down": 0, "total": 0,
  "remark": "VLESS-TCP-Vision-Frontend", "enable": true, "expiryTime": 0,
  "listen": "", "port": 443, "protocol": "vless",
  "settings": "{\"clients\":[{\"id\":\"'"$CLIENT_ID"'\",\"flow\":\"xtls-rprx-vision\"}],\"decryption\":\"none\",\"fallbacks\":[{\"dest\":\"2023\",\"xver\":0,\"path\":\"'"/$XHTTP_PATH"'"},{\"dest\":\"8080\",\"xver\":2}]}",
  "streamSettings": "{\"network\":\"tcp\",\"security\":\"tls\",\"tlsSettings\":{\"serverName\":\"'"$DOMAIN"'\",\"minVersion\":\"1.3\",\"maxVersion\":\"1.3\",\"cipherSuites\":\"\",\"certificates\":[{\"certificateFile\":\"'"$CERT_DIR/$DOMAIN"'.crt\",\"keyFile\":\"'"$CERT_DIR/$DOMAIN"'.key\"}],\"alpn\":[\"h2\",\"http/1.1\"]}}",
  "sniffing": "{\"enabled\":true,\"destOverride\":[\"http\",\"tls\",\"quic\",\"fakedns\"]}",
  "allocate": "{\"strategy\":\"always\",\"refresh\":5,\"concurrency\":3}"
}') || true
if ! echo "$FRONTEND_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
    echo "Warning: Frontend inbound creation failed (certs may not be ready yet)"
fi

# 3. Update 3x-ui credentials to user-provided values (if different from defaults)
if [ "$XUI_USER" != "admin" ] || [ "$XUI_PASS" != "admin" ]; then
    echo "  Updating 3x-ui credentials..."
    CRED_RESP=$(xui_json "http://127.0.0.1:2053/panel/setting/updateUser" \
        '{"oldUsername":"admin","oldPassword":"admin","newUsername":"'"$XUI_USER"'","newPassword":"'"$XUI_PASS"'"}')
    if echo "$CRED_RESP" | python3 -c "import sys,json; sys.exit(0 if json.load(sys.stdin).get('success') else 1)" 2>/dev/null; then
        echo "  Credentials updated"
    else
        echo "Warning: Failed to update credentials"
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
    echo "  Panel and subscription configured"
else
    echo "Warning: Failed to configure panel settings"
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
echo "  Inbounds and subscription configured via API"

echo "[8/8] Done."
echo ""
echo "=== Setup Complete ==="
echo "URLs:"
echo "  Panel:  https://$DOMAIN/$ADMIN_PATH/"
echo "  Sub:    https://$DOMAIN/$SUB_PATH/"
echo ""
echo "Credentials:"
echo "  Web Auth: admin / [your password]"
echo "  3x-ui:    $XUI_USER / $XUI_PASS"
echo "  UUID:     $CLIENT_ID"
echo "  XHTTP:    /$XHTTP_PATH/"
echo "  Lampac:   $LAMJac_PASSWORD"
echo ""
echo "Note: Certificates might take a minute to generate. If the 443 port"
echo "is not working immediately, wait a bit and restart 3x-ui."
