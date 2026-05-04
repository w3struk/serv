#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd -P)"
SERVER_DIR="$(dirname "$SCRIPT_DIR")"

usage() {
    echo "Usage: $0 <domain>"
    echo ""
    echo "Example: $0 mydomain.com"
    exit 1
}

[ $# -lt 1 ] && usage

DOMAIN="$1"
shift

if ! echo "$DOMAIN" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9.-]*[a-zA-Z0-9])?\.[a-zA-Z]{2,}$'; then
    echo "Error: Invalid domain format"
    exit 1
fi

echo "=== steal-oneself Server Setup ==="
echo ""
echo "Domain: $DOMAIN"
echo "Server dir: $SERVER_DIR"
echo ""

echo "[1/5] Creating directories..."
mkdir -p "$SERVER_DIR/3x-ui/db"
mkdir -p "$SERVER_DIR/caddy/data"
mkdir -p "$SERVER_DIR/tmp"

echo "[2/5] Checking Lampac password..."
if [ ! -f "$SERVER_DIR/lampac/passwd" ]; then
    echo "Warning: lampac/passwd not set. Create it manually:"
    echo "  printf '%s' 'your_password' > $SERVER_DIR/lampac/passwd"
else
    echo "  lampac/passwd exists"
fi

echo "[3/5] Updating Caddyfile..."
if grep -q "example.com" "$SERVER_DIR/Caddyfile"; then
    sed -i "s/example.com/$DOMAIN/g" "$SERVER_DIR/Caddyfile"
    echo "  Domain replaced: example.com -> $DOMAIN"
else
    echo "  Domain already set or example.com not found"
fi

echo "[4/5] Generating Caddy bcrypt hash..."
echo "Enter password for admin (will be hashed):"
read -s ADMIN_PASSWORD
echo ""
BCRYPT_HASH=$(docker run --rm -i caddy caddy hash-password <<< "$ADMIN_PASSWORD" 2>/dev/null) || {
    echo "Error: Docker not available. Install Docker first"
    exit 1
}

echo "  BCRYPT_HASH generated"
echo "  Update Caddyfile manually:"
echo "    Replace '\$2a\$14\$HASHEDPASSWORD' with:"
echo "    $BCRYPT_HASH"

echo ""
echo "[5/5] Next steps:"
echo ""
echo "1. Edit Caddyfile and replace the bcrypt hash:"
echo "   nano $SERVER_DIR/Caddyfile"
echo ""
echo "2. Start services:"
echo "   cd $SERVER_DIR && docker compose up -d"
echo ""
echo "3. Set panel base path:"
echo "   docker exec -it 3xui_app /app/x-ui setting -webBasePath /admin-secret-path/"
echo "   docker restart 3xui_app"
echo ""
echo "4. Set up firewall:"
echo "   sudo bash $SCRIPT_DIR/firewall.sh"
echo ""
echo "5. Open https://$DOMAIN/admin-secret-path/"
echo ""
echo "Setup complete"