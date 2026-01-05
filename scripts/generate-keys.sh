#!/usr/bin/env bash
# Zanjir - Matrix Signing Key Generator
# Generates the Dendrite Matrix signing key using Docker

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEY_FILE="$PROJECT_DIR/dendrite/matrix_key.pem"

echo "[*] Generating Matrix signing key..."

# Check if key already exists
if [ -f "$KEY_FILE" ]; then
    echo "[!] Key already exists: $KEY_FILE"
    read -p "Do you want to generate a new key? (y/N): " confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo "[-] Cancelled."
        exit 0
    fi
    echo "[*] Removing old key..."
    rm -f "$KEY_FILE"
fi

# Generate key using Docker
echo "[*] Generating key with Dendrite..."

docker run --rm \
    -v "$PROJECT_DIR/dendrite:/etc/dendrite" \
    matrixdotorg/dendrite-monolith:latest \
    /usr/bin/generate-keys \
    --private-key /etc/dendrite/matrix_key.pem

# Verify key was created
if [ -f "$KEY_FILE" ]; then
    echo "[+] Key generated successfully: $KEY_FILE"
    chmod 600 "$KEY_FILE"
    echo "[+] File permissions set."
else
    echo "[-] Error generating key!"
    exit 1
fi

