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
LAMJac_PASSWORD="$(head -c 16 /dev/urandom | base64 | tr -dc 'a-zA-Z0-9' | head -c 16)"
CLIENT_ID=$(cat /proc/sys/kernel/random/uuid)

echo "=== Configuration Summary ==="
echo "Domain:      $DOMAIN"
echo "Admin path:  /$ADMIN_PATH/"
echo "Sub path:    /$SUB_PATH/"
echo "Client UUID: $CLIENT_ID"
echo ""

echo "[1/8] Generating Lampac password..."
printf '%s' "$LAMJac_PASSWORD" > "$SERVER_DIR/lampac/passwd"
echo "  Done"

echo "[2/8] Enabling BBR..."
if ! grep -q "net.core.default_qdisc=fq" /etc/sysctl.conf; then
    echo "net.core.default_qdisc=fq" | tee -a /etc/sysctl.conf
    echo "net.ipv4.tcp_congestion_control=bbr" | tee -a /etc/sysctl.conf
    sysctl -p >/dev/null 2>&1
fi
echo "  BBR enabled"

echo "[3/8] Updating Caddyfile..."
sed -i "s/example\.com/$DOMAIN/g" "$SERVER_DIR/Caddyfile"
# Обновляем пути в Caddyfile, используя формат из шаблона
sed -i "s|/admin-\*|/$ADMIN_PATH/*|g" "$SERVER_DIR/Caddyfile"
sed -i "s|/sub-\*|/$SUB_PATH/*|g" "$SERVER_DIR/Caddyfile"
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
sed -i "s/\\\$2a\\\$14\\\$HASHEDPASSWORD/$BCRYPT_HASH/" "$SERVER_DIR/Caddyfile"
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
mkdir -p "$SERVER_DIR/3x-ui/db"
mkdir -p "$SERVER_DIR/caddy/data"
cd "$SERVER_DIR" && docker compose down && docker compose up -d
echo "  Services started"

echo "[7/8] Configuring 3x-ui Inbounds via API..."
echo "  Waiting for 3x-ui to be ready (max 60s)..."
MAX_RETRIES=30
RETRY_COUNT=0
until curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:2053/login | grep -q "200"; do
    sleep 2
    RETRY_COUNT=$((RETRY_COUNT+1))
    if [ $RETRY_COUNT -ge $MAX_RETRIES ]; then
        echo "Error: 3x-ui failed to start in time"
        exit 1
    fi
done

COOKIE_FILE=$(mktemp)
# Авторизация
LOGIN_RES=$(curl -s -X POST "http://127.0.0.1:2053/login" \
     -d "username=$XUI_USER&password=$XUI_PASS" \
     -c "$COOKIE_FILE")

if [[ ! "$LOGIN_RES" == *"true"* ]]; then
    echo "Error: 3x-ui login failed. Check credentials."
    rm "$COOKIE_FILE"
    exit 1
fi

# 1. Добавляем XHTTP Backend (Порт 2023)
XHTTP_JSON='{
  "enable": true,
  "remark": "VLESS-XHTTP-Backend",
  "listen": "127.0.0.1",
  "port": 2023,
  "protocol": "vless",
  "settings": "{\"clients\": [{\"id\": \"'$CLIENT_ID'\"}], \"decryption\": \"none\", \"fallbacks\": []}",
  "streamSettings": "{\"network\": \"xhttp\", \"security\": \"none\", \"xhttpSettings\": {\"path\": \"/api/v*\", \"mode\": \"request-response\"}}",
  "sniffing": "{\"enabled\": false}",
  "allocate": "{\"strategy\": \"always\", \"refresh\": 5, \"concurrency\": 3}"
}'

curl -s -X POST "http://127.0.0.1:2053/panel/api/inbounds/add" \
     -b "$COOKIE_FILE" \
     -H "Content-Type: application/json" \
     -d "$XHTTP_JSON" > /dev/null

# 2. Добавляем XTLS-Vision Frontend (Порт 443)
CERT_DIR="/etc/x-ui/certs/acme-v02.api.letsencrypt.org-directory/$DOMAIN"
FRONTEND_JSON='{
  "enable": true,
  "remark": "VLESS-TCP-Vision-Frontend",
  "listen": "",
  "port": 443,
  "protocol": "vless",
  "settings": "{\"clients\": [{\"id\": \"'$CLIENT_ID'\", \"flow\": \"xtls-rprx-vision\"}], \"decryption\": \"none\", \"fallbacks\": [{\"dest\": \"2023\", \"xver\": 0, \"path\": \"/api/v*\"}, {\"dest\": \"8080\", \"xver\": 2}]}",
  "streamSettings": "{\"network\": \"tcp\", \"security\": \"tls\", \"tlsSettings\": {\"serverName\": \"'$DOMAIN'\", \"minVersion\": \"1.3\", \"maxVersion\": \"1.3\", \"cipherSuites\": \"\", \"certificates\": [{\"certificateFile\": \"'$CERT_DIR'/'$DOMAIN'.crt\", \"keyFile\": \"'$CERT_DIR'/'$DOMAIN'.key\"}], \"alpn\": [\"h2\", \"http/1.1\"]}}",
  "sniffing": "{\"enabled\": true, \"destOverride\": [\"http\", \"tls\", \"quic\", \"fakedns\"]}",
  "allocate": "{\"strategy\": \"always\", \"refresh\": 5, \"concurrency\": 3}"
}'

curl -s -X POST "http://127.0.0.1:2053/panel/api/inbounds/add" \
     -b "$COOKIE_FILE" \
     -H "Content-Type: application/json" \
     -d "$FRONTEND_JSON" > /dev/null

rm "$COOKIE_FILE"
echo "  Inbounds configured via API"

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
echo "  Lampac:   $LAMJac_PASSWORD"
echo ""
echo "Note: Certificates might take a minute to generate. If the 443 port"
echo "is not working immediately, wait a bit and restart 3x-ui."
